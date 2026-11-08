use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use validator::Validate;

use crate::{InviteTarget, RsvpStatus};

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct EventInvite {
    pub id: Uuid,
    pub event_id: Uuid,
    pub user_id: Uuid,
    pub invited_by: Uuid,
    pub status: RsvpStatus,
    pub responded_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Invite {
    pub id: Uuid,
    pub target_type: InviteTarget,
    pub target_id: Uuid,
    pub invited_user_id: Option<Uuid>,
    pub invited_email: Option<String>,
    pub invited_by: Uuid,
    pub token: String,
    pub status: String,
    pub created_at: DateTime<Utc>,
    pub accepted_at: Option<DateTime<Utc>>,
    /// An open link: addressed to nobody, never spent, good for everyone who
    /// follows it until the club turns it off. `default` so a row read by a
    /// query that does not select it is an ordinary one-use invite.
    #[sqlx(default)]
    #[serde(default)]
    pub open: bool,
    /// How many people have joined through an open link.
    #[sqlx(default)]
    #[serde(default)]
    pub uses: i32,
    /// What the invite is to — the club, "team · club", or the fixture — and
    /// who sent it. Filled in only when listing somebody's own invites: an
    /// invite reading "A club invitation" asks people to join without saying
    /// what they are joining. `default` so every other query can leave them out.
    #[sqlx(default)]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub target_name: Option<String>,
    #[sqlx(default)]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub invited_by_name: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct CreateInviteRequest {
    pub target_type: InviteTarget,
    pub target_id: Uuid,
    pub invited_user_id: Option<Uuid>,
    pub invited_email: Option<String>,
}

/// What an invite link is to, for somebody who has not signed in yet. Enough
/// to say "Join Southall Strikers" on the page instead of "You have been
/// invited" to who knows what — and nothing about who else was invited.
#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct InvitePreview {
    pub target_type: InviteTarget,
    pub target_id: Uuid,
    /// The club the link leads into: the club itself, a team's club, or the
    /// fixture's club.
    pub club_id: Option<Uuid>,
    pub club_name: Option<String>,
    pub team_name: Option<String>,
    pub event_title: Option<String>,
    pub invited_by_name: Option<String>,
    pub open: bool,
    /// False once a one-use invite is spent or the open link is turned off,
    /// so the page can say so before anyone bothers to sign up.
    pub usable: bool,
}

#[derive(Debug, Clone, Deserialize)]
pub struct RsvpRequest {
    pub status: RsvpStatus,
}

#[derive(Debug, Clone, Serialize)]
pub struct AttendeeSummary {
    pub user_id: Uuid,
    pub name: String,
    pub status: RsvpStatus,
    pub availability: Option<crate::AvailabilityStatus>,
    pub paid: bool,
    /// Which side they are on. A fixture asks both clubs, so a list of names
    /// with nothing to separate them is two squads in a heap — and on a
    /// twenty-a-side league that is forty strangers in one column.
    pub club_id: Option<Uuid>,
    pub club_name: Option<String>,
    /// The last fixture they actually turned out for, for *that* club. It is
    /// the difference between a squad member and a name on a list.
    pub last_played_at: Option<DateTime<Utc>>,
}
