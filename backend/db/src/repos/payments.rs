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

/// Record the provider's intent id against our payment, so a webhook that only
/// names the intent can still find the row.
pub async fn attach_intent(
    pool: &PgPool,
    payment_id: Uuid,
    intent_id: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "UPDATE payments SET stripe_payment_intent_id = $2, updated_at = NOW() WHERE id = $1",
    )
    .bind(payment_id)
    .bind(intent_id)
    .execute(pool)
    .await?;
    Ok(())
}

/// Settle by provider intent id. Returns `None` when we have never heard of it.
pub async fn mark_status_by_intent(
    pool: &PgPool,
    intent_id: &str,
    status: PaymentStatus,
) -> Result<Option<Payment>, sqlx::Error> {
    sqlx::query_as::<_, Payment>(
        r#"
        UPDATE payments SET status = $2, updated_at = NOW()
        WHERE stripe_payment_intent_id = $1
        RETURNING id, user_id, event_id, order_id, amount_cents, currency, status,
                  stripe_payment_intent_id, created_at, updated_at
        "#,
    )
    .bind(intent_id)
    .bind(status)
    .fetch_optional(pool)
    .await
}

/// A paid event payment settles that member's ticket for the same event, if
/// they hold one. Idempotent: a replayed webhook changes nothing.
pub async fn settle_ticket_for_payment(
    pool: &PgPool,
    payment_id: Uuid,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE event_tickets t
        SET status = 'paid',
            paid_at = COALESCE(t.paid_at, NOW()),
            payment_method = COALESCE(t.payment_method, 'stripe'),
            updated_at = NOW()
        FROM payments p
        WHERE p.id = $1
          AND p.status = 'succeeded'
          AND t.event_id = p.event_id
          AND t.user_id = p.user_id
          AND t.status <> 'cancelled'
        "#,
    )
    .bind(payment_id)
    .execute(pool)
    .await?;
    Ok(())
}

/// Whether this member has already paid for this fixture — the check that keeps
/// a second tap from taking a second payment.
pub async fn has_paid_for_event(
    pool: &PgPool,
    user_id: Uuid,
    event_id: Uuid,
) -> Result<bool, sqlx::Error> {
    let row: (bool,) = sqlx::query_as(
        r#"
        SELECT EXISTS(
          SELECT 1 FROM payments
          WHERE user_id = $1 AND event_id = $2 AND status = 'succeeded'
        )
        "#,
    )
    .bind(user_id)
    .bind(event_id)
    .fetch_one(pool)
    .await?;
    Ok(row.0)
}
