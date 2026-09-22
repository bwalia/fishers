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

/// Claim a webhook delivery. `false` means we have already acted on this one.
///
/// Stripe retries until it gets a 2xx and re-sends on its own schedule
/// besides, so "settle this ticket" arrives more than once as a matter of
/// course. The primary key decides the race in the database; two API replicas
/// processing the same delivery cannot both win.
pub async fn claim_webhook_event(
    pool: &PgPool,
    event_id: &str,
    kind: Option<&str>,
) -> Result<bool, sqlx::Error> {
    let claimed = sqlx::query(
        "INSERT INTO payment_webhook_events (event_id, kind) VALUES ($1, $2)
         ON CONFLICT (event_id) DO NOTHING",
    )
    .bind(event_id)
    .bind(kind)
    .execute(pool)
    .await?;
    Ok(claimed.rows_affected() == 1)
}

/// Note which payment a delivery turned out to be about, for the audit trail.
pub async fn link_webhook_event(
    pool: &PgPool,
    event_id: &str,
    payment_id: Uuid,
) -> Result<(), sqlx::Error> {
    sqlx::query("UPDATE payment_webhook_events SET payment_id = $2 WHERE event_id = $1")
        .bind(event_id)
        .bind(payment_id)
        .execute(pool)
        .await?;
    Ok(())
}

/// A payment already opened for this fixture and still waiting to settle.
///
/// Tapping Pay twice used to open a second payment, and a second Stripe
/// intent, for the same ticket. Reusing the pending row means the second tap
/// reaches Stripe with the same idempotency key and gets the same intent back.
pub async fn pending_for_event(
    pool: &PgPool,
    user_id: Uuid,
    event_id: Uuid,
) -> Result<Option<Payment>, sqlx::Error> {
    sqlx::query_as::<_, Payment>(
        r#"
        SELECT id, user_id, event_id, order_id, amount_cents, currency, status,
               stripe_payment_intent_id, created_at, updated_at
        FROM payments
        WHERE user_id = $1 AND event_id = $2
          AND status IN ('pending', 'requires_action')
        ORDER BY created_at DESC
        LIMIT 1
        "#,
    )
    .bind(user_id)
    .bind(event_id)
    .fetch_optional(pool)
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

/// A paid entry-fee payment settles the entry in the same breath. Idempotent:
/// a replayed webhook changes nothing, because `COALESCE` keeps the first
/// timestamp.
pub async fn settle_entry_for_payment(
    pool: &PgPool,
    payment_id: Uuid,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE tournament_entrants en
        SET entry_paid_at = COALESCE(en.entry_paid_at, NOW()),
            entry_payment_method = COALESCE(en.entry_payment_method, 'card')
        FROM payments p
        WHERE p.id = $1
          AND p.status = 'succeeded'
          AND en.id = p.entrant_id
        "#,
    )
    .bind(payment_id)
    .execute(pool)
    .await?;
    Ok(())
}

/// A payment already opened for this entry and still waiting to settle.
pub async fn pending_for_entrant(
    pool: &PgPool,
    entrant_id: Uuid,
) -> Result<Option<Payment>, sqlx::Error> {
    sqlx::query_as::<_, Payment>(
        r#"
        SELECT id, user_id, event_id, order_id, amount_cents, currency, status,
               stripe_payment_intent_id, created_at, updated_at
        FROM payments
        WHERE entrant_id = $1 AND status IN ('pending', 'requires_action')
        ORDER BY created_at DESC
        LIMIT 1
        "#,
    )
    .bind(entrant_id)
    .fetch_optional(pool)
    .await
}

/// Open a payment for a tournament entry.
///
/// `payments` grew an `entrant_id` rather than gaining a second kind of
/// payment: the intent, the webhook and the idempotency are all the same, and
/// only what it settles differs.
pub async fn create_pending_entry(
    pool: &PgPool,
    user_id: Uuid,
    entrant_id: Uuid,
    amount_cents: i32,
    currency: &str,
) -> Result<Payment, sqlx::Error> {
    sqlx::query_as::<_, Payment>(
        r#"
        INSERT INTO payments (user_id, entrant_id, amount_cents, currency, status)
        VALUES ($1, $2, $3, $4, 'pending')
        RETURNING id, user_id, event_id, order_id, amount_cents, currency, status,
                  stripe_payment_intent_id, created_at, updated_at
        "#,
    )
    .bind(user_id)
    .bind(entrant_id)
    .bind(amount_cents)
    .bind(currency)
    .fetch_one(pool)
    .await
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
