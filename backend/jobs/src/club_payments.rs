//! The scheduler's side of paying the club by bank transfer.
//!
//! Every job here marks what it has done before the next tick can see it
//! again (`attendance_prompted_at`, `auto_bill_skipped_at`, a bill existing,
//! `last_reminded_at`, `check_reminded_at`), so a tick that runs twice sends
//! nothing twice. RSVP reminders once went out every five minutes for want of
//! exactly that.

use std::collections::BTreeMap;

use chrono::Utc;
use fishers_db::repos::club_payments as repo;
use fishers_db::repos::club_payments::{Attendee, BillError, BillInput, Payer};
use fishers_db::repos::notifications as notifications_repo;
use fishers_domain::money::{self, fmt_money, CostMode, PayoutState, Rounding};
use fishers_notifications::PushService;
use serde_json::{json, Value};
use sqlx::PgPool;
use tracing::{info, warn};
use uuid::Uuid;

/// Stored, then pushed — the same order the API uses. The title and body go
/// in the stored payload too, so an app that doesn't know this kind of
/// notification can still show it.
async fn notify(pool: &PgPool, push: &PushService, user: Uuid, kind: &str, title: &str, body: &str, mut payload: Value) {
    if let Value::Object(map) = &mut payload {
        map.entry("title").or_insert_with(|| json!(title));
        map.entry("body").or_insert_with(|| json!(body));
    }
    if let Err(error) = notifications_repo::record(pool, user, kind, &payload).await {
        warn!(%error, kind, "could not store a notification");
    }
    if let Err(error) = push.send(pool, user, kind, title, body, payload).await {
        warn!(%error, kind, "push failed");
    }
}

fn describe_cost(mode: &str, amount: i64, currency: &str) -> String {
    let money = fmt_money(amount, currency);
    match CostMode::parse(mode) {
        Some(CostMode::SplitTotal) => format!("{money} split between whoever came"),
        _ => format!("{money} each"),
    }
}

/// "Who came to Friday nets?" — to whoever scheduled it, once, when it ends.
pub async fn prompt_who_came(pool: &PgPool, push: &PushService) -> anyhow::Result<()> {
    let events = repo::events_to_prompt(pool).await?;
    for e in &events {
        // Marked first: a failed push must not turn into a prompt every tick.
        repo::mark_prompted(pool, e.event_id).await?;
        notify(
            pool,
            push,
            e.created_by,
            "bill_who_came",
            &format!("Who came to {}?", e.title),
            &format!(
                "Tick who came and send the bill: {}. Everyone gets their share and the club's bank details.",
                describe_cost(&e.mode, e.amount_cents, &e.currency)
            ),
            json!({ "event_id": e.event_id, "club_id": e.club_id }),
        )
        .await;
    }
    if !events.is_empty() {
        info!(count = events.len(), "asked who came");
    }
    Ok(())
}

/// Nobody sent the bill within the club's window: send it to whoever said
/// they were going (or, where attendance was recorded, whoever came), and
/// tell the person who scheduled it.
pub async fn auto_bill(pool: &PgPool, push: &PushService) -> anyhow::Result<()> {
    let events = repo::events_to_auto_bill(pool).await?;
    let mut sent = 0usize;
    for e in &events {
        let candidates = repo::candidates(pool, e.event_id).await?;
        let recorded = candidates.iter().any(|c| c.attended.is_some());
        let mut people: Vec<Attendee> = candidates
            .into_iter()
            .filter(|c| if recorded { c.attended == Some(true) } else { c.rsvp == "going" })
            .map(|c| Attendee { user_id: Some(c.user_id), name: c.name })
            .collect();
        people.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()).then(a.user_id.cmp(&b.user_id)));
        if people.is_empty() {
            repo::mark_auto_bill_skipped(pool, e.event_id).await?;
            notify(
                pool,
                push,
                e.created_by,
                "bill_not_sent",
                &format!("No bill sent for {}", e.title),
                "Nobody said they were going, so there was no one to bill. Tick who came on the event to send it.",
                json!({ "event_id": e.event_id, "club_id": e.club_id }),
            )
            .await;
            continue;
        }

        let accounts = repo::payout_accounts(pool, e.club_id).await?;
        let timelines: Vec<_> = accounts.iter().map(|a| a.timeline()).collect();
        let states = money::payout_states(&timelines, Utc::now());
        let payout = accounts.iter().zip(&states).rev().find(|(_, s)| **s == PayoutState::Active).map(|(a, _)| a.id);

        let mut tx = pool.begin().await?;
        let outcome = repo::issue_bill(
            &mut tx,
            &BillInput {
                event_id: e.event_id,
                club_id: e.club_id,
                title: &e.title,
                event_start_at: e.start_at,
                mode: CostMode::parse(&e.mode).unwrap_or(CostMode::PerPlayer),
                amount_cents: e.amount_cents,
                currency: &e.currency,
                rounding: if e.round_shares_up { Rounding::Up10p } else { Rounding::Exact },
                payout_account_id: payout,
                attendees: people,
                note: None,
                by: None,
                auto: true,
                expected_version: None,
            },
        )
        .await;
        let outcome = match outcome {
            Ok(o) => o,
            // Somebody sent it by hand in the meantime: theirs stands.
            Err(BillError::Mismatch { .. }) | Err(BillError::VersionConflict { .. }) => continue,
            Err(BillError::Split(reason)) => {
                drop(tx);
                repo::mark_auto_bill_skipped(pool, e.event_id).await?;
                notify(
                    pool,
                    push,
                    e.created_by,
                    "bill_not_sent",
                    &format!("No bill sent for {}", e.title),
                    &format!("{} Open the event to send it yourself.", reason.message()),
                    json!({ "event_id": e.event_id, "club_id": e.club_id }),
                )
                .await;
                continue;
            }
            Err(BillError::Db(error)) => return Err(error.into()),
        };
        repo::audit(
            &mut tx,
            e.club_id,
            None,
            "auto_send_bill",
            "bill",
            Some(outcome.bill.id),
            None,
            Some(json!({ "event_id": e.event_id, "people": outcome.changed.len(), "total_cents": outcome.bill.total_cents })),
        )
        .await?;
        tx.commit().await?;
        sent += 1;

        let club = repo::club_name(pool, e.club_id).await?.unwrap_or_default();
        for (user, amount) in &outcome.changed {
            notify(
                pool,
                push,
                *user,
                "bill_issued",
                &e.title,
                &format!("Your share is {}. Pay {club} by bank transfer in the app.", fmt_money(*amount, &e.currency)),
                json!({ "event_id": e.event_id, "club_id": e.club_id }),
            )
            .await;
        }
        notify(
            pool,
            push,
            e.created_by,
            "bill_auto_sent",
            &format!("Bill sent for {}", e.title),
            &format!(
                "Nobody had sent it, so it went to the {} who said they were going. Change who came on the event if that's not right.",
                outcome.changed.len()
            ),
            json!({ "event_id": e.event_id, "club_id": e.club_id }),
        )
        .await;
    }
    if sent > 0 {
        info!(sent, "sent bills nobody had sent");
    }
    Ok(())
}

