use chrono::{DateTime, Duration, Utc};
use fishers_domain::tournament::{self, GeneratedFixture, Slot};
use fishers_domain::{
    AddEntrantsRequest, BookTicketRequest, Entrant, EntryInvitation, EntryStatus, EventTicket,
    FixtureBlock, GenerateSlotsRequest, InviteEntrantRequest, PointsRules, RecordResultRequest,
    ScheduleRow, Standing, TicketSummary, TournamentEntrant, TournamentFormat, UpdateBlockRequest,
};
use sqlx::PgPool;
use uuid::Uuid;

/// Every column of a block, in one place: `events` reads them too, and a
/// settings column returned by one query and missing from the other is a field
/// that silently reads as null on half the screens.
pub const BLOCK_COLS: &str = "id, club_id, team_id, name, kind, starts_on, ends_on, created_at, \
                              description, venue_id, max_entrants, entry_deadline, \
                              entry_fee_cents, players_per_side, guest_players_allowed, \
                              age_group, gender, conditions, rules_notes";

/// One list, so a column added to an entrant cannot be returned by one query
/// and silently missing from another.
const ENTRANT_COLS: &str = "id, block_id, name, club_id, team_id, seed, group_label, \
                            contact_name, contact_email, status, invited_by, responded_at, \
                            entry_paid_at, entry_payment_method, withdrawn";

pub async fn get_block(pool: &PgPool, id: Uuid) -> Result<Option<FixtureBlock>, sqlx::Error> {
    sqlx::query_as::<_, FixtureBlock>(&format!(
        "SELECT {BLOCK_COLS} FROM fixture_blocks WHERE id = $1"
    ))
    .bind(id)
    .fetch_optional(pool)
    .await
}

/// Format, points rules and tour logistics for one block.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct BlockSettings {
    pub club_id: Uuid,
    pub name: String,
    pub format: String,
    pub group_count: Option<i32>,
    pub points_win: i32,
    pub points_draw: i32,
    pub points_no_result: i32,
    pub sport: Option<String>,
}

pub async fn block_settings(pool: &PgPool, id: Uuid) -> Result<BlockSettings, sqlx::Error> {
    sqlx::query_as::<_, BlockSettings>(
        r#"
        SELECT b.club_id, b.name, b.format, b.group_count, b.points_win, b.points_draw,
               b.points_no_result,
               (SELECT e.sport::TEXT FROM events e WHERE e.fixture_block_id = b.id LIMIT 1) AS sport
        FROM fixture_blocks b WHERE b.id = $1
        "#,
    )
    .bind(id)
    .fetch_one(pool)
    .await
}

/// The playing conditions a fixture inherits, when it belongs to a tournament
/// that set any.
///
/// One join rather than two queries, and deliberately not a field on `Event`:
/// every screen that reads a fixture would then have to carry a column it has
/// no use for.
pub async fn conditions_for_event(
    pool: &PgPool,
    event_id: Uuid,
) -> Result<Option<fishers_domain::MatchConditions>, sqlx::Error> {
    let row: Option<(Option<serde_json::Value>,)> = sqlx::query_as(
        "SELECT fb.conditions
         FROM events e
         JOIN fixture_blocks fb ON fb.id = e.fixture_block_id
         WHERE e.id = $1",
    )
    .bind(event_id)
    .fetch_optional(pool)
    .await?;

    Ok(row
        .and_then(|r| r.0)
        // A stored shape we cannot read is treated as "not set" rather than
        // failing the match: a scorer at a ground needs to start, and the two
        // captains can agree the terms themselves.
        .and_then(|v| serde_json::from_value(v).ok()))
}

pub async fn points_rules(pool: &PgPool, block_id: Uuid) -> Result<PointsRules, sqlx::Error> {
    let settings = block_settings(pool, block_id).await?;
    Ok(PointsRules {
        win: settings.points_win,
        draw: settings.points_draw,
        no_result: settings.points_no_result,
    })
}

