use axum::extract::State;
use axum::routing::post;
use axum::{Json, Router};
use fishers_db::repos::payments as payments_repo;
use fishers_domain::{CreatePaymentIntentRequest, PaymentIntentResponse, PaymentStatus};
use serde::Deserialize;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/payments/intent", post(create_intent))
        .route("/payments/webhook", post(webhook))
}

async fn create_intent(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(body): Json<CreatePaymentIntentRequest>,
) -> ApiResult<Json<PaymentIntentResponse>> {
    if body.amount_cents <= 0 {
        return Err(ApiError::bad_request("amount_cents must be positive"));
    }
    let payment =
        payments_repo::create_pending(&state.pool, auth.user_id, &body, None).await?;
    let intent = state
        .stripe
        .create_payment_intent(payment.id, &body)
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    // Persist stub PI id
    let _ = payments_repo::mark_status(&state.pool, payment.id, PaymentStatus::Pending).await?;
    let _ = sqlx::query(
        "UPDATE payments SET stripe_payment_intent_id = $2 WHERE id = $1",
    )
    .bind(payment.id)
    .bind(&intent.client_secret)
    .execute(&state.pool)
    .await?;

    Ok(Json(intent))
}

#[derive(Deserialize)]
struct WebhookBody {
    payment_id: Option<uuid::Uuid>,
    status: Option<String>,
}

async fn webhook(
    State(state): State<AppState>,
    Json(body): Json<WebhookBody>,
) -> ApiResult<Json<serde_json::Value>> {
    // Dev stub — real Stripe signature verification goes here.
    if let (Some(id), Some(status)) = (body.payment_id, body.status.as_deref()) {
        let st = match status {
            "succeeded" => PaymentStatus::Succeeded,
            "failed" => PaymentStatus::Failed,
            "refunded" => PaymentStatus::Refunded,
            _ => PaymentStatus::Pending,
        };
        payments_repo::mark_status(&state.pool, id, st).await?;
    }
    Ok(Json(serde_json::json!({ "received": true })))
}