/// One nudge per member per club for everything still unpaid, on the club's
/// chase settings. A share covered by a claim waiting to be confirmed is not
/// chased: the member has done their part.
pub async fn chase_shares(pool: &PgPool, push: &PushService) -> anyhow::Result<()> {
    let due = repo::shares_due_a_reminder(pool).await?;
    let mut by_member: BTreeMap<(Uuid, Uuid), Vec<Uuid>> = BTreeMap::new();
    for s in &due {
        if let Some(user) = s.user_id {
            by_member.entry((s.club_id, user)).or_default().push(s.id);
        }
    }
    let mut chased = 0usize;
    for ((club_id, user), candidates) in by_member {
        let (shares, payments) = repo::ledger(pool, club_id, Some(user)).await?;
        let ledger_shares: Vec<_> = shares.iter().map(|s| s.ledger()).collect();
        let ledger_payments: Vec<_> = payments.iter().filter(|p| p.payer() == Payer::Member(user)).map(|p| p.ledger()).collect();
        let settled = money::settle(&ledger_shares, &ledger_payments);
        let still_owed: Vec<Uuid> = candidates
            .into_iter()
            .filter(|id| {
                let amount = shares.iter().find(|s| s.id == *id).map_or(0, |s| s.amount_cents);
                settled.shares.get(id).is_some_and(|p| amount - p.paid_cents - p.waiting_cents > 0)
            })
            .collect();
        if still_owed.is_empty() || settled.owed_cents <= 0 {
            continue;
        }
        let currency = shares.last().map(|s| s.currency.clone()).unwrap_or_else(|| "GBP".into());
        let club = repo::club_name(pool, club_id).await?.unwrap_or_default();
        let money = fmt_money(settled.owed_cents, &currency);
        repo::mark_shares_reminded(pool, &still_owed).await?;
        notify(
            pool,
            push,
            user,
            "fee_reminder",
            &format!("You owe {club} {money}"),
            &format!("You still owe {club} {money}. Pay by bank transfer in the app, then tap I've paid."),
            json!({ "club_id": club_id }),
        )
        .await;
        chased += 1;
    }
    if chased > 0 {
        info!(chased, "reminded members what they owe");
    }
    Ok(())
}

/// Claims nobody has checked for two days: one nudge to whoever checks them.
pub async fn nudge_stale_claims(pool: &PgPool, push: &PushService) -> anyhow::Result<()> {
    for (club_id, ids) in repo::stale_claims(pool).await? {
        repo::mark_claims_nudged(pool, &ids).await?;
        let club = repo::club_name(pool, club_id).await?.unwrap_or_default();
        let admins = repo::money_admins(pool, club_id).await?;
        let (title, body) = if ids.len() == 1 {
            (
                format!("{club}: a payment to check"),
                "Somebody said they paid two days ago. Check your bank, then confirm it in the app.".to_string(),
            )
        } else {
            (
                format!("{club}: {} payments to check", ids.len()),
                format!("{} people said they paid over two days ago. Check your bank, then confirm them in the app.", ids.len()),
            )
        };
        for checker in repo::payment_checkers(&admins) {
            notify(pool, push, checker, "payments_to_check", &title, &body, json!({ "club_id": club_id })).await;
        }
    }
    Ok(())
}

/// Once a replacement goes live, the old details are retired: their sealed
/// number is wiped and only the name and last four digits stay.
pub async fn retire_replaced_accounts(pool: &PgPool) -> anyhow::Result<()> {
    for club_id in repo::clubs_with_replaced_accounts(pool).await? {
        let accounts = repo::payout_accounts(pool, club_id).await?;
        let timelines: Vec<_> = accounts.iter().map(|a| a.timeline()).collect();
        let states = money::payout_states(&timelines, Utc::now());
        for (account, state) in accounts.iter().zip(states) {
            if state != PayoutState::Superseded {
                continue;
            }
            let mut tx = pool.begin().await?;
            if repo::retire_payout_account(&mut tx, account.id, None).await? {
                repo::audit(&mut tx, club_id, None, "retire_replaced_bank_details", "payout_account", Some(account.id),
                    Some(json!({ "holder_name": account.holder_name, "last4": account.last4 })), None).await?;
            }
            tx.commit().await?;
        }
    }
    Ok(())
}
