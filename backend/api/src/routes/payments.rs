//! Match fees and ticket payments.
//!
//! The webhook is the only unauthenticated route in the API, so it is the only
//! one that must prove who is calling: a signed `Stripe-Signature` header over
//! the exact bytes received. Without it, anyone could mark their own fee paid.

use axum::body::Bytes;
use axum::extract::State;
use axum::http::HeaderMap;
use axum::routing::post;
use axum::{Json, Router};
use fishers_db::repos::payments as payments_repo;
use fishers_domain::{CreatePaymentIntentRequest, PaymentIntentResponse, PaymentStatus};
use fishers_payments::WebhookVerification;
use serde::Deserialize;
use tracing::{error, info, warn};
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

/// A club fee is not a house deposit; anything larger is a fat finger.
const MAX_PAYMENT_CENTS: i32 = 100_000;

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
    if body.amount_cents > MAX_PAYMENT_CENTS {
        return Err(ApiError::bad_request("that amount looks like a mistake"));
    }
    if body.event_id.is_none() && body.order_id.is_none() {
        return Err(ApiError::bad_request(
            "a payment must be for a fixture or an order",
        ));
    }

    // Row first, so the intent we create at Stripe can carry our id in its
    // metadata and the webhook always knows what it is settling.
    let payment = payments_repo::create_pending(&state.pool, auth.user_id, &body, None).await?;
    let intent = state
        .stripe
        .create_payment_intent(payment.id, &body)
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;
    payments_repo::attach_intent(&state.pool, payment.id, &intent.client_secret).await?;
    Ok(Json(intent))
}

/// What we read out of a Stripe event. The rest of the payload is ignored.
#[derive(Deserialize)]
struct StripeEvent {
    #[serde(default)]
    id: Option<String>,
    #[serde(rename = "type", default)]
    kind: Option<String>,
    #[serde(default)]
    data: Option<StripeEventData>,
    // The dev-mode shape: `{ "payment_id": …, "status": "succeeded" }`.
    #[serde(default)]
    payment_id: Option<Uuid>,
    #[serde(default)]
    status: Option<String>,
}

#[derive(Deserialize)]
struct StripeEventData {
    #[serde(default)]
    object: Option<StripeObject>,
}

#[derive(Deserialize)]
struct StripeObject {
    #[serde(default)]
    id: Option<String>,
    #[serde(default)]
    metadata: Option<PaymentMetadata>,
}

#[derive(Deserialize)]
struct PaymentMetadata {
    #[serde(default)]
    fishers_payment_id: Option<Uuid>,
}

async fn webhook(
    State(state): State<AppState>,
    headers: HeaderMap,
    body: Bytes,
) -> ApiResult<Json<serde_json::Value>> {
    let signature = headers
        .get("stripe-signature")
        .and_then(|v| v.to_str().ok())
        .unwrap_or_default();

    match state.stripe.verify_webhook_signature(
        &body,
        signature,
        chrono::Utc::now().timestamp(),
    ) {
        WebhookVerification::Ok => {}
        WebhookVerification::Unconfigured => {
            // Refusing here is the whole point: an unconfigured webhook secret
            // used to mean "accept anything from anyone".
            warn!("payment webhook refused — STRIPE_WEBHOOK_SECRET is not set");
            return Err(ApiError::unauthorized(
                "webhooks are not configured on this server",
            ));
        }
        WebhookVerification::BadSignature(reason) => {
            warn!(reason, "payment webhook refused");
            return Err(ApiError::unauthorized("invalid webhook signature"));
        }
    }

    let event: StripeEvent = serde_json::from_slice(&body)
        .map_err(|e| ApiError::bad_request(format!("unreadable webhook body: {e}")))?;

    // Either shape can name the payment: our own metadata, or the intent id.
    let payment_id = event.payment_id.or_else(|| {
        event
            .data
            .as_ref()
            .and_then(|d| d.object.as_ref())
            .and_then(|o| o.metadata.as_ref())
            .and_then(|m| m.fishers_payment_id)
    });
    let intent_id = event
        .data
        .as_ref()
        .and_then(|d| d.object.as_ref())
        .and_then(|o| o.id.clone());

    let status = match event.kind.as_deref().or(event.status.as_deref()) {
        Some("payment_intent.succeeded") | Some("succeeded") => PaymentStatus::Succeeded,
        Some("payment_intent.payment_failed") | Some("failed") => PaymentStatus::Failed,
        Some("charge.refunded") | Some("refunded") => PaymentStatus::Refunded,
        Some("payment_intent.canceled") | Some("cancelled") => PaymentStatus::Cancelled,
        other => {
            info!(?other, "ignoring webhook event we do not act on");
            return Ok(Json(serde_json::json!({ "received": true, "acted": false })));
        }
    };

    let updated = match (payment_id, intent_id.as_deref()) {
        (Some(id), _) => payments_repo::mark_status(&state.pool, id, status).await.ok(),
        (None, Some(intent)) => payments_repo::mark_status_by_intent(&state.pool, intent, status)
            .await
            .ok()
            .flatten(),
        (None, None) => None,
    };

    let Some(payment) = updated else {
        error!(event_id = ?event.id, "webhook names no payment we know about");
        return Ok(Json(serde_json::json!({ "received": true, "acted": false })));
    };

    // A succeeded ticket payment settles the ticket in the same breath.
    if status == PaymentStatus::Succeeded {
        if let Err(error) = payments_repo::settle_ticket_for_payment(&state.pool, payment.id).await
        {
            error!(%error, "could not settle the ticket for a paid payment");
        }
    }

    Ok(Json(
        serde_json::json!({ "received": true, "acted": true, "payment_id": payment.id }),
    ))
}
