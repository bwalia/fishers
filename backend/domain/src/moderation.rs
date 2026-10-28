//! Reporting something, and blocking somebody.
//!
//! An app with chat, profiles, photographs and free-text listings between
//! strangers needs both: a way to tell us something is wrong, and a way for
//! one person to stop another reaching them without waiting on us first.
//!
//! A block is stored as the person's own act — *I* blocked *them* — and read
//! symmetrically wherever it is enforced. See [`Block::HIDES_BOTH_WAYS`].

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use validator::Validate;

/// What a report is about. Not an enum in the database: reports outlive the
/// rows they name, so the pairing is a kind plus an id rather than a foreign
/// key per table.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SubjectKind {
    Message,
    Listing,
    User,
    Club,
}

impl SubjectKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Message => "message",
            Self::Listing => "listing",
            Self::User => "user",
            Self::Club => "club",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "message" => Some(Self::Message),
            "listing" => Some(Self::Listing),
            "user" => Some(Self::User),
            "club" => Some(Self::Club),
            _ => None,
        }
    }
}

/// Why. A fixed list rather than free text, because the note is optional and
/// a report with nothing but an empty note tells whoever reads it nothing.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ReportReason {
    /// Abuse, threats, harassment of a person.
    Abuse,
    /// Sexual, violent or otherwise objectionable content.
    Objectionable,
    /// Advertising, scams, repeated junk.
    Spam,
    /// Pretending to be somebody else, including a club.
    Impersonation,
    /// Somebody's details posted without them.
    Privacy,
    /// None of the above; the note carries it.
    Other,
}

impl ReportReason {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Abuse => "abuse",
            Self::Objectionable => "objectionable",
            Self::Spam => "spam",
            Self::Impersonation => "impersonation",
            Self::Privacy => "privacy",
            Self::Other => "other",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "abuse" => Some(Self::Abuse),
            "objectionable" => Some(Self::Objectionable),
            "spam" => Some(Self::Spam),
            "impersonation" => Some(Self::Impersonation),
            "privacy" => Some(Self::Privacy),
            "other" => Some(Self::Other),
            _ => None,
        }
    }
}

/// One block, as the person who made it would describe it.
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Block {
    pub blocker_id: Uuid,
    pub blocked_id: Uuid,
    pub created_at: DateTime<Utc>,
}

impl Block {
    /// Enforcement reads a block in both directions. Stated here because it
    /// is the one rule every call site has to agree on: a block that worked
    /// only outward would leave the person who blocked still being talked
    /// at, which is what they were trying to stop.
    pub const HIDES_BOTH_WAYS: bool = true;
}

/// Somebody on your blocked list, with enough to recognise them by.
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct BlockedUser {
    pub id: Uuid,
    pub name: String,
    pub avatar_url: Option<String>,
    pub blocked_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct CreateReportRequest {
    pub subject_kind: SubjectKind,
    pub subject_id: Uuid,
    pub reason: ReportReason,
    /// Optional, and capped: a note is context, not an essay, and an
    /// unbounded text column reachable by anybody signed in is a place to
    /// put a megabyte.
    #[validate(length(max = 2000, message = "A note can be up to 2000 characters."))]
    pub note: Option<String>,
}

/// A report as whoever reviews it sees it.
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct ContentReport {
    pub id: Uuid,
    pub reporter_id: Option<Uuid>,
    pub reporter_name: Option<String>,
    pub subject_kind: String,
    pub subject_id: Uuid,
    pub reason: String,
    pub note: Option<String>,
    pub status: String,
    pub created_at: DateTime<Utc>,
    pub reviewed_at: Option<DateTime<Utc>>,
}

/// What a reviewer decides. `Open` is not here: a decision cannot be "no
/// decision", and reopening is a new report rather than a status flip.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ReportVerdict {
    Actioned,
    Dismissed,
}

impl ReportVerdict {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Actioned => "actioned",
            Self::Dismissed => "dismissed",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Every variant round-trips through the string the database stores. The
    /// two halves are written out by hand in opposite directions, so a new
    /// variant added to one and forgotten in the other fails here rather
    /// than becoming a row nothing can read back.
    #[test]
    fn every_reason_survives_the_database() {
        for reason in [
            ReportReason::Abuse,
            ReportReason::Objectionable,
            ReportReason::Spam,
            ReportReason::Impersonation,
            ReportReason::Privacy,
            ReportReason::Other,
        ] {
            assert_eq!(ReportReason::parse(reason.as_str()), Some(reason));
        }
        assert_eq!(ReportReason::parse("whatever"), None);
    }

    #[test]
    fn every_subject_kind_survives_the_database() {
        for kind in [
            SubjectKind::Message,
            SubjectKind::Listing,
            SubjectKind::User,
            SubjectKind::Club,
        ] {
            assert_eq!(SubjectKind::parse(kind.as_str()), Some(kind));
        }
        assert_eq!(SubjectKind::parse(""), None);
    }

    /// The reason arrives as JSON from a phone, so the wire spelling is part
    /// of the contract and not an implementation detail.
    #[test]
    fn a_report_is_read_from_the_json_a_phone_sends() {
        let body = serde_json::json!({
            "subject_kind": "message",
            "subject_id": "00000000-0000-0000-0000-000000000001",
            "reason": "abuse",
            "note": "called me names"
        });
        let req: CreateReportRequest = serde_json::from_value(body).expect("parses");
        assert_eq!(req.subject_kind, SubjectKind::Message);
        assert_eq!(req.reason, ReportReason::Abuse);
        assert!(req.validate().is_ok());
    }

    #[test]
    fn a_note_longer_than_the_column_is_refused() {
        let req = CreateReportRequest {
            subject_kind: SubjectKind::User,
            subject_id: Uuid::nil(),
            reason: ReportReason::Other,
            note: Some("x".repeat(2001)),
        };
        assert!(req.validate().is_err());
    }
}
