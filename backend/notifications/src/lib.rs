//! APNs / push notification service (stub for Phase 3).

use serde_json::Value;
use tracing::info;
use uuid::Uuid;

#[derive(Debug, Clone, Default)]
pub struct PushService {
    pub bundle_id: String,
}

impl PushService {
    pub fn from_env() -> Self {
        Self {
            bundle_id: std::env::var("APNS_BUNDLE_ID")
                .unwrap_or_else(|_| "com.fishers.app".into()),
        }
    }

    pub async fn send(
        &self,
        user_id: Uuid,
        notification_type: &str,
        title: &str,
        body: &str,
        payload: Value,
    ) -> anyhow::Result<()> {
        info!(
            %user_id,
            notification_type,
            title,
            body,
            %payload,
            bundle = %self.bundle_id,
            "push notification stub (wire APNs in phase 3)"
        );
        Ok(())
    }
}
