use fishers_notifications::PushService;
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
        }
    }
}
