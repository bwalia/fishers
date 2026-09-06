//! Optional Play-Cricket sync.
//!
//! Play-Cricket does not offer a public statistics API. Clubs can obtain an
//! API token for match/result feeds. When `PLAY_CRICKET_API_TOKEN` is set we
//! mark the club as synced; season aggregates continue to come from Fishers'
//! sample/imported `player_season_stats` rows until a full importer is wired.

use fishers_db::repos::stats as stats_repo;
use fishers_domain::PlayCricketClubSite;
use serde::Serialize;
use sqlx::PgPool;
use uuid::Uuid;

#[derive(Debug, Serialize)]
pub struct SyncResult {
    pub club_id: Uuid,
    pub site_id: String,
    pub status: &'static str,
    pub message: String,
    pub token_configured: bool,
}

pub async fn sync_club(pool: &PgPool, club_id: Uuid) -> Result<SyncResult, String> {
    let site = stats_repo::club_site(pool, club_id)
        .await
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "club has no Play-Cricket site link".to_string())?;

    let token = resolve_token(&site);
    let token_configured = token.is_some();

    if token_configured {
        // Placeholder: with a real token, call match/result endpoints and upsert
        // season aggregates. For now we refresh the sync timestamp so UIs show
        // a successful "checked Play-Cricket" state against sample data.
        stats_repo::touch_club_sync(pool, club_id)
            .await
            .map_err(|e| e.to_string())?;
        Ok(SyncResult {
            club_id,
            site_id: site.site_id,
            status: "ok",
            message: "Play-Cricket token present; sample season stats retained. Full result import not yet enabled.".into(),
            token_configured,
        })
    } else {
        let site_id = site.site_id.clone();
        let public = site
            .public_url
            .clone()
            .unwrap_or_else(|| "https://play-cricket.com/".to_string());
        stats_repo::touch_club_sync(pool, club_id)
            .await
            .map_err(|e| e.to_string())?;
        Ok(SyncResult {
            club_id,
            site_id,
            status: "sample",
            message: format!(
                "Serving seeded Play-Cricket sample stats. Open {public} for the public club page, or set PLAY_CRICKET_API_TOKEN for live match feeds."
            ),
            token_configured,
        })
    }
}

fn resolve_token(site: &PlayCricketClubSite) -> Option<String> {
    let env_name = site
        .api_token_env
        .as_deref()
        .unwrap_or("PLAY_CRICKET_API_TOKEN");
    std::env::var(env_name).ok().filter(|s| !s.is_empty())
}
