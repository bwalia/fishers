//! The email a player gets when their club closes the season.
//!
//! Written to be read on a phone in thirty seconds: the good news first, then
//! the handful of numbers that describe their season, the last few innings,
//! any best they set, and one button to the whole thing. Nothing in it is a
//! ranking they come last in — a club's bottom ten do not need an email to
//! tell them so. A member who did not play gets a short thank-you instead of
//! a page of zeros.

use fishers_domain::season::{milestone_label, PlayerGame, SeasonRecordLine};

use crate::brand::{html_escape, Brand};

pub struct SeasonEmail {
    pub subject: String,
    pub text: String,
    pub html: String,
}

/// What the email needs that is not the player's own figures.
pub struct SeasonContext<'a> {
    pub club_name: &'a str,
    pub season: i32,
    pub record: &'a SeasonRecordLine,
    /// Where "See your whole season" goes.
    pub page_url: &'a str,
    pub unsubscribe_url: &'a str,
}

fn first_name(name: &str) -> &str {
    name.split_whitespace().next().unwrap_or("there")
}

fn record_line(r: &SeasonRecordLine) -> String {
    let mut s = format!("Played {}, won {}, lost {}", r.played, r.won, r.lost);
    if r.tied_or_no_result > 0 {
        s.push_str(&format!(", {} tied or no result", r.tied_or_no_result));
    }
    s
}

fn fmt1(x: Option<f64>) -> String {
    x.map(|v| format!("{v:.1}")).unwrap_or_else(|| "–".into())
}

