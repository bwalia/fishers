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
use fishers_db::repos::passes;
use fishers_domain::money::{self, fmt_money, CostMode, PassBilling, PassStanding, PayoutState, Rounding};
use fishers_notifications::PushService;
use serde_json::{json, Value};
use sqlx::PgPool;
use tracing::{info, warn};
use uuid::Uuid;

/// Stored, then pushed — the same order the API uses. The title, body and
/// kind go in the payload too, so an app that doesn't know this kind of
/// notification can still show it, and a push can be routed by its kind.
async fn notify(pool: &PgPool, push: &PushService, user: Uuid, kind: &str, title: &str, body: &str, mut payload: Value) {
    if let Value::Object(map) = &mut payload {
        map.entry("title").or_insert_with(|| json!(title));
        map.entry("body").or_insert_with(|| json!(body));
        map.entry("kind").or_insert_with(|| json!(kind));
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
            .map(|c| Attendee { user_id: Some(c.user_id), name: c.name, ..Default::default() })
            .collect();
        people.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()).then(a.user_id.cmp(&b.user_id)));
        // Passes, free price types and per-type prices, exactly as a bill sent by hand.
        let facts = fishers_db::repos::passes::SessionFacts {
            club_id: e.club_id,
            event_id: Some(e.event_id),
            subtype: e.subtype.clone(),
            team_id: e.team_id,
            day: e.start_at.date_naive(),
        };
        let mode = CostMode::parse(&e.mode).unwrap_or(CostMode::PerPlayer);
        let people = fishers_db::repos::passes::priced(pool, &facts, mode, people).await?;
        let bundles: Vec<Uuid> = people
            .iter()
            .filter_map(|p| match &p.cover {
                Some(repo::Cover::Pass { holder_id, .. }) => Some(*holder_id),
                _ => None,
            })
            .collect();
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
        bundle_notices(pool, push, &bundles).await;

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
        // A junior's parent pays: they hear about it too.
        if let Some(payer) = passes::payer_of(pool, club_id, user).await? {
            let name = repo::user_name(pool, user).await?.unwrap_or_default();
            notify(
                pool,
                push,
                payer,
                "fee_reminder",
                &format!("{} owes {club} {money}", repo::first_name_of(&name)),
                &format!("{name} still owes {club} {money}. Pay it in the app, then tap I've paid."),
                json!({ "club_id": club_id, "for": user }),
            )
            .await;
        }
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
pub async fn retire_replaced_accounts(pool: &PgPool, push: &PushService) -> anyhow::Result<()> {
    for club_id in repo::clubs_with_replaced_accounts(pool).await? {
        let accounts = repo::payout_accounts(pool, club_id).await?;
        let timelines: Vec<_> = accounts.iter().map(|a| a.timeline()).collect();
        let states = money::payout_states(&timelines, Utc::now());
        for (account, state) in accounts.iter().zip(states) {
            if state != PayoutState::Superseded {
                continue;
            }
            let mut tx = pool.begin().await?;
            let retired = repo::retire_payout_account(&mut tx, account.id, None).await?;
            if retired {
                repo::audit(&mut tx, club_id, None, "retire_replaced_bank_details", "payout_account", Some(account.id),
                    Some(json!({ "holder_name": account.holder_name, "last4": account.last4 })), None).await?;
            }
            tx.commit().await?;
            // A standing order keeps paying the old account until its owner
            // changes it, and nothing else would tell them: say so, once, as
            // the new details take over. No account numbers in a notification.
            if retired {
                let club = repo::club_name(pool, club_id).await?.unwrap_or_default();
                for h in passes::standing_orders(pool, club_id).await? {
                    notify_pass(pool, push, &h, "pass_bank_changed", &format!("{club}'s bank details changed"),
                        "Change your standing order to the new details: open the club's pay screen in the app to see them.").await;
                }
            }
        }
    }
    Ok(())
}

