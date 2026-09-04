//! Role-based access control for Fishers clubs and teams.
//!
//! Product roles map to [`UserRole`]:
//! - **Club secretary** → [`UserRole::ClubAdmin`]
//! - **Team captain** → [`UserRole::TeamCaptain`]
//! - **Vice captain** → [`UserRole::TeamViceCaptain`] (score matches, help selection)
//! - **Member / guest** → join, RSVP; cannot invite or score unless listed as match official

use serde::{Deserialize, Serialize};

use crate::UserRole;

/// Fine-grained actions gated by club/team role.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Permission {
    ViewClub,
    RespondAsPlayer,
    InviteToClub,
    InviteToTeam,
    InviteToEvent,
    ManageEvents,
    ManageSelection,
    ManageMembers,
    ManageClubOps,
    UseAdminAssistant,
    /// Live cricket scoring / claim scorer session.
    ScoreMatch,
    ManagePlatform,
}

impl Permission {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::ViewClub => "view_club",
            Self::RespondAsPlayer => "respond_as_player",
            Self::InviteToClub => "invite_to_club",
            Self::InviteToTeam => "invite_to_team",
            Self::InviteToEvent => "invite_to_event",
            Self::ManageEvents => "manage_events",
            Self::ManageSelection => "manage_selection",
            Self::ManageMembers => "manage_members",
            Self::ManageClubOps => "manage_club_ops",
            Self::UseAdminAssistant => "use_admin_assistant",
            Self::ScoreMatch => "score_match",
            Self::ManagePlatform => "manage_platform",
        }
    }
}

impl UserRole {
    pub fn display_name(self) -> &'static str {
        match self {
            Self::SuperAdmin => "Super admin",
            Self::ClubAdmin => "Club secretary",
            Self::TeamCaptain => "Team captain",
            Self::TeamViceCaptain => "Vice captain",
            Self::Member => "Member",
            Self::Guest => "Guest",
        }
    }

    pub fn can(self, permission: Permission) -> bool {
        permissions_for(self).contains(&permission)
    }

    pub fn can_invite_to_play(self) -> bool {
        self.can(Permission::InviteToEvent)
    }

    pub fn can_score_match(self) -> bool {
        self.can(Permission::ScoreMatch)
    }

    pub fn is_club_officer(self) -> bool {
        matches!(
            self,
            Self::SuperAdmin
                | Self::ClubAdmin
                | Self::TeamCaptain
                | Self::TeamViceCaptain
        )
    }
}

use Permission::*;

const SUPER_ADMIN_PERMS: &[Permission] = &[
    ViewClub,
    RespondAsPlayer,
    InviteToClub,
    InviteToTeam,
    InviteToEvent,
    ManageEvents,
    ManageSelection,
    ManageMembers,
    ManageClubOps,
    UseAdminAssistant,
    ScoreMatch,
    ManagePlatform,
];

const CLUB_SECRETARY_PERMS: &[Permission] = &[
    ViewClub,
    RespondAsPlayer,
    InviteToClub,
    InviteToTeam,
    InviteToEvent,
    ManageEvents,
    ManageSelection,
    ManageMembers,
    ManageClubOps,
    UseAdminAssistant,
    ScoreMatch,
];

const TEAM_CAPTAIN_PERMS: &[Permission] = &[
    ViewClub,
    RespondAsPlayer,
    InviteToTeam,
    InviteToEvent,
    ManageEvents,
    ManageSelection,
    UseAdminAssistant,
    ScoreMatch,
];

const TEAM_VICE_CAPTAIN_PERMS: &[Permission] = &[
    ViewClub,
    RespondAsPlayer,
    InviteToEvent,
    ManageSelection,
    ScoreMatch,
];

const MEMBER_PERMS: &[Permission] = &[ViewClub, RespondAsPlayer];

pub fn permissions_for(role: UserRole) -> &'static [Permission] {
    match role {
        UserRole::SuperAdmin => SUPER_ADMIN_PERMS,
        UserRole::ClubAdmin => CLUB_SECRETARY_PERMS,
        UserRole::TeamCaptain => TEAM_CAPTAIN_PERMS,
        UserRole::TeamViceCaptain => TEAM_VICE_CAPTAIN_PERMS,
        UserRole::Member | UserRole::Guest => MEMBER_PERMS,
    }
}

pub fn effective_role(club_role: Option<UserRole>, team_role: Option<UserRole>) -> Option<UserRole> {
    match (club_role, team_role) {
        (Some(a), Some(b)) => Some(higher_role(a, b)),
        (Some(a), None) => Some(a),
        (None, Some(b)) => Some(b),
        (None, None) => None,
    }
}

fn role_rank(role: UserRole) -> u8 {
    match role {
        UserRole::SuperAdmin => 50,
        UserRole::ClubAdmin => 40,
        UserRole::TeamCaptain => 30,
        UserRole::TeamViceCaptain => 25,
        UserRole::Member => 20,
        UserRole::Guest => 10,
    }
}

pub fn higher_role(a: UserRole, b: UserRole) -> UserRole {
    if role_rank(a) >= role_rank(b) {
        a
    } else {
        b
    }
}

pub fn parse_role(raw: &str) -> Option<UserRole> {
    match raw {
        "super_admin" => Some(UserRole::SuperAdmin),
        "club_admin" | "club_secretary" | "secretary" => Some(UserRole::ClubAdmin),
        "team_captain" | "captain" => Some(UserRole::TeamCaptain),
        "team_vice_captain" | "vice_captain" | "vice-captain" => Some(UserRole::TeamViceCaptain),
        "member" => Some(UserRole::Member),
        "guest" => Some(UserRole::Guest),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn secretary_and_captains_can_score() {
        assert!(UserRole::ClubAdmin.can_score_match());
        assert!(UserRole::TeamCaptain.can_score_match());
        assert!(UserRole::TeamViceCaptain.can_score_match());
        assert!(!UserRole::Member.can_score_match());
    }

    #[test]
    fn secretary_can_invite_to_play_member_cannot() {
        assert!(UserRole::ClubAdmin.can_invite_to_play());
        assert!(UserRole::TeamCaptain.can_invite_to_play());
        assert!(!UserRole::Member.can_invite_to_play());
    }

    #[test]
    fn parse_vice_captain() {
        assert_eq!(parse_role("vice_captain"), Some(UserRole::TeamViceCaptain));
        assert_eq!(parse_role("team_vice_captain"), Some(UserRole::TeamViceCaptain));
    }
}
