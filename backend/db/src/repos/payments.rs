use fishers_domain::{CreatePaymentIntentRequest, Payment, PaymentStatus};
use sqlx::PgPool;
use uuid::Uuid;

pub async fn create_pending(
    pool: &PgPool,
    user_id: Uuid,
    req: &CreatePaymentIntentRequest,
    stripe_pi: Option<&str>,
) -> Result<Payment, sqlx::Error> {
    let currency = req
        .currency
        .clone()
        .unwrap_or_else(|| "GBP".to_string());

    sqlx::query_as::<_, Payment>(
        r#"
        INSERT INTO payments (user_id, event_id, order_id, amount_cents, currency, status, stripe_payment_intent_id)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING id, user_id, event_id, order_id, amount_cents, currency, status,
                  stripe_payment_intent_id, created_at, updated_at
        "#,
    )
    .bind(user_id)
    .bind(req.event_id)
    .bind(req.order_id)
    .bind(req.amount_cents)
    .bind(currency)
    .bind(PaymentStatus::Pending)
    .bind(stripe_pi)
    .fetch_one(pool)
    .await
}

pub async fn mark_status(
    pool: &PgPool,
    payment_id: Uuid,
    status: PaymentStatus,
) -> Result<Payment, sqlx::Error> {
    sqlx::query_as::<_, Payment>(
        r#"
        UPDATE payments SET status = $2, updated_at = NOW() WHERE id = $1
        RETURNING id, user_id, event_id, order_id, amount_cents, currency, status,
                  stripe_payment_intent_id, created_at, updated_at
        "#,
    )
    .bind(payment_id)
    .bind(status)
    .fetch_one(pool)
    .await
}

pub async fn list_for_event(pool: &PgPool, event_id: Uuid) -> Result<Vec<Payment>, sqlx::Error> {
    sqlx::query_as::<_, Payment>(
        r#"
        SELECT id, user_id, event_id, order_id, amount_cents, currency, status,
               stripe_payment_intent_id, created_at, updated_at
        FROM payments WHERE event_id = $1 ORDER BY created_at DESC
        "#,
    )
    .bind(event_id)
    .fetch_all(pool)
    .await
}