/// Each month's charge for a monthly pass, and each instalment when it falls.
/// Never charges for days before somebody was put on a pass (a back-dated
/// start pays from its first charge, not for the months in between), and
/// charging a month twice does nothing.
pub async fn charge_passes(pool: &PgPool, push: &PushService) -> anyhow::Result<()> {
    let today = Utc::now().date_naive();
    let mut charged = 0usize;
    for h in passes::running_holders(pool).await? {
        let Some(plan) = passes::plan(pool, h.plan_id).await? else { continue };
        let added = h.created_at.date_naive();
        let due: Vec<(chrono::NaiveDate, usize)> = match plan.billing() {
            PassBilling::Once => Vec::new(),
            PassBilling::Monthly => money::monthly_periods(h.started_on, today, h.ends_on)
                .into_iter()
                .enumerate()
                .map(|(i, d)| (d, i + 1))
                .collect(),
            // Instalments keep falling after a cancel: the pass was bought.
            PassBilling::Instalments => money::instalment_days(h.started_on, plan.instalments.unwrap_or(1).max(1) as u32)
                .into_iter()
                .enumerate()
                .filter(|(_, d)| *d <= today)
                .map(|(i, d)| (d, i + 1))
                .collect(),
        };
        for (period, part) in due {
            if period < added && period != h.started_on {
                continue;
            }
            let payout = repo::payout_accounts(pool, h.club_id).await.ok().and_then(|accounts| {
                let timelines: Vec<_> = accounts.iter().map(|a| a.timeline()).collect();
                let states = money::payout_states(&timelines, Utc::now());
                accounts.iter().zip(states).rev().find(|(_, s)| *s == PayoutState::Active).map(|(a, _)| a.id)
            });
            let title = passes::charge_title(&plan, period, part);
            let mut tx = pool.begin().await?;
            let bill = passes::charge_pass(&mut tx, &plan, &h, period, &title, plan.charge_cents(), payout).await?;
            tx.commit().await?;
            if bill.is_none() {
                continue;
            }
            charged += 1;
            let club = repo::club_name(pool, h.club_id).await?.unwrap_or_default();
            let money = fmt_money(plan.charge_cents(), &plan.currency);
            let body = match plan.billing() {
                PassBilling::Monthly => format!(
                    "{money} for {}. If your standing order to {club} is set up, there's nothing to do.",
                    period.format("%B")
                ),
                _ => format!("{money} is due to {club}. Pay by bank transfer in the app, then tap I've paid."),
            };
            notify_pass(pool, push, &h, "pass_charge", &title, &body).await;
        }
    }
    if charged > 0 {
        info!(charged, "charged passes");
    }
    Ok(())
}

/// A holder hears about their pass, and so does whoever pays for them.
async fn notify_pass(pool: &PgPool, push: &PushService, h: &passes::Holder, kind: &str, title: &str, body: &str) {
    let payload = json!({ "club_id": h.club_id, "pass_holder_id": h.id });
    notify(pool, push, h.user_id, kind, title, body, payload.clone()).await;
    if let Ok(Some(payer)) = passes::payer_of(pool, h.club_id, h.user_id).await {
        notify(pool, push, payer, kind, title, &format!("For {}: {body}", h.name), payload).await;
    }
}

/// Once when a pass falls behind, once more if it's suspended (the club is
/// told then too), and back to quiet once it's paid up.
pub async fn pass_standing_notices(pool: &PgPool, push: &PushService) -> anyhow::Result<()> {
    let today = Utc::now().date_naive();
    for h in passes::running_holders(pool).await? {
        let Some(plan) = passes::plan(pool, h.plan_id).await? else { continue };
        let now = match passes::standing(pool, &plan, &h, today).await? {
            PassStanding::UpToDate => "up_to_date",
            PassStanding::Behind => "behind",
            PassStanding::Suspended => "suspended",
        };
        if now == h.told_standing || !passes::set_told_standing(pool, h.id, &h.told_standing, now).await? {
            continue;
        }
        let club = repo::club_name(pool, h.club_id).await?.unwrap_or_default();
        match now {
            "behind" if h.told_standing == "up_to_date" => {
                notify_pass(pool, push, &h, "pass_behind", &format!("{}: a payment is late", plan.name),
                    &format!("A payment for {} hasn't reached {club} yet. Pay it in the app to keep your sessions covered.", plan.name)).await;
            }
            "suspended" => {
                notify_pass(pool, push, &h, "pass_suspended", &format!("{} is paused", plan.name),
                    &format!("Payments to {club} are late, so sessions are charged as usual until it's paid up.")).await;
                for (admin, _) in repo::money_admins(pool, h.club_id).await? {
                    notify(pool, push, admin, "pass_suspended_club", &format!("{}: {} is behind", plan.name, h.name),
                        &format!("{}'s pass is paused for late payments. You can keep it covering them from the pass.", h.name),
                        json!({ "club_id": h.club_id, "pass_holder_id": h.id })).await;
                }
            }
            _ => {}
        }
    }
    Ok(())
}

/// A bundle down to its last session, or used up, says so — once, on the
/// bill that did it. (The API does the same for a bill sent by hand.)
async fn bundle_notices(pool: &PgPool, push: &PushService, holder_ids: &[Uuid]) {
    for id in holder_ids {
        let Ok(Some(h)) = passes::holder(pool, *id).await else { continue };
        let Ok(Some(plan)) = passes::plan(pool, h.plan_id).await else { continue };
        let Some(limit) = plan.sessions else { continue };
        let Ok(used) = passes::sessions_used(pool, h.id, None).await else { continue };
        let Some((title, body)) = passes::sessions_left_notice(&plan.name, i64::from(limit) - used) else { continue };
        notify_pass(pool, push, &h, "pass_sessions_left", &title, body).await;
    }
}
