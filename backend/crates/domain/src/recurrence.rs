//! RRULE-subset recurrence engine.
//!
//! Supports enough of RFC 5545 for club fixtures like
//! "every Wednesday 6–8pm, June–August":
//!
//! `FREQ=WEEKLY;INTERVAL=1;BYDAY=WE;UNTIL=20260831T235959Z`
//!
//! Supported parts: `FREQ` (WEEKLY | DAILY), `INTERVAL`, `BYDAY` (comma list of
//! MO,TU,WE,TH,FR,SA,SU — WEEKLY only), `UNTIL` (`YYYYMMDDTHHMMSSZ` or
//! `YYYYMMDD`, inclusive), `COUNT`. All times are UTC.

use chrono::{DateTime, Datelike, Duration, NaiveDate, NaiveDateTime, Utc, Weekday};

const MAX_ITERATIONS: u32 = 5_000;

#[derive(Debug, thiserror::Error, PartialEq)]
pub enum RecurrenceError {
    #[error("empty recurrence rule")]
    Empty,
    #[error("malformed part `{0}` (expected KEY=VALUE)")]
    MalformedPart(String),
    #[error("unsupported FREQ `{0}` (supported: WEEKLY, DAILY)")]
    UnsupportedFreq(String),
    #[error("invalid {key} value `{value}`")]
    InvalidValue { key: &'static str, value: String },
    #[error("missing FREQ")]
    MissingFreq,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Freq {
    Weekly,
    Daily,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RecurrenceRule {
    pub freq: Freq,
    pub interval: u32,
    pub by_day: Vec<Weekday>,
    pub until: Option<DateTime<Utc>>,
    pub count: Option<u32>,
}

impl RecurrenceRule {
    /// Parse an RRULE string (with or without a leading `RRULE:`).
    pub fn parse(rule: &str) -> Result<Self, RecurrenceError> {
        let rule = rule.trim().trim_start_matches("RRULE:").trim();
        if rule.is_empty() {
            return Err(RecurrenceError::Empty);
        }

        let mut freq = None;
        let mut interval = 1u32;
        let mut by_day = Vec::new();
        let mut until = None;
        let mut count = None;

        for part in rule.split(';').filter(|p| !p.trim().is_empty()) {
            let (key, value) = part
                .split_once('=')
                .ok_or_else(|| RecurrenceError::MalformedPart(part.to_string()))?;
            let value = value.trim();
            match key.trim().to_ascii_uppercase().as_str() {
                "FREQ" => {
                    freq = Some(match value.to_ascii_uppercase().as_str() {
                        "WEEKLY" => Freq::Weekly,
                        "DAILY" => Freq::Daily,
                        other => return Err(RecurrenceError::UnsupportedFreq(other.to_string())),
                    })
                }
                "INTERVAL" => {
                    interval = value.parse::<u32>().ok().filter(|i| *i >= 1).ok_or(
                        RecurrenceError::InvalidValue {
                            key: "INTERVAL",
                            value: value.to_string(),
                        },
                    )?
                }
                "BYDAY" => {
                    for day in value.split(',') {
                        by_day.push(parse_weekday(day.trim()).ok_or(
                            RecurrenceError::InvalidValue {
                                key: "BYDAY",
                                value: day.to_string(),
                            },
                        )?);
                    }
                }
                "UNTIL" => {
                    until = Some(parse_until(value).ok_or(RecurrenceError::InvalidValue {
                        key: "UNTIL",
                        value: value.to_string(),
                    })?)
                }
                "COUNT" => {
                    count = Some(value.parse::<u32>().map_err(|_| {
                        RecurrenceError::InvalidValue {
                            key: "COUNT",
                            value: value.to_string(),
                        }
                    })?)
                }
                // Ignore parts we don't support rather than failing hard.
                _ => {}
            }
        }

        let freq = freq.ok_or(RecurrenceError::MissingFreq)?;
        let mut by_day = by_day;
        by_day.sort_by_key(|d| d.num_days_from_monday());
        by_day.dedup();

        Ok(Self {
            freq,
            interval,
            by_day,
            until,
            count,
        })
    }

    /// Expand occurrence start times within `[window_start, window_end]`.
    ///
    /// `dtstart` is the first occurrence (the event's own start); occurrences
    /// keep its time of day. At most `cap` results are returned.
    pub fn occurrences(
        &self,
        dtstart: DateTime<Utc>,
        window_start: DateTime<Utc>,
        window_end: DateTime<Utc>,
        cap: usize,
    ) -> Vec<DateTime<Utc>> {
        let mut out = Vec::new();
        if cap == 0 || window_end < dtstart {
            return out;
        }
        // Occurrences counted against COUNT include those before the window
        // (RRULE COUNT counts from DTSTART).
        let mut emitted: u32 = 0;

        match self.freq {
            Freq::Daily => {
                for k in 0..MAX_ITERATIONS {
                    let occ = dtstart + Duration::days(k as i64 * self.interval as i64);
                    if self.past_limits(occ, window_end, emitted) {
                        break;
                    }
                    emitted += 1;
                    if occ >= window_start {
                        out.push(occ);
                        if out.len() >= cap {
                            break;
                        }
                    }
                }
            }
            Freq::Weekly => {
                let days: Vec<Weekday> = if self.by_day.is_empty() {
                    vec![dtstart.weekday()]
                } else {
                    self.by_day.clone()
                };
                let time = dtstart.time();
                let week0: NaiveDate = dtstart.date_naive()
                    - Duration::days(dtstart.weekday().num_days_from_monday() as i64);

                'outer: for week in 0..MAX_ITERATIONS {
                    let week_start =
                        week0 + Duration::days(week as i64 * 7 * self.interval as i64);
                    for wd in &days {
                        let date = week_start + Duration::days(wd.num_days_from_monday() as i64);
                        let occ: DateTime<Utc> =
                            NaiveDateTime::new(date, time).and_utc();
                        if occ < dtstart {
                            continue;
                        }
                        if self.past_limits(occ, window_end, emitted) {
                            break 'outer;
                        }
                        emitted += 1;
                        if occ >= window_start {
                            out.push(occ);
                            if out.len() >= cap {
                                break 'outer;
                            }
                        }
                    }
                }
            }
        }
        out
    }

    fn past_limits(&self, occ: DateTime<Utc>, window_end: DateTime<Utc>, emitted: u32) -> bool {
        if occ > window_end {
            return true;
        }
        if let Some(until) = self.until {
            if occ > until {
                return true;
            }
        }
        if let Some(count) = self.count {
            if emitted >= count {
                return true;
            }
        }
        false
    }
}

fn parse_weekday(s: &str) -> Option<Weekday> {
    match s.to_ascii_uppercase().as_str() {
        "MO" => Some(Weekday::Mon),
        "TU" => Some(Weekday::Tue),
        "WE" => Some(Weekday::Wed),
        "TH" => Some(Weekday::Thu),
        "FR" => Some(Weekday::Fri),
        "SA" => Some(Weekday::Sat),
        "SU" => Some(Weekday::Sun),
        _ => None,
    }
}

fn parse_until(s: &str) -> Option<DateTime<Utc>> {
    if let Ok(ndt) = NaiveDateTime::parse_from_str(s, "%Y%m%dT%H%M%SZ") {
        return Some(ndt.and_utc());
    }
    // Bare date: treat as inclusive of that whole day.
    if let Ok(date) = NaiveDate::parse_from_str(s, "%Y%m%d") {
        return date.and_hms_opt(23, 59, 59).map(|ndt| ndt.and_utc());
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn utc(y: i32, mo: u32, d: u32, h: u32, mi: u32) -> DateTime<Utc> {
        Utc.with_ymd_and_hms(y, mo, d, h, mi, 0).unwrap()
    }

    #[test]
    fn weekly_wednesday_nets_june_to_august() {
        // "every Wednesday 6–8pm, June–August"
        let rule = RecurrenceRule::parse("FREQ=WEEKLY;INTERVAL=1;BYDAY=WE;UNTIL=20260831").unwrap();
        let dtstart = utc(2026, 6, 3, 18, 0); // first Wednesday of June
        let occs = rule.occurrences(dtstart, dtstart, utc(2026, 12, 31, 0, 0), 100);
        assert_eq!(occs.len(), 13); // 13 Wednesdays: 3 Jun – 26 Aug
        assert_eq!(occs[0], dtstart);
        assert_eq!(occs[1], utc(2026, 6, 10, 18, 0));
        assert_eq!(*occs.last().unwrap(), utc(2026, 8, 26, 18, 0));
        for o in &occs {
            assert_eq!(o.weekday(), Weekday::Wed);
            assert_eq!(o.time(), dtstart.time());
        }
    }

    #[test]
    fn weekly_multiple_days_and_window() {
        let rule = RecurrenceRule::parse("FREQ=WEEKLY;BYDAY=MO,FR").unwrap();
        let dtstart = utc(2026, 1, 5, 19, 0); // a Monday
        // Window only covers the second week.
        let occs = rule.occurrences(dtstart, utc(2026, 1, 11, 0, 0), utc(2026, 1, 18, 0, 0), 100);
        assert_eq!(occs, vec![utc(2026, 1, 12, 19, 0), utc(2026, 1, 16, 19, 0)]);
    }

    #[test]
    fn biweekly_interval() {
        let rule = RecurrenceRule::parse("FREQ=WEEKLY;INTERVAL=2;BYDAY=SA").unwrap();
        let dtstart = utc(2026, 6, 6, 10, 0); // a Saturday
        let occs = rule.occurrences(dtstart, dtstart, utc(2026, 7, 6, 0, 0), 100);
        assert_eq!(
            occs,
            vec![utc(2026, 6, 6, 10, 0), utc(2026, 6, 20, 10, 0), utc(2026, 7, 4, 10, 0)]
        );
    }

    #[test]
    fn count_limits_total_occurrences() {
        let rule = RecurrenceRule::parse("FREQ=DAILY;COUNT=3").unwrap();
        let dtstart = utc(2026, 6, 1, 9, 0);
        let occs = rule.occurrences(dtstart, dtstart, utc(2026, 12, 1, 0, 0), 100);
        assert_eq!(occs.len(), 3);
        assert_eq!(occs[2], utc(2026, 6, 3, 9, 0));
    }

    #[test]
    fn count_is_anchored_at_dtstart_not_window() {
        let rule = RecurrenceRule::parse("FREQ=DAILY;COUNT=5").unwrap();
        let dtstart = utc(2026, 6, 1, 9, 0);
        // Window starts after the first three occurrences: only #4 and #5 land in it.
        let occs = rule.occurrences(dtstart, utc(2026, 6, 4, 0, 0), utc(2026, 12, 1, 0, 0), 100);
        assert_eq!(occs, vec![utc(2026, 6, 4, 9, 0), utc(2026, 6, 5, 9, 0)]);
    }

    #[test]
    fn until_datetime_form_is_respected() {
        let rule =
            RecurrenceRule::parse("RRULE:FREQ=WEEKLY;BYDAY=WE;UNTIL=20260617T180000Z").unwrap();
        let dtstart = utc(2026, 6, 3, 18, 0);
        let occs = rule.occurrences(dtstart, dtstart, utc(2026, 12, 31, 0, 0), 100);
        assert_eq!(occs.len(), 3); // 3rd, 10th, 17th June
    }

    #[test]
    fn defaults_to_dtstart_weekday_without_byday() {
        let rule = RecurrenceRule::parse("FREQ=WEEKLY").unwrap();
        let dtstart = utc(2026, 6, 4, 18, 30); // a Thursday
        let occs = rule.occurrences(dtstart, dtstart, utc(2026, 6, 20, 0, 0), 100);
        assert_eq!(occs, vec![dtstart, utc(2026, 6, 11, 18, 30), utc(2026, 6, 18, 18, 30)]);
    }

    #[test]
    fn parse_errors() {
        assert_eq!(RecurrenceRule::parse(""), Err(RecurrenceError::Empty));
        assert_eq!(
            RecurrenceRule::parse("INTERVAL=2"),
            Err(RecurrenceError::MissingFreq)
        );
        assert!(matches!(
            RecurrenceRule::parse("FREQ=MONTHLY"),
            Err(RecurrenceError::UnsupportedFreq(_))
        ));
        assert!(matches!(
            RecurrenceRule::parse("FREQ=WEEKLY;BYDAY=XX"),
            Err(RecurrenceError::InvalidValue { key: "BYDAY", .. })
        ));
    }

    #[test]
    fn cap_bounds_output() {
        let rule = RecurrenceRule::parse("FREQ=DAILY").unwrap();
        let dtstart = utc(2026, 1, 1, 8, 0);
        let occs = rule.occurrences(dtstart, dtstart, utc(2030, 1, 1, 0, 0), 10);
        assert_eq!(occs.len(), 10);
    }
}