pub async fn update_block(
    pool: &PgPool,
    id: Uuid,
    req: &UpdateBlockRequest,
) -> Result<FixtureBlock, sqlx::Error> {
    let format = req.format.map(format_str);
    sqlx::query_as::<_, FixtureBlock>(&format!(
        "UPDATE fixture_blocks SET
             name = COALESCE($2, name),
             format = COALESCE($3, format),
             group_count = COALESCE($4, group_count),
             points_win = COALESCE($5, points_win),
             points_draw = COALESCE($6, points_draw),
             points_no_result = COALESCE($7, points_no_result),
             meet_point = COALESCE($8, meet_point),
             departs_at = COALESCE($9, departs_at),
             travel_notes = COALESCE($10, travel_notes),
             accommodation_notes = COALESCE($11, accommodation_notes),
             cost_cents = COALESCE($12, cost_cents),
             -- `$24` names the settings being unset. Without it a cap could be
             -- set and never removed: COALESCE cannot tell a field that was
             -- left alone from one that was cleared, because JSON cannot.
             description = CASE WHEN 'description' = ANY($24::TEXT[]) THEN NULL
                                ELSE COALESCE($13, description) END,
             venue_id = CASE WHEN 'venue_id' = ANY($24::TEXT[]) THEN NULL
                             ELSE COALESCE($14, venue_id) END,
             max_entrants = CASE WHEN 'max_entrants' = ANY($24::TEXT[]) THEN NULL
                                 ELSE COALESCE($15, max_entrants) END,
             entry_deadline = CASE WHEN 'entry_deadline' = ANY($24::TEXT[]) THEN NULL
                                   ELSE COALESCE($16, entry_deadline) END,
             entry_fee_cents = CASE WHEN 'entry_fee_cents' = ANY($24::TEXT[]) THEN NULL
                                    ELSE COALESCE($17, entry_fee_cents) END,
             players_per_side = COALESCE($18, players_per_side),
             guest_players_allowed = COALESCE($19, guest_players_allowed),
             age_group = COALESCE($20, age_group),
             gender = COALESCE($21, gender),
             conditions = CASE WHEN 'conditions' = ANY($24::TEXT[]) THEN NULL
                               ELSE COALESCE($22, conditions) END,
             rules_notes = CASE WHEN 'rules_notes' = ANY($24::TEXT[]) THEN NULL
                                ELSE COALESCE($23, rules_notes) END
         WHERE id = $1
         RETURNING {BLOCK_COLS}"
    ))
    .bind(id)
    .bind(&req.name)
    .bind(format)
    .bind(req.group_count)
    .bind(req.points_win)
    .bind(req.points_draw)
    .bind(req.points_no_result)
    .bind(&req.meet_point)
    .bind(req.departs_at)
    .bind(&req.travel_notes)
    .bind(&req.accommodation_notes)
    .bind(req.cost_cents)
    .bind(&req.settings.description)
    .bind(req.settings.venue_id)
    .bind(req.settings.max_entrants)
    .bind(req.settings.entry_deadline)
    .bind(req.settings.entry_fee_cents)
    .bind(req.settings.players_per_side)
    .bind(req.settings.guest_players_allowed)
    .bind(&req.settings.age_group)
    .bind(&req.settings.gender)
    .bind(
        req.settings
            .conditions
            .as_ref()
            .map(serde_json::to_value)
            .transpose()
            .unwrap_or_default(),
    )
    .bind(&req.settings.rules_notes)
    .bind(&req.settings.clear)
    .fetch_one(pool)
    .await
}

fn format_str(format: TournamentFormat) -> &'static str {
    match format {
        TournamentFormat::None => "none",
        TournamentFormat::RoundRobin => "round_robin",
        TournamentFormat::GroupsKnockout => "groups_knockout",
        TournamentFormat::Knockout => "knockout",
        TournamentFormat::Ladder => "ladder",
    }
}

pub fn parse_format(raw: &str) -> TournamentFormat {
    match raw {
        "round_robin" => TournamentFormat::RoundRobin,
        "groups_knockout" => TournamentFormat::GroupsKnockout,
        "knockout" => TournamentFormat::Knockout,
        "ladder" => TournamentFormat::Ladder,
        _ => TournamentFormat::None,
    }
}

// MARK: entrants

/// Enter sides an organiser typed in themselves.
///
/// These are in the draw the moment they are added — the organiser is entering
/// them, not asking them. Asking a real club is [`invite_entrant`].
pub async fn add_entrants(
    pool: &PgPool,
    block_id: Uuid,
    req: &AddEntrantsRequest,
) -> Result<Result<Vec<TournamentEntrant>, String>, sqlx::Error> {
    let mut tx = pool.begin().await?;

    // The organiser's own cap applies to the organiser. Typing eleven names
    // into an eight-side tournament otherwise made the limit meaningless and
    // the draw wrong, while inviting a ninth club was refused.
    let max: Option<i32> =
        sqlx::query_scalar("SELECT max_entrants FROM fixture_blocks WHERE id = $1 FOR UPDATE")
            .bind(block_id)
            .fetch_one(&mut *tx)
            .await?;
    if let Some(max) = max {
        let taken: (i64,) = sqlx::query_as(
            "SELECT COUNT(*) FROM tournament_entrants
             WHERE block_id = $1 AND status IN ('invited', 'accepted')",
        )
        .bind(block_id)
        .fetch_one(&mut *tx)
        .await?;
        // Counted before any are written, so "room for two, you gave five" is
        // refused whole rather than entering two and dropping three.
        let room = max as i64 - taken.0;
        if (req.entrants.len() as i64) > room {
            return Ok(Err(if room <= 0 {
                format!("this tournament is full at {max} sides")
            } else {
                format!("only room for {room} more — you gave {}", req.entrants.len())
            }));
        }
    }

    let mut added = Vec::with_capacity(req.entrants.len());
    for entrant in &req.entrants {
        // Two unique indexes, so two conflict targets: a club enters once, and
        // a free-text side is unique by name among the other free-text sides.
        let conflict = if entrant.club_id.is_some() {
            "(block_id, club_id) WHERE club_id IS NOT NULL"
        } else {
            "(block_id, lower(name)) WHERE club_id IS NULL"
        };
        let row = sqlx::query_as::<_, TournamentEntrant>(&format!(
            r#"
            INSERT INTO tournament_entrants
                (block_id, name, club_id, team_id, seed, contact_name, contact_email)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            ON CONFLICT {conflict} DO UPDATE SET
                name = EXCLUDED.name,
                club_id = EXCLUDED.club_id,
                team_id = EXCLUDED.team_id,
                seed = EXCLUDED.seed,
                contact_name = EXCLUDED.contact_name,
                contact_email = EXCLUDED.contact_email,
                -- A side that has been asked and not yet answered keeps its
                -- invitation. Re-typing their name is not them saying yes.
                status = CASE WHEN tournament_entrants.status = 'invited'
                              THEN tournament_entrants.status ELSE 'accepted' END
            RETURNING {ENTRANT_COLS}
            "#
        ))
        .bind(block_id)
        .bind(&entrant.name)
        .bind(entrant.club_id)
        .bind(entrant.team_id)
        .bind(entrant.seed)
        .bind(&entrant.contact_name)
        .bind(&entrant.contact_email)
        .fetch_one(&mut *tx)
        .await?;
        added.push(row);
    }
    tx.commit().await?;
    Ok(Ok(added))
}

