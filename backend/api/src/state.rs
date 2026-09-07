use fishers_agent::AgentService;
use fishers_domain::ResourceTable;
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
    /// Duckworth–Lewis resources. Swap in a league's own table by pointing
    /// `DLS_RESOURCE_TABLE` at a CSV of `overs,w0,w1,…,w9` rows.
    pub dls: ResourceTable,
    pub g50: f64,
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
        Self {
            pool,
            jwt_secret,
            access_ttl_secs,
            refresh_ttl_secs,
            stripe: StripeClient::from_env(),
            push,
            agent: AgentService::from_env(),
            email: EmailService::from_env(),
            dls: load_dls_table(),
            g50: std::env::var("DLS_G50")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(fishers_domain::dls::DEFAULT_G50),
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
