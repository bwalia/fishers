import SwiftUI

/// One step of the first-run guide.
struct GuideStep: Identifiable, Equatable {
    enum Action: Equatable {
        case verify, startClub, addTeam, invitePlayers, chooseCaptain, scheduleFixture
        case shareProfile, acceptInvite
    }

    let id: String
    let title: String
    let detail: String
    let done: Bool
    let action: Action
}

/// The steps for the role somebody chose, in order.
///
/// Each one is worked out from real state — a club that exists, a team with a
/// name, a member with the captain role — never from "they tapped the button",
/// so it cannot tick off something that did not happen. The same rules as the
/// dashboard's guide, so a phone and a laptop agree on what is left.
enum GettingStartedGuide {
    struct Facts {
        var role: RoleIntent
        var user: PublicUser
        /// The server asks for confirmation and can send a code.
        var canVerify: Bool
        var ownClub: Club?
        var teamCount: Int
        var members: [ClubMemberDetail]
        var eventCount: Int
        var inviteCount: Int
        var clubCount: Int
        var sharedOnce: Bool
    }

    static func steps(_ f: Facts) -> [GuideStep] {
        var steps: [GuideStep] = []
        if f.canVerify {
            steps.append(GuideStep(
                id: "verify",
                title: tr("Confirm it's you"),
                detail: tr("Proves it's really you. Clubs are only started, and invites only accepted, by confirmed accounts."),
                done: f.user.isVerified,
                action: .verify
            ))
        }

        switch f.role {
        case .secretary:
            steps += [
                GuideStep(
                    id: "club", title: tr("Start your club"),
                    detail: tr("Its name and sport. You become the secretary — you run the teams, fixtures and who's in."),
                    done: f.ownClub != nil, action: .startClub
                ),
                GuideStep(
                    id: "team", title: tr("Add your first team"),
                    detail: tr("A 1st XI, a Sunday side, the juniors — each team gets its own squad and fixtures."),
                    done: f.teamCount > 0, action: .addTeam
                ),
                GuideStep(
                    id: "players", title: tr("Invite your players"),
                    detail: tr("Add people by email or mobile number, or from the profile link a player sends you."),
                    done: f.members.count > 1, action: .invitePlayers
                ),
                GuideStep(
                    id: "captain", title: tr("Name a captain"),
                    detail: tr("Give one member the captain role — or, if you captain the side yourself, say so. Captains pick the side and run the scorebook."),
                    done: f.members.contains { $0.role == .teamCaptain || $0.isCaptain == true },
                    action: .chooseCaptain
                ),
                GuideStep(
                    id: "fixture", title: tr("Schedule your first fixture"),
                    detail: tr("Who, where and when. Players mark themselves available and the captain picks the side."),
                    done: f.eventCount > 0, action: .scheduleFixture
                ),
            ]
        case .player:
            steps += [
                GuideStep(
                    id: "share", title: tr("Send your profile to your club secretary"),
                    detail: tr("They open your link and invite you in. No need for them to type your details."),
                    done: f.sharedOnce || f.inviteCount > 0 || f.clubCount > 0, action: .shareProfile
                ),
                GuideStep(
                    id: "join", title: tr("Accept your club's invite"),
                    detail: f.inviteCount > 0
                        ? "It's waiting at the top of this screen — check it's your club, then tap Accept."
                        : "When your secretary invites you, it appears at the top of this screen, ready to accept.",
                    done: f.clubCount > 0, action: .acceptInvite
                ),
            ]
        }
        return steps
    }
}

/// Loads what the guide needs beyond what Home already has.
@MainActor
final class GettingStartedStore: ObservableObject {
    @Published private(set) var verification: VerificationStatus?
    @Published private(set) var teams: [Team] = []
    @Published private(set) var members: [ClubMemberDetail] = []
    @Published private(set) var ownClubRole: ClubRoleInfo?
    @Published private(set) var sharedOnce = false

    func load(user: PublicUser, ownClub: Club?) async {
        sharedOnce = UserDefaults.standard.bool(forKey: ShareProfileView.sharedKey(user.id))
        async let status = FishersAPI.verificationStatus()
        if let club = ownClub {
            async let teamList = FishersAPI.teams(clubId: club.id)
            async let m = FishersAPI.clubMembers(clubId: club.id)
            async let r = FishersAPI.myClubRole(clubId: club.id)
            teams = (try? await teamList) ?? []
            members = (try? await m) ?? []
            ownClubRole = try? await r
        } else {
            teams = []
            members = []
            ownClubRole = nil
        }
        verification = try? await status
    }

    func markShared() { sharedOnce = true }
}