/// Ask a side into a tournament. They answer for themselves.
///
/// Asking a side that is already in the draw is refused rather than silently
/// resetting their answer. Asking one that said no, or pulled out, puts the
/// question back to them — clubs change their minds, and re-entering a side
/// should not mean deleting them first.
pub async fn invite_entrant(
    pool: &PgPool,
    block_id: Uuid,
    invited_by: Uuid,
    req: &InviteEntrantRequest,
    name: &str,
    token: Option<&str>,
) -> Result<Result<TournamentEntrant, String>, sqlx::Error> {
    let mut tx = pool.begin().await?;

    // Lock the block: two organisers inviting the same club at the same moment
    // would otherwise both read "not entered" and both insert, and both could
    // pass a "one place left" check.
    let limits: (Option<i32>, Option<DateTime<Utc>>) = sqlx::query_as(
        "SELECT max_entrants, entry_deadline FROM fixture_blocks WHERE id = $1 FOR UPDATE",
    )
    .bind(block_id)
    .fetch_one(&mut *tx)
    .await?;

    if let Some(closed) = limits.1 {
        if Utc::now() > closed {
            return Ok(Err("entries for this tournament have closed".into()));
        }
    }

    let existing = sqlx::query_as::<_, TournamentEntrant>(&format!(
        "SELECT {ENTRANT_COLS} FROM tournament_entrants
         WHERE block_id = $1 AND (($2::UUID IS NOT NULL AND club_id = $2)
                                  OR ($2::UUID IS NULL AND lower(name) = lower($3)))
         FOR UPDATE"
    ))
    .bind(block_id)
    .bind(req.club_id)
    .bind(name)
    .fetch_optional(&mut *tx)
    .await?;

    if let Some(entrant) = existing {
        return Ok(match entrant.status.as_str() {
            EntryStatus::ACCEPTED => Err(format!("{name} is already in this tournament")),
            // Still waiting on them: hand back the same invitation rather than
            // stacking a second one up, so re-sending is safe.
            EntryStatus::INVITED => Ok(entrant),
            _ => {
                let again = sqlx::query_as::<_, TournamentEntrant>(&format!(
                    "UPDATE tournament_entrants
                     SET status = 'invited', invited_by = $2, invite_token = $3,
                         responded_at = NULL, seed = COALESCE($4, seed),
                         contact_name = COALESCE($5, contact_name),
                         contact_email = COALESCE($6, contact_email)
                     WHERE id = $1
                     RETURNING {ENTRANT_COLS}"
                ))
                .bind(entrant.id)
                .bind(invited_by)
                .bind(token)
                .bind(req.seed)
                .bind(&req.contact_name)
                .bind(&req.contact_email)
                .fetch_one(&mut *tx)
                .await?;
                tx.commit().await?;
                Ok(again)
            }
        });
    }

    // A side that is already in the draw was returned above, so reaching here
    // means one more. A declined side being asked again also passes through the
    // branch above, which is why the count is only checked on a genuinely new
    // entry: re-asking somebody who pulled out must not be refused for space
    // they are about to give back.
    if let Some(max) = limits.0 {
        let taken: (i64,) = sqlx::query_as(
            "SELECT COUNT(*) FROM tournament_entrants
             WHERE block_id = $1 AND status IN ('invited', 'accepted')",
        )
        .bind(block_id)
        .fetch_one(&mut *tx)
        .await?;
        if taken.0 >= max as i64 {
            return Ok(Err(format!("this tournament is full at {max} sides")));
        }
    }

    let entrant = sqlx::query_as::<_, TournamentEntrant>(&format!(
        r#"
        INSERT INTO tournament_entrants
            (block_id, name, club_id, team_id, seed, contact_name, contact_email,
             status, invited_by, invite_token)
        VALUES ($1, $2, $3, $4, $5, $6, $7, 'invited', $8, $9)
        RETURNING {ENTRANT_COLS}
        "#
    ))
    .bind(block_id)
    .bind(name)
    .bind(req.club_id)
    .bind(req.team_id)
    .bind(req.seed)
    .bind(&req.contact_name)
    .bind(&req.contact_email)
    .bind(invited_by)
    .bind(token)
    .fetch_one(&mut *tx)
    .await?;

    tx.commit().await?;
    Ok(Ok(entrant))
}