pub fn render(brand: &Brand, game: &PlayerGame, ctx: &SeasonContext) -> SeasonEmail {
    if game.totals.matches == 0 {
        return thank_you(brand, game, ctx);
    }
    let first = first_name(&game.name);
    let t = &game.totals;
    let subject = format!("Your {} season at {}", ctx.season, ctx.club_name);

    // The numbers: only the ones that apply. A batter who never bowled gets
    // no row of dashes for bowling.
    let mut rows: Vec<(String, String)> = vec![("Matches".into(), t.matches.to_string())];
    if t.batting_innings > 0 {
        rows.push(("Runs".into(), t.runs.to_string()));
        rows.push(("Average".into(), fmt1(t.batting_average)));
        rows.push(("Strike rate".into(), fmt1(t.strike_rate)));
        if let Some(h) = t.high_score {
            rows.push(("Best".into(), format!("{h}{}", if t.high_score_not_out { "*" } else { "" })));
        }
    }
    if t.bowling_balls > 0 {
        rows.push(("Wickets".into(), t.wickets.to_string()));
        rows.push(("Economy".into(), t.economy.map(|e| format!("{e:.2}")).unwrap_or_else(|| "–".into())));
        if let Some(b) = t.best_bowling.filter(|b| b.wickets > 0) {
            rows.push(("Best bowling".into(), format!("{}/{}", b.wickets, b.runs)));
        }
    }
    let held = t.catches + t.stumpings;
    if held > 0 {
        rows.push(("Catches".into(), held.to_string()));
    }

    let mut text = format!("Hi {first},\n\nThe {} season at {} is over. Here's yours.\n\n", ctx.season, ctx.club_name);
    for h in &game.highlights {
        text.push_str(&format!("  * {}\n", h.text));
    }
    text.push('\n');
    for (k, v) in &rows {
        text.push_str(&format!("{k}: {v}\n"));
    }

    // The last five, as a strip of scores — newest last, so it reads left
    // to right like the season did.
    let recent: Vec<String> = game
        .form
        .matches
        .iter()
        .take(5)
        .rev()
        .map(|f| {
            let mut bits = Vec::new();
            if f.batted {
                bits.push(format!("{}{}", f.runs, if f.not_out { "*" } else { "" }));
            }
            if f.bowled {
                bits.push(format!("{}/{}", f.wickets, f.runs_conceded));
            }
            if bits.is_empty() {
                bits.push("played".into());
            }
            bits.join(" · ")
        })
        .collect();
    if !recent.is_empty() {
        text.push_str(&format!("\nLast {}: {}\n", recent.len(), recent.join("  |  ")));
    }
    let new_milestones: Vec<String> = game
        .milestones
        .iter()
        .filter(|m| m.this_season && m.code != "first_match")
        .map(|m| milestone_label(&m.code))
        .collect();
    if !new_milestones.is_empty() {
        text.push_str(&format!("\nThis season you reached: {}\n", new_milestones.join(", ")));
    }
    text.push_str(&format!(
        "\n{}: {}\n\nSee your whole season: {}\n\nSee you next season.\n— {}\n\n\
         You get this once a season. Stop these emails: {}\n",
        ctx.club_name,
        record_line(ctx.record),
        ctx.page_url,
        brand.name,
        ctx.unsubscribe_url,
    ));

    // HTML
    let c = &brand.colour;
    let tint = &brand.tint;
    let hl: String = game
        .highlights
        .iter()
        .map(|h| {
            format!(
                r#"<tr><td style="padding:10px 14px;border-left:4px solid {c};background:{tint};border-radius:8px;font-size:15px;line-height:1.5">{}</td></tr><tr><td style="height:8px"></td></tr>"#,
                html_escape(&h.text)
            )
        })
        .collect();
    let cells: String = rows
        .chunks(3)
        .map(|chunk| {
            let tds: String = chunk
                .iter()
                .map(|(k, v)| {
                    format!(
                        r#"<td width="33%" style="padding:10px 6px;text-align:center"><div style="font-size:24px;font-weight:700;color:#1f2a22">{}</div><div style="font-size:12px;color:#5b6660;text-transform:uppercase;letter-spacing:.05em">{}</div></td>"#,
                        html_escape(v),
                        html_escape(k)
                    )
                })
                .collect();
            format!("<tr>{tds}</tr>")
        })
        .collect();
    let strip: String = recent
        .iter()
        .map(|r| {
            format!(
                r#"<td style="padding:4px"><div style="padding:8px 10px;border-radius:8px;background:#f4f1e8;font-size:14px;font-weight:600;text-align:center;white-space:nowrap">{}</div></td>"#,
                html_escape(r)
            )
        })
        .collect();
    let strip = if strip.is_empty() {
        String::new()
    } else {
        format!(
            r#"<tr><td style="padding:16px 28px 0;font-size:13px;color:#5b6660;text-transform:uppercase;letter-spacing:.05em">Your last {n}</td></tr>
<tr><td style="padding:6px 24px 0"><table role="presentation" cellpadding="0" cellspacing="0"><tr>{strip}</tr></table></td></tr>"#,
            n = recent.len()
        )
    };
    let milestones_html = if new_milestones.is_empty() {
        String::new()
    } else {
        format!(
            r#"<tr><td style="padding:16px 28px 0;font-size:15px;line-height:1.6"><strong>Reached this season:</strong> {}</td></tr>"#,
            html_escape(&new_milestones.join(", "))
        )
    };
    let body = format!(
        r#"<tr><td style="padding:4px 28px 0;font-size:22px;font-weight:700;line-height:1.3">Your {season} season at {club}</td></tr>
<tr><td style="padding:8px 28px 16px;font-size:15px;line-height:1.6;color:#3b4740">Hi {first} — the season is over. Here's how yours went.</td></tr>
<tr><td style="padding:0 28px"><table role="presentation" width="100%" cellpadding="0" cellspacing="0">{hl}</table></td></tr>
<tr><td style="padding:8px 22px 0"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border:1px solid #e3ddd0;border-radius:10px">{cells}</table></td></tr>
{strip}
{milestones_html}
<tr><td style="padding:16px 28px 0;font-size:14px;color:#3b4740">{club}: {record}</td></tr>
<tr><td style="padding:22px 28px 28px"><a href="{url}" style="display:inline-block;background:{c};color:#ffffff;text-decoration:none;font-weight:700;padding:12px 22px;border-radius:999px">See your whole season</a></td></tr>"#,
        season = ctx.season,
        club = html_escape(ctx.club_name),
        first = html_escape(first),
        record = html_escape(&record_line(ctx.record)),
        url = html_escape(ctx.page_url),
    );
    let footer = format!(
        r#"You get this once a season, when {club} closes it. <a href="{u}" style="color:#7a847e">Stop season emails</a>."#,
        club = html_escape(ctx.club_name),
        u = html_escape(ctx.unsubscribe_url),
    );
    SeasonEmail { subject, text, html: brand.email_html(&body, Some(&footer)) }
}

