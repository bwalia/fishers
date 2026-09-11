use crate::services::ollama::Ollama;
use crate::services::storage::Storage;
use fishers_agent::AgentService;
use fishers_domain::ResourceTable;
use fishers_notifications::whatsapp::WhatsAppService;
use fishers_notifications::{EmailService, PushService};
use fishers_payments::StripeClient;
use sqlx::PgPool;

#[derive(Clone)]
pub struct AppState {
    pub pool: PgPool,
    pub jwt_secret: String,
    pub access_ttl_secs: i64,
    pub refresh_ttl_secs: i64,
    pub stripe: StripeClient,
    pub push: PushService,
    /// Reads chat threads and proposes admin; disabled without ANTHROPIC_API_KEY.
    pub agent: AgentService,
    pub email: EmailService,
    /// Phone verification codes, via Meta's WhatsApp Cloud API. Off without WHATSAPP_TOKEN.
    pub whatsapp: WhatsAppService,
    /// Duckworth–Lewis resources. Swap in a league's own table by pointing
    /// `DLS_RESOURCE_TABLE` at a CSV of `overs,w0,w1,…,w9` rows.
    pub dls: ResourceTable,
    pub g50: f64,
    /// Writes a line of colour over the top of the one the log already gives.
    /// `None` without OLLAMA_URL, and commentary then stays as written.
    pub ollama: Option<Ollama>,
    /// Object storage for uploads. `None` when the server has no bucket.
    pub storage: Option<Storage>,
    /// Changes to push to connected browsers; see `live`.
    pub live: crate::live::Live,
    /// VERIFICATION_REQUIRED: whether starting a club or accepting an invite
    /// needs a confirmed email or phone. Off until the codes are ready to rely
    /// on — and separate from whether email is configured, so switching on
    /// SMTP for reminders never locks anybody out by surprise.
    pub verification_required: bool,
}

impl AppState {
    pub fn new(pool: PgPool, jwt_secret: String, push: PushService) -> Self {
        let access_ttl_secs = std::env::var("JWT_ACCESS_TTL_SECS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(900);
        let refresh_ttl_secs = std::env::var("JWT_REFRESH_TTL_SECS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(2_592_000);
        // Before the struct: `pool` moves into it below.
        let live = crate::live::Live::spawn(pool.clone());
        Self {
            pool,
            jwt_secret,
            access_ttl_secs,
            refresh_ttl_secs,
            stripe: StripeClient::from_env(),
            push,
            agent: AgentService::from_env(),
            email: EmailService::from_env(),
            whatsapp: WhatsAppService::from_env(),
            dls: load_dls_table(),
            g50: std::env::var("DLS_G50")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(fishers_domain::dls::DEFAULT_G50),
            ollama: Ollama::from_env(),
            storage: Storage::from_env(),
            live,
            verification_required: matches!(
                std::env::var("VERIFICATION_REQUIRED").as_deref(),
                Ok("true" | "1" | "yes")
            ),
        }
    }

    /// Tell somebody something happened.
    ///
    /// Always stored, then pushed. The push half is still an APNs stub, so
    /// storing is what makes a notification real: the app reads them back the
    /// next time it is opened, and a promise of "they'll be told" stops being
    /// a lie whether or not a device is registered.
    pub async fn notify(
        &self,
        user_id: uuid::Uuid,
        kind: &str,
        title: &str,
        body: &str,
        payload: serde_json::Value,
    ) {
        if let Err(error) =
            fishers_db::repos::notifications::record(&self.pool, user_id, kind, &payload).await
        {
            tracing::warn!(%error, kind, "could not store a notification");
        }
        if let Err(error) = self
            .push
            .send(&self.pool, user_id, kind, title, body, payload)
            .await
        {
            tracing::warn!(%error, kind, "push failed");
        }
    }
}

/// The built-in table is a documented approximation. A league holding the
/// official Standard Edition table can drop it in as CSV and the scorecard
/// will say so.
fn load_dls_table() -> ResourceTable {
    let Ok(path) = std::env::var("DLS_RESOURCE_TABLE") else {
        return ResourceTable::default();
    };
    // Set-but-empty is "use the built-in table", not "open a file named ''".
    // .env.example ships `DLS_RESOURCE_TABLE=`, so every plain `cargo run`
    // logged a read error at startup for a file nobody asked for.
    if path.trim().is_empty() {
        return ResourceTable::default();
    }
    match std::fs::read_to_string(&path) {
        Ok(csv) => match parse_resource_csv(&csv) {
            Ok(table) => {
                tracing::info!(%path, "loaded a supplied DLS resource table");
                table
            }
            Err(error) => {
                tracing::error!(%path, %error, "DLS table unusable — falling back to the built-in one");
                ResourceTable::default()
            }
        },
        Err(error) => {
            tracing::error!(%path, %error, "could not read the DLS table");
            ResourceTable::default()
        }
    }
}

/// `overs,w0,w1,…,w9` per line, overs ascending from 0. Blank lines and lines
/// starting `#` are ignored.
fn parse_resource_csv(csv: &str) -> Result<ResourceTable, String> {
    let mut rows: Vec<[f64; 10]> = Vec::new();
    for (number, line) in csv.lines().enumerate() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let cells: Vec<&str> = line.split(',').map(str::trim).collect();
        if cells.len() != 11 {
            return Err(format!("line {}: expected 11 columns, got {}", number + 1, cells.len()));
        }
        let mut row = [0.0f64; 10];
        for (index, cell) in cells[1..].iter().enumerate() {
            row[index] = cell
                .parse()
                .map_err(|_| format!("line {}: `{cell}` is not a number", number + 1))?;
        }
        rows.push(row);
    }
    ResourceTable::from_rows(rows)
}