/// A side answers, or pulls out. The allowed moves live in the domain, so the
/// rule is the same here as it is in the apps.
pub async fn set_entry_status(
    pool: &PgPool,
    entrant_id: Uuid,
    to: &str,
) -> Result<Result<TournamentEntrant, String>, sqlx::Error> {
    let mut tx = pool.begin().await?;
    let current: Option<(String, String)> = sqlx::query_as(
        "SELECT status, name FROM tournament_entrants WHERE id = $1 FOR UPDATE",
    )
    .bind(entrant_id)
    .fetch_optional(&mut *tx)
    .await?;

    let Some((from, name)) = current else {
        return Ok(Err("entrant not found".into()));
    };
    if from == to {
        return Ok(Err(format!("{name} is already {to}")));
    }
    if !EntryStatus::can_move(&from, to) {
        return Ok(Err(format!("a side that is {from} cannot become {to}")));
    }

    let entrant = sqlx::query_as::<_, TournamentEntrant>(&format!(
        // This function only ever *answers* an invitation — `can_move` has no
        // transition back to `invited` — so the link is always spent here.
        // Re-inviting a side that declined issues a fresh one, in
        // `invite_entrant`.
        "UPDATE tournament_entrants
         SET status = $2, responded_at = NOW(), invite_token = NULL
         WHERE id = $1
         RETURNING {ENTRANT_COLS}"
    ))
    .bind(entrant_id)
    .bind(to)
    .fetch_one(&mut *tx)
    .await?;

    tx.commit().await?;
    Ok(Ok(entrant))
}

/// Mark an entry fee settled by an organiser — a cheque, a bank transfer, cash
/// in an envelope. The card path settles itself through the webhook.
pub async fn record_entry_payment(
    pool: &PgPool,
    entrant_id: Uuid,
    method: &str,
) -> Result<Option<TournamentEntrant>, sqlx::Error> {
    sqlx::query_as::<_, TournamentEntrant>(&format!(
        "UPDATE tournament_entrants
         SET entry_paid_at = COALESCE(entry_paid_at, NOW()),
             entry_payment_method = COALESCE(entry_payment_method, $2)
         WHERE id = $1
         RETURNING {ENTRANT_COLS}"
    ))
    .bind(entrant_id)
    .bind(method)
    .fetch_optional(pool)
    .await
}

/// What a side owes to enter, and whether they have paid it.
pub async fn entry_fee_for(
    pool: &PgPool,
    entrant_id: Uuid,
) -> Result<Option<(Uuid, Option<i32>, Option<DateTime<Utc>>)>, sqlx::Error> {
    sqlx::query_as(
        "SELECT en.block_id, fb.entry_fee_cents, en.entry_paid_at
         FROM tournament_entrants en
         JOIN fixture_blocks fb ON fb.id = en.block_id
         WHERE en.id = $1",
    )
    .bind(entrant_id)
    .fetch_optional(pool)
    .await
}

/// Tournaments a club has been asked into and has not answered, plus the ones
/// it is already in — the club's own view of its season.
pub async fn entry_invitations(
    pool: &PgPool,
    club_id: Uuid,
    pending_only: bool,
) -> Result<Vec<EntryInvitation>, sqlx::Error> {
    sqlx::query_as::<_, EntryInvitation>(
        r#"
        SELECT en.id            AS entrant_id,
               en.block_id,
               fb.name          AS block_name,
               fb.kind,
               fb.starts_on,
               fb.ends_on,
               fb.club_id       AS host_club_id,
               c.name           AS host_club_name,
               en.name          AS entrant_name,
               en.club_id,
               en.status,
               (SELECT name FROM users WHERE id = en.invited_by) AS invited_by_name,
               fb.entry_fee_cents,
               en.entry_paid_at,
               en.created_at
        FROM tournament_entrants en
        JOIN fixture_blocks fb ON fb.id = en.block_id
        JOIN clubs c ON c.id = fb.club_id
        WHERE en.club_id = $1
          AND (NOT $2 OR en.status = 'invited')
        ORDER BY fb.starts_on NULLS LAST, en.created_at DESC
        "#,
    )
    .bind(club_id)
    .bind(pending_only)
    .fetch_all(pool)
    .await
}

/// Resolve an emailed invitation link.
pub async fn entrant_by_token(
    pool: &PgPool,
    token: &str,
) -> Result<Option<TournamentEntrant>, sqlx::Error> {
    sqlx::query_as::<_, TournamentEntrant>(&format!(
        "SELECT {ENTRANT_COLS} FROM tournament_entrants WHERE invite_token = $1"
    ))
    .bind(token)
    .fetch_optional(pool)
    .await
}

pub async fn get_entrant(
    pool: &PgPool,
    entrant_id: Uuid,
) -> Result<Option<TournamentEntrant>, sqlx::Error> {
    sqlx::query_as::<_, TournamentEntrant>(&format!(
        "SELECT {ENTRANT_COLS} FROM tournament_entrants WHERE id = $1"
    ))
    .bind(entrant_id)
    .fetch_optional(pool)
    .await
}