/// For a member who did not play: no page of zeros, just thanks and the club's year.
fn thank_you(brand: &Brand, game: &PlayerGame, ctx: &SeasonContext) -> SeasonEmail {
    let first = first_name(&game.name);
    let subject = format!("The {} season at {} is over", ctx.season, ctx.club_name);
    let text = format!(
        "Hi {first},\n\nThe {season} season at {club} is over: the club {record}.\n\nThanks for being part of it. \
         Next season, every match you play is counted — your runs, wickets, catches and bests, \
         all in one place.\n\nSee the club's season: {url}\n\n— {brand}\n\n\
         You get this once a season. Stop these emails: {unsub}\n",
        season = ctx.season,
        club = ctx.club_name,
        record = record_line(ctx.record).to_lowercase(),
        url = ctx.page_url,
        brand = brand.name,
        unsub = ctx.unsubscribe_url,
    );
    let body = format!(
        r#"<tr><td style="padding:4px 28px 0;font-size:22px;font-weight:700;line-height:1.3">The {season} season at {club} is over</td></tr>
<tr><td style="padding:8px 28px 0;font-size:15px;line-height:1.6">Hi {first} — {club} {record}. Thanks for being part of it.</td></tr>
<tr><td style="padding:8px 28px 0;font-size:15px;line-height:1.6;color:#3b4740">Next season, every match you play is counted: your runs, wickets, catches and bests, all in one place.</td></tr>
<tr><td style="padding:22px 28px 28px"><a href="{url}" style="display:inline-block;background:{c};color:#ffffff;text-decoration:none;font-weight:700;padding:12px 22px;border-radius:999px">See the club's season</a></td></tr>"#,
        season = ctx.season,
        club = html_escape(ctx.club_name),
        first = html_escape(first),
        record = html_escape(&record_line(ctx.record)).to_lowercase(),
        url = html_escape(ctx.page_url),
        c = brand.colour,
    );
    let footer = format!(
        r#"You get this once a season. <a href="{}" style="color:#7a847e">Stop season emails</a>."#,
        html_escape(ctx.unsubscribe_url)
    );
    SeasonEmail { subject, text, html: brand.email_html(&body, Some(&footer)) }
}

#[cfg(test)]
mod tests {
    use super::*;
    use fishers_domain::season::PlayerGame;
    use uuid::Uuid;

    fn ctx<'a>(record: &'a SeasonRecordLine) -> SeasonContext<'a> {
        SeasonContext {
            club_name: "Bat & <Ball> CC",
            season: 2026,
            record,
            page_url: "https://x.test/stats",
            unsubscribe_url: "https://x.test/unsubscribe/abc",
        }
    }

    #[test]
    fn a_member_who_did_not_play_gets_thanks_not_zeros() {
        let record = SeasonRecordLine { played: 8, won: 4, lost: 3, tied_or_no_result: 1 };
        let game = PlayerGame::build(Uuid::new_v4(), "Andy Wright".into(), 2026, vec![], None);
        let mail = render(&Brand::default(), &game, &ctx(&record));
        assert_eq!(mail.subject, "The 2026 season at Bat & <Ball> CC is over");
        assert!(mail.text.contains("the club played 8, won 4, lost 3"));
        assert!(!mail.html.contains("Runs") && !mail.html.contains("Average"));
        assert!(mail.text.contains("https://x.test/unsubscribe/abc"));
    }

    #[test]
    fn a_club_name_cannot_inject_html() {
        let record = SeasonRecordLine::default();
        let game = PlayerGame::build(Uuid::new_v4(), "<b>Andy</b>".into(), 2026, vec![], None);
        let mail = render(&Brand::default(), &game, &ctx(&record));
        assert!(!mail.html.contains("<Ball>") && mail.html.contains("&lt;Ball&gt;"));
        assert!(!mail.html.contains("<b>Andy"));
    }
}
