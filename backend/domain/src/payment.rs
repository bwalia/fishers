use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::PaymentStatus;

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Payment {
    pub id: Uuid,
    pub user_id: Uuid,
    pub event_id: Option<Uuid>,
    pub order_id: Option<Uuid>,
    pub amount_cents: i32,
    pub currency: String,
    pub status: PaymentStatus,
    pub stripe_payment_intent_id: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CreatePaymentIntentRequest {
    pub event_id: Option<Uuid>,
    pub order_id: Option<Uuid>,
    pub amount_cents: i32,
    pub currency: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct PaymentIntentResponse {
    pub payment_id: Uuid,
    pub client_secret: String,
    pub amount_cents: i32,
    pub currency: String,
    pub status: PaymentStatus,
}