pub async fn list_entrants(
    pool: &PgPool,
    block_id: Uuid,
) -> Result<Vec<TournamentEntrant>, sqlx::Error> {
    sqlx::query_as::<_, TournamentEntrant>(&format!(
        "SELECT {ENTRANT_COLS} FROM tournament_entrants WHERE block_id = $1
         ORDER BY group_label NULLS LAST, seed NULLS LAST, name"
    ))
    .bind(block_id)
    .fetch_all(pool)
    .await
}

pub async fn withdraw_entrant(pool: &PgPool, entrant_id: Uuid) -> Result<(), sqlx::Error> {
    // `withdrawn` is generated from `status` now, so this writes the status.
    sqlx::query("UPDATE tournament_entrants SET status = 'withdrawn', responded_at = NOW()
                 WHERE id = $1")
        .bind(entrant_id)
        .execute(pool)
        .await?;
    Ok(())
}

async fn set_groups(
    pool: &PgPool,
    allocation: &[(Uuid, String)],
) -> Result<(), sqlx::Error> {
    for (entrant_id, group) in allocation {
        sqlx::query("UPDATE tournament_entrants SET group_label = $2 WHERE id = $1")
            .bind(entrant_id)
            .bind(group)
            .execute(pool)
            .await?;
    }
    Ok(())
}

// MARK: the grid

pub async fn generate_slots(
    pool: &PgPool,
    block_id: Uuid,
    req: &GenerateSlotsRequest,
) -> Result<Vec<Slot>, sqlx::Error> {
    let mut tx = pool.begin().await?;
    if req.replace {
        sqlx::query("DELETE FROM tournament_slots WHERE block_id = $1 AND event_id IS NULL")
            .bind(block_id)
            .execute(&mut *tx)
            .await?;
    }

    let planned = tournament::generate_slots(
        &req.courts,
        req.first_start,
        req.match_minutes,
        req.gap_minutes,
        req.rounds,
    );

    let mut created = Vec::with_capacity(planned.len());
    for slot in planned {
        let row: Option<(Uuid,)> = sqlx::query_as(
            "INSERT INTO tournament_slots (block_id, venue_id, court_label, starts_at, ends_at)
             VALUES ($1, $2, $3, $4, $5)
             ON CONFLICT (block_id, court_label, starts_at) DO NOTHING
             RETURNING id",
        )
        .bind(block_id)
        .bind(req.venue_id)
        .bind(&slot.court_label)
        .bind(slot.starts_at)
        .bind(slot.ends_at)
        .fetch_optional(&mut *tx)
        .await?;
        if let Some(row) = row {
            created.push(Slot { id: row.0, ..slot });
        }
    }
    tx.commit().await?;
    Ok(created)
}

pub async fn list_free_slots(pool: &PgPool, block_id: Uuid) -> Result<Vec<Slot>, sqlx::Error> {
    sqlx::query_as::<_, (Uuid, String, DateTime<Utc>, DateTime<Utc>)>(
        "SELECT id, court_label, starts_at, ends_at FROM tournament_slots
         WHERE block_id = $1 AND event_id IS NULL ORDER BY starts_at, court_label",
    )
    .bind(block_id)
    .fetch_all(pool)
    .await
    .map(|rows| {
        rows.into_iter()
            .map(|(id, court_label, starts_at, ends_at)| Slot {
                id,
                court_label,
                starts_at,
                ends_at,
            })
            .collect()
    })
}

// MARK: schedule

/// Turn generated fixtures into real events, filling their slots.
pub async fn commit_schedule(
    pool: &PgPool,
    block_id: Uuid,
    created_by: Uuid,
    scheduled: &[(GeneratedFixture, Slot)],
    entrant_names: &[(Uuid, String)],
    sport: &str,
    subtype: &str,
) -> Result<usize, sqlx::Error> {
    let name_of = |id: Uuid| {
        entrant_names
            .iter()
            .find(|(entrant_id, _)| *entrant_id == id)
            .map(|(_, name)| name.clone())
            .unwrap_or_else(|| "TBC".into())
    };

    let settings = block_settings(pool, block_id).await?;
    let mut tx = pool.begin().await?;
    let mut created = 0usize;

    for (fixture, slot) in scheduled {
        let (Some(home), Some(away)) = (fixture.home, fixture.away) else {
            continue; // byes are not fixtures
        };
        let title = format!("{} v {}", name_of(home), name_of(away));
        let metadata = serde_json::json!({
            "stage": fixture.stage,
            "round": fixture.round,
            "group_label": fixture.group_label,
            "court_label": slot.court_label,
            "tournament": settings.name,
        });

        let event: (Uuid,) = sqlx::query_as(
            r#"
            INSERT INTO events (club_id, sport, event_subtype, title, start_at, end_at,
                                status, metadata, created_by, fixture_block_id)
            VALUES ($1, $2::sport_type, $3::event_subtype, $4, $5, $6, 'scheduled', $7, $8, $9)
            RETURNING id
            "#,
        )
        .bind(settings.club_id)
        .bind(sport)
        .bind(subtype)
        .bind(&title)
        .bind(slot.starts_at)
        .bind(slot.ends_at)
        .bind(&metadata)
        .bind(created_by)
        .bind(block_id)
        .fetch_one(&mut *tx)
        .await?;

        for (entrant_id, side) in [(home, "home"), (away, "away")] {
            sqlx::query(
                "INSERT INTO event_entrants (event_id, entrant_id, side)
                 VALUES ($1, $2, $3)
                 ON CONFLICT (event_id, entrant_id) DO NOTHING",
            )
            .bind(event.0)
            .bind(entrant_id)
            .bind(side)
            .execute(&mut *tx)
            .await?;
        }

        sqlx::query("UPDATE tournament_slots SET event_id = $2 WHERE id = $1")
            .bind(slot.id)
            .bind(event.0)
            .execute(&mut *tx)
            .await?;

        created += 1;
    }

    tx.commit().await?;
    Ok(created)
}

/// Assign groups before generating a group stage.
pub async fn apply_groups(
    pool: &PgPool,
    entrants: &[Entrant],
    group_count: usize,
) -> Result<Vec<(Uuid, String)>, sqlx::Error> {
    let allocation = tournament::allocate_groups(entrants, group_count);
    set_groups(pool, &allocation).await?;
    Ok(allocation)
}

pub async fn schedule_rows(
    pool: &PgPool,
    block_id: Uuid,
) -> Result<Vec<ScheduleRow>, sqlx::Error> {
    sqlx::query_as::<_, ScheduleRow>(
        r#"
        SELECT e.id AS event_id,
               e.title,
               e.start_at AS starts_at,
               e.metadata ->> 'court_label' AS court_label,
               e.metadata ->> 'stage' AS stage,
               (e.metadata ->> 'round')::INT AS round,
               e.metadata ->> 'group_label' AS group_label,
               home.name AS home_name,
               away.name AS away_name,
               hs.score AS home_score,
               aws.score AS away_score,
               hs.result AS home_result,
               e.status::TEXT AS status
        FROM events e
        LEFT JOIN event_entrants hs ON hs.event_id = e.id AND hs.side = 'home'
        LEFT JOIN event_entrants aws ON aws.event_id = e.id AND aws.side = 'away'
        LEFT JOIN tournament_entrants home ON home.id = hs.entrant_id
        LEFT JOIN tournament_entrants away ON away.id = aws.entrant_id
        WHERE e.fixture_block_id = $1
        ORDER BY e.start_at, court_label
        "#,
    )
    .bind(block_id)
    .fetch_all(pool)
    .await
}

// MARK: results and the table

pub async fn record_result(
    pool: &PgPool,
    event_id: Uuid,
    req: &RecordResultRequest,
    rules: PointsRules,
) -> Result<(), sqlx::Error> {
    let mut tx = pool.begin().await?;
    for entrant in &req.entrants {
        sqlx::query(
            "UPDATE event_entrants
             SET score = $3, result = $4, points = $5, score_detail = $6
             WHERE event_id = $1 AND entrant_id = $2",
        )
        .bind(event_id)
        .bind(entrant.entrant_id)
        .bind(entrant.score)
        .bind(&entrant.result)
        .bind(rules.points_for(&entrant.result))
        .bind(&entrant.score_detail)
        .execute(&mut *tx)
        .await?;
    }
    sqlx::query("UPDATE events SET status = 'completed', updated_at = NOW() WHERE id = $1")
        .bind(event_id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(())
}

pub async fn standings(pool: &PgPool, block_id: Uuid) -> Result<Vec<Standing>, sqlx::Error> {
    let mut table = sqlx::query_as::<_, Standing>(
        "SELECT entrant_id, name, group_label, played, won, lost, drawn, no_result,
                points, scored, conceded
         FROM tournament_standings WHERE block_id = $1",
    )
    .bind(block_id)
    .fetch_all(pool)
    .await?;
    tournament::order_standings(&mut table);
    Ok(table)
}

// MARK: ticketed events

/// Book a place, with guests if the event allows them. Capacity is checked
/// inside the transaction so two people can't take the last two places.
pub async fn book_ticket(
    pool: &PgPool,
    event_id: Uuid,
    user_id: Uuid,
    req: &BookTicketRequest,
) -> Result<Result<EventTicket, String>, sqlx::Error> {
    let mut tx = pool.begin().await?;

    let event: (Option<i32>, Option<i32>, i32, Option<DateTime<Utc>>, String) = sqlx::query_as(
        "SELECT ticket_price_cents, ticket_capacity, guests_allowed, rsvp_deadline, fee_currency
         FROM events WHERE id = $1 FOR UPDATE",
    )
    .bind(event_id)
    .fetch_one(&mut *tx)
    .await?;

    if let Some(deadline) = event.3 {
        if Utc::now() > deadline {
            return Ok(Err("bookings for this event have closed".into()));
        }
    }
    if req.guests > event.2 {
        return Ok(Err(format!(
            "this event allows {} guest{} per member",
            event.2,
            if event.2 == 1 { "" } else { "s" }
        )));
    }

    if let Some(capacity) = event.1 {
        let taken: (Option<i64>,) = sqlx::query_as(
            "SELECT SUM(1 + guests) FROM event_tickets
             WHERE event_id = $1 AND status <> 'cancelled' AND user_id <> $2",
        )
        .bind(event_id)
        .bind(user_id)
        .fetch_one(&mut *tx)
        .await?;
        let wanted = 1 + req.guests as i64;
        if taken.0.unwrap_or(0) + wanted > capacity as i64 {
            let left = (capacity as i64 - taken.0.unwrap_or(0)).max(0);
            return Ok(Err(format!("only {left} place(s) left")));
        }
    }

    let amount = event.0.unwrap_or(0) * (1 + req.guests);
    let ticket = sqlx::query_as::<_, EventTicket>(
        r#"
        INSERT INTO event_tickets (event_id, user_id, guests, guest_names, amount_cents,
                                   currency, notes)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        ON CONFLICT (event_id, user_id) DO UPDATE SET
            guests = EXCLUDED.guests,
            guest_names = EXCLUDED.guest_names,
            amount_cents = EXCLUDED.amount_cents,
            notes = EXCLUDED.notes,
            status = CASE WHEN event_tickets.status = 'cancelled' THEN 'reserved'
                          ELSE event_tickets.status END,
            updated_at = NOW()
        RETURNING id, event_id, user_id, NULL::TEXT AS name, guests, guest_names, amount_cents,
                  currency, status, notes, created_at
        "#,
    )
    .bind(event_id)
    .bind(user_id)
    .bind(req.guests)
    .bind(&req.guest_names)
    .bind(amount)
    .bind(&event.4)
    .bind(&req.notes)
    .fetch_one(&mut *tx)
    .await?;

    tx.commit().await?;
    Ok(Ok(ticket))
}

pub async fn list_tickets(
    pool: &PgPool,
    event_id: Uuid,
) -> Result<Vec<EventTicket>, sqlx::Error> {
    sqlx::query_as::<_, EventTicket>(
        r#"
        SELECT t.id, t.event_id, t.user_id, u.name, t.guests, t.guest_names, t.amount_cents,
               t.currency, t.status, t.notes, t.created_at
        FROM event_tickets t
        JOIN users u ON u.id = t.user_id
        WHERE t.event_id = $1
        ORDER BY t.status, u.name
        "#,
    )
    .bind(event_id)
    .fetch_all(pool)
    .await
}

pub async fn ticket_summary(
    pool: &PgPool,
    event_id: Uuid,
) -> Result<TicketSummary, sqlx::Error> {
    sqlx::query_as::<_, TicketSummary>(
        "SELECT event_id, title, ticket_capacity, ticket_price_cents, guests_allowed,
                tickets_public, bookings, headcount, collected_cents, outstanding_cents
         FROM event_ticket_summary WHERE event_id = $1",
    )
    .bind(event_id)
    .fetch_one(pool)
    .await
}

pub async fn set_ticket_status(
    pool: &PgPool,
    ticket_id: Uuid,
    user_id: Option<Uuid>,
    status: &str,
) -> Result<Option<EventTicket>, sqlx::Error> {
    sqlx::query_as::<_, EventTicket>(
        r#"
        UPDATE event_tickets t
        SET status = $3, updated_at = NOW()
        WHERE t.id = $1 AND ($2::uuid IS NULL OR t.user_id = $2)
        RETURNING t.id, t.event_id, t.user_id, NULL::TEXT AS name, t.guests, t.guest_names,
                  t.amount_cents, t.currency, t.status, t.notes, t.created_at
        "#,
    )
    .bind(ticket_id)
    .bind(user_id)
    .bind(status)
    .fetch_optional(pool)
    .await
}

/// One ticket, for the checks a payment has to make before taking money.
pub async fn get_ticket(pool: &PgPool, ticket_id: Uuid) -> Result<Option<EventTicket>, sqlx::Error> {
    sqlx::query_as::<_, EventTicket>(
        r#"
        SELECT t.id, t.event_id, t.user_id, u.name, t.guests, t.guest_names, t.amount_cents,
               t.currency, t.status, t.notes, t.created_at
        FROM event_tickets t
        JOIN users u ON u.id = t.user_id
        WHERE t.id = $1
        "#,
    )
    .bind(ticket_id)
    .fetch_optional(pool)
    .await
}

/// Record money that arrived outside the app. Stamped with who recorded it, so
/// the treasurer's book has a name against every cash payment.
pub async fn record_ticket_payment(
    pool: &PgPool,
    ticket_id: Uuid,
    recorded_by: Uuid,
    method: &str,
) -> Result<Option<EventTicket>, sqlx::Error> {
    sqlx::query_as::<_, EventTicket>(
        r#"
        UPDATE event_tickets
        SET status = 'paid',
            paid_at = COALESCE(paid_at, NOW()),
            paid_by = $2,
            payment_method = $3,
            updated_at = NOW()
        WHERE id = $1 AND status <> 'cancelled'
        RETURNING id, event_id, user_id, NULL::TEXT AS name, guests, guest_names,
                  amount_cents, currency, status, notes, created_at
        "#,
    )
    .bind(ticket_id)
    .bind(recorded_by)
    .bind(method)
    .fetch_optional(pool)
    .await
}

pub async fn ticket_event(pool: &PgPool, ticket_id: Uuid) -> Result<Option<Uuid>, sqlx::Error> {
    let row: Option<(Uuid,)> = sqlx::query_as("SELECT event_id FROM event_tickets WHERE id = $1")
        .bind(ticket_id)
        .fetch_optional(pool)
        .await?;
    Ok(row.map(|r| r.0))
}

/// Entrants as the generator wants them.
/// The sides a draw is actually made from.
///
/// Confirmed only, which means two things: a club that was asked and never
/// answered is not a fixture, and — where the tournament charges — neither is
/// one that said yes and has not paid. Building a fixture list around sides
/// who might still not turn up is how an organiser loses a Saturday.
///
/// The same rule as `tournament_standings`, and in SQL for the same reason:
/// the draw and the table must not each decide it for themselves.
pub async fn entrants_for_generation(
    pool: &PgPool,
    block_id: Uuid,
) -> Result<Vec<Entrant>, sqlx::Error> {
    sqlx::query_as::<_, (Uuid, String, Option<i32>, Option<String>)>(
        "SELECT en.id, en.name, en.seed, en.group_label
         FROM tournament_entrants en
         JOIN fixture_blocks fb ON fb.id = en.block_id
         WHERE en.block_id = $1
           AND en.status = 'accepted'
           AND (COALESCE(fb.entry_fee_cents, 0) = 0 OR en.entry_paid_at IS NOT NULL)
         ORDER BY en.group_label NULLS LAST, en.seed NULLS LAST, en.name",
    )
    .bind(block_id)
    .fetch_all(pool)
    .await
    .map(|rows| {
        rows.into_iter()
            .map(|(id, name, seed, group_label)| Entrant { id, name, seed, group_label })
            .collect()
    })
}

/// The whole invitation as the club being asked needs to read it: what the
/// tournament is, who is running it, what it costs, and where their answer
/// has got to.
///
/// One query, because the invited club cannot read the tournament any other
/// way — they are not members of the club running it.
#[derive(Debug, Clone, serde::Serialize, sqlx::FromRow)]
pub struct InvitationView {
    pub entrant_id: Uuid,
    pub entrant_name: String,
    pub status: String,
    pub club_id: Option<Uuid>,
    pub entry_paid_at: Option<DateTime<Utc>>,
    pub entry_payment_method: Option<String>,
    pub block_id: Uuid,
    pub block_name: String,
    pub kind: String,
    pub description: Option<String>,
    pub starts_on: Option<chrono::NaiveDate>,
    pub ends_on: Option<chrono::NaiveDate>,
    pub host_club_id: Uuid,
    pub host_club_name: String,
    pub invited_by_name: Option<String>,
    pub entry_fee_cents: Option<i32>,
    pub entry_deadline: Option<DateTime<Utc>>,
    pub max_entrants: Option<i32>,
    pub players_per_side: i32,
    pub guest_players_allowed: i32,
    pub age_group: String,
    pub gender: String,
    #[sqlx(json(nullable))]
    pub conditions: Option<fishers_domain::MatchConditions>,
    pub rules_notes: Option<String>,
    pub venue_name: Option<String>,
}

pub async fn invitation(
    pool: &PgPool,
    entrant_id: Uuid,
) -> Result<Option<InvitationView>, sqlx::Error> {
    sqlx::query_as::<_, InvitationView>(
        r#"
        SELECT en.id AS entrant_id, en.name AS entrant_name, en.status, en.club_id,
               en.entry_paid_at, en.entry_payment_method,
               fb.id AS block_id, fb.name AS block_name, fb.kind, fb.description,
               fb.starts_on, fb.ends_on,
               fb.club_id AS host_club_id, c.name AS host_club_name,
               (SELECT name FROM users WHERE id = en.invited_by) AS invited_by_name,
               fb.entry_fee_cents, fb.entry_deadline, fb.max_entrants,
               fb.players_per_side, fb.guest_players_allowed, fb.age_group, fb.gender,
               fb.conditions, fb.rules_notes,
               (SELECT name FROM venues WHERE id = fb.venue_id) AS venue_name
        FROM tournament_entrants en
        JOIN fixture_blocks fb ON fb.id = en.block_id
        JOIN clubs c ON c.id = fb.club_id
        WHERE en.id = $1
        "#,
    )
    .bind(entrant_id)
    .fetch_optional(pool)
    .await
}

/// Whether this person may read a tournament: a member of the club running it,
/// or of a club it has asked in. Without the second half the invited club
/// cannot see what it is being asked to agree to.
pub async fn may_read_block(
    pool: &PgPool,
    block_id: Uuid,
    user_id: Uuid,
) -> Result<bool, sqlx::Error> {
    sqlx::query_scalar::<_, bool>(
        r#"
        SELECT EXISTS (
            SELECT 1
            FROM fixture_blocks fb
            JOIN club_members cm ON cm.club_id = fb.club_id
                                AND cm.user_id = $2 AND cm.status = 'active'
            WHERE fb.id = $1
        ) OR EXISTS (
            SELECT 1
            FROM tournament_entrants en
            JOIN club_members cm ON cm.club_id = en.club_id
                                AND cm.user_id = $2 AND cm.status = 'active'
            WHERE en.block_id = $1 AND en.club_id IS NOT NULL
        )
        "#,
    )
    .bind(block_id)
    .bind(user_id)
    .fetch_one(pool)
    .await
}

/// Default rest between a side's games, used when a request omits it.
pub fn default_rest() -> Duration {
    Duration::minutes(30)
}