/// The guide, as a section at the top of Home.
struct GettingStartedSection: View {
    let role: RoleIntent
    let steps: [GuideStep]
    let verification: VerificationStatus?
    let ownClub: Club?
    let ownClubRole: ClubRoleInfo?
    let user: PublicUser
    let onChanged: () async -> Void
    let onShared: () -> Void
    /// Sheets belong to the screen, not to a section inside its list: SwiftUI
    /// does not reliably present one from list content, and the button then
    /// does nothing. Home presents them.
    let onStartClub: () -> Void

    @EnvironmentObject private var session: SessionStore
    @State private var switching = false

    private var current: GuideStep? { steps.first { !$0.done } }
    private var doneCount: Int { steps.filter(\.done).count }

    var body: some View {
        if let current {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        "Getting started · \(role == .secretary ? "Club secretary" : "Player")",
                        systemImage: "sparkles"
                    )
                    .font(FishersTheme.overline)
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(FishersTheme.pitch)

                    Text(role == .secretary ? tr("Let's set up your club") : tr("Let's get you into your club"))
                        .font(FishersTheme.title)
                    Text(t("cl.n_of_m_done", vars: ["done": doneCount, "total": steps.count, "left": steps.count - doneCount]))
                        .font(FishersTheme.subhead)
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(doneCount), total: Double(steps.count))
                        .tint(FishersTheme.pitch)
                        .accessibilityLabel(tr("Setup progress"))
                        .accessibilityValue("\(doneCount) of \(steps.count)")
                }
                .padding(.vertical, 4)

                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    stepRow(step, number: index + 1, isCurrent: step == current)
                }

                Button {
                    switching = true
                    Task {
                        try? await session.setRoleIntent(role == .secretary ? .player : .secretary)
                        switching = false
                        await onChanged()
                    }
                } label: {
                    Text(role == .secretary
                         ? tr("Here to play, not to run a club? Switch to the player guide")
                         : tr("Running a club instead? Switch to the secretary guide"))
                        .font(FishersTheme.footnote)
                        .frame(minHeight: FishersTheme.minTap)
                }
                .buttonStyle(.borderless)
                .disabled(switching)
            }
        }
    }

    @ViewBuilder
    private func stepRow(_ step: GuideStep, number: Int, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                marker(step, number: number, isCurrent: isCurrent)
                Text(step.title)
                    .font(isCurrent ? FishersTheme.headline : FishersTheme.body)
                    .foregroundStyle(step.done || !isCurrent ? .secondary : .primary)
                    .strikethrough(step.done, color: .secondary)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(step.done ? tr("Done") : isCurrent ? tr("Next") : tr("Later"))

            if isCurrent {
                Text(step.detail)
                    .font(FishersTheme.subhead)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                action(for: step)
            }
        }
        .padding(.vertical, isCurrent ? 6 : 0)
    }

    private func marker(_ step: GuideStep, number: Int, isCurrent: Bool) -> some View {
        ZStack {
            Circle()
                .fill(step.done ? FishersTheme.pitch : FishersTheme.cream)
                .overlay(Circle().strokeBorder(isCurrent || step.done ? FishersTheme.pitch : FishersTheme.hairline, lineWidth: 2))
            if step.done {
                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
            } else if isCurrent {
                Text("\(number)").font(FishersTheme.caption).foregroundStyle(FishersTheme.pitch)
            } else {
                Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func action(for step: GuideStep) -> some View {
        switch step.action {
        case .verify:
            if let verification {
                VerifyContactView(status: verification, compact: true) { user in
                    session.adopt(user)
                    Task { await onChanged() }
                }
            }
        case .startClub:
            primary("Start your club", systemImage: "plus", action: onStartClub)
        case .shareProfile:
            ShareProfileView(userId: user.id, onShared: onShared)
        case .acceptInvite:
            EmptyView()
        case .addTeam, .scheduleFixture:
            if let ownClub {
                NavigationLink {
                    ClubDetailView(club: ownClub)
                } label: {
                    Label(step.action == .addTeam ? tr("Add a team") : tr("Schedule a match"),
                          systemImage: step.action == .addTeam ? "person.3" : "calendar.badge.plus")
                        .font(FishersTheme.headline)
                }
            }
        case .invitePlayers, .chooseCaptain:
            if let ownClub {
                NavigationLink {
                    ClubAdminView(club: ownClub, role: ownClubRole)
                } label: {
                    Label(step.action == .invitePlayers ? tr("Invite players") : tr("Choose a captain"),
                          systemImage: step.action == .invitePlayers ? "person.badge.plus" : tr("star"))
                        .font(FishersTheme.headline)
                }
            }
        }
    }

    private func primary(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(FishersTheme.headline)
                .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
        }
        .buttonStyle(.borderedProminent)
    }
}
