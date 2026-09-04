//! Role-based access control for Fishers clubs and teams.
//!
//! Product roles map to [`UserRole`]:
//! - **Club secretary** → [`UserRole::ClubAdmin`] (manages roster, invites, venues, fees)
//! - **Team captain** → [`UserRole::TeamCaptain`] (invites to play, squad selection)
//! - **Member / guest** → join, RSVP, availability; cannot invite others to play

use serde::{Deserialize, Serialize};

use crate::UserRole;

/// Fine-grained actions gated by club/team role.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Permission {
    /// View club details, teams, fixtures (any active member).
    ViewClub,
    /// Mark own availability / RSVP.
    RespondAsPlayer,
    /// Invite a person into the club (secretary).
    InviteToClub,
    /// Invite a person onto a team (secretary or that team's captain).
    InviteToTeam,
    /// Invite a player to a specific session/match (secretary or captain).
    InviteToEvent,
    /// Create / edit / cancel fixtures for the club.
    ManageEvents,
    /// Commit and publish a squad / selection board.
    ManageSelection,
    /// Add/remove members and assign roles (secretary).
    ManageMembers,
    /// Create teams and venues, shop products, fee chase.
    ManageClubOps,
    /// Run / apply the admin assistant proposals.
    UseAdminAssistant,
    /// Platform-level club onboarding (super admin only).
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
            Self::ManagePlatform => "manage_platform",
        }
    }
}

impl UserRole {
    /// Human-facing label (secretary is the product name for club_admin).
    pub fn display_name(self) -> &'static str {
        match self {
            Self::SuperAdmin => "Super admin",
            Self::ClubAdmin => "Club secretary",
            Self::TeamCaptain => "Team captain",
            Self::Member => "Member",
            Self::Guest => "Guest",
        }
    }

    pub fn can(self, permission: Permission) -> bool {
        permissions_for(self).contains(&permission)
    }

    /// Captain or secretary (or platform admin) — who may invite people to play.
    pub fn can_invite_to_play(self) -> bool {
        self.can(Permission::InviteToEvent)
    }

    pub fn is_club_officer(self) -> bool {
        matches!(
            self,
            Self::SuperAdmin | Self::ClubAdmin | Self::TeamCaptain
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
    ManagePlatform,
];

/// Club secretary — roster, invites, ops, selection oversight.
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
];

/// Captain — invite to play, pick squads, run fixture chat assistant.
const TEAM_CAPTAIN_PERMS: &[Permission] = &[
    ViewClub,
    RespondAsPlayer,
    InviteToTeam,
    InviteToEvent,
    ManageEvents,
    ManageSelection,
    UseAdminAssistant,
];

const MEMBER_PERMS: &[Permission] = &[ViewClub, RespondAsPlayer];

/// Static permission matrix. Keep this the single source of truth.
pub fn permissions_for(role: UserRole) -> &'static [Permission] {
    match role {
        UserRole::SuperAdmin => SUPER_ADMIN_PERMS,
        UserRole::ClubAdmin => CLUB_SECRETARY_PERMS,
        UserRole::TeamCaptain => TEAM_CAPTAIN_PERMS,
        UserRole::Member | UserRole::Guest => MEMBER_PERMS,
    }
}

/// Effective role for a user in a club context (highest of club + optional team).
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

/// Parse DB / JSON role strings (`club_admin`, `team_captain`, …).
pub fn parse_role(raw: &str) -> Option<UserRole> {
    match raw {
        "super_admin" => Some(UserRole::SuperAdmin),
        "club_admin" | "club_secretary" | "secretary" => Some(UserRole::ClubAdmin),
        "team_captain" | "captain" => Some(UserRole::TeamCaptain),
        "member" => Some(UserRole::Member),
        "guest" => Some(UserRole::Guest),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn secretary_can_invite_to_play_member_cannot() {
        assert!(UserRole::ClubAdmin.can_invite_to_play());
        assert!(UserRole::TeamCaptain.can_invite_to_play());
        assert!(!UserRole::Member.can_invite_to_play());
        assert!(!UserRole::Guest.can_invite_to_play());
    }

    #[test]
    fn only_secretary_manages_members() {
        assert!(UserRole::ClubAdmin.can(Permission::ManageMembers));
        assert!(!UserRole::TeamCaptain.can(Permission::ManageMembers));
        assert!(!UserRole::Member.can(Permission::ManageMembers));
    }

    #[test]
    fn captain_can_select_squad() {
        assert!(UserRole::TeamCaptain.can(Permission::ManageSelection));
        assert!(UserRole::ClubAdmin.can(Permission::ManageSelection));
        assert!(!UserRole::Member.can(Permission::ManageSelection));
    }

    #[test]
    fn parse_secretary_aliases() {
        assert_eq!(parse_role("secretary"), Some(UserRole::ClubAdmin));
        assert_eq!(parse_role("club_secretary"), Some(UserRole::ClubAdmin));
        assert_eq!(parse_role("captain"), Some(UserRole::TeamCaptain));
    }

    #[test]
    fn effective_role_prefers_higher() {
        assert_eq!(
            effective_role(Some(UserRole::Member), Some(UserRole::TeamCaptain)),
            Some(UserRole::TeamCaptain)
        );
        assert_eq!(
            effective_role(Some(UserRole::ClubAdmin), Some(UserRole::TeamCaptain)),
            Some(UserRole::ClubAdmin)
        );
    }
}
