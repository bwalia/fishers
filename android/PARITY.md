# Parity inventory — iOS → Android

Every screen, store, model and endpoint in the iPhone app, and where its
Android counterpart lives or will live. `ios/Fishers/` is the specification;
where this table and the Swift disagree, the Swift is right.

> **The Android app is Kotlin and Compose.** This inventory was written against
> a Flutter port that reached its foundation and one vertical slice before we
> changed course — Flutter earns its keep by serving both phones, and iOS is
> already 26,726 lines of native SwiftUI, so here it was a single-platform
> toolkit carrying an extra runtime for nothing.
>
> The inventory itself survived the change, which is why it is still here: what
> it records is *what the iPhone does*, and that did not change. The **Status**
> column did — everything is `planned` again — and the paths now point at
> `android/app/src/main/kotlin/com/fishers/app/`. Read the Dart paths below as
> the shape of the thing rather than its address.
>
> One row is already different in kind. The cricket engine is no longer ported
> at all: `backend/ffi` exposes the Rust one through UniFFI and Android calls
> it, so the Laws run once, in the code the server scores with.

**Status of this document.** In Kotlin, the foundation is `config/` and
`theme/`, plus the shared engine — built and tested. Everything else is a plan.
The rows below name the piece and its place; the layout is settled before
anyone writes it. Paths were relative to `flutter/` and are being restated
against `android/` as each row is ported.

| Status | Meaning |
|---|---|
| **done** | Ported to Kotlin, tested, on this branch |
| planned | Named and placed; not written yet |
| **gap** | Deliberately not shipping in v1 — see [Deliberate divergences](#deliberate-divergences) |

---

## 1. Screens

50 Swift files under `ios/Fishers/Views/`. Every screen keeps its navigation
path and the same information in the same order of visual priority.

### Root and chrome

| iOS | Android | Status | Notes |
|---|---|---|---|
| `Views/RootView.swift` | `lib/views/root_view.dart` | **done** | Not authenticated → auth, otherwise tabs, with the same 250 ms crossfade. The quick start is not ported, so there is no third branch yet. The palette proof it replaced is still there as `PaletteProof`, which is what the theme tests pump. |
| `Views/MainTabView.swift` | `lib/views/main_tab_view.dart` | **done**, Chats only | A bottom `NavigationBar`: Home, Fixtures, Chats, Clubs, Profile, in that order. Only Chats is built; the other three say which screen is missing rather than rendering blank, and Profile carries sign-out. `LiveAlerts` is not ported. |
| `Views/ShareSheet.swift` | `lib/views/share_sheet.dart` | planned | `UIActivityViewController` → the Android share intent. |
| `Views/Components/FishersBrandHeader.swift` (`FishersBrandHeader`, `FishersMark`) | `lib/views/components/fishers_brand_header.dart` | planned | Auth hero and empty states. |
| `Views/Components/LiveAlerts.swift` (`LiveAlerts`, `AlertThread`, `AlertCard`) | `lib/views/components/live_alerts.dart` | planned | The only `accessibilityIdentifier` in the iOS tree — `"live-alert"` — becomes `Key('live-alert')`. |
| `Views/Components/PeoplePickerView.swift` | `lib/views/components/people_picker_view.dart` | planned | Tabbed one-person picker; search appears above 8 names. |

### Auth and onboarding

| iOS | Android | Status | Notes |
|---|---|---|---|
| `Views/Auth/AuthView.swift` | `lib/views/auth/auth_view.dart` | **done**, email only | Sign in / sign up on one form, with the role question on sign-up. **No social buttons yet**: Apple is a settled gap, and Google needs a native SDK and platform config that have not landed — `social_auth.dart` is ported but nothing calls it. |
| `Views/Onboarding/QuickStartView.swift` (`QuickStartView`, `WelcomeShareSheet`) | `lib/views/onboarding/quick_start_view.dart` | planned | Sport + squad number, both skippable. |
| `Views/Onboarding/RoleChooserView.swift` | `lib/views/onboarding/role_chooser_view.dart` | planned | "I run a club" / "I play for a club". |
| `Views/Onboarding/GettingStarted.swift` (`GuideStep`, `GettingStartedGuide`, `GettingStartedStore`, `GettingStartedSection`) | `lib/views/onboarding/getting_started.dart` + `lib/stores/getting_started_store.dart` | planned | The store moves to `stores/`; the section stays a view. Reloads when the club context arrives. |
| `Views/Onboarding/PendingInvitesSection.swift` | `lib/views/onboarding/pending_invites_section.dart` | planned | Draws nothing when empty. |
| `Views/Onboarding/VerifyContactView.swift` | `lib/views/onboarding/verify_contact_view.dart` | planned | Six-digit email/SMS code. |
| `Views/Onboarding/ShareProfileView.swift` | `lib/views/onboarding/share_profile_view.dart` | planned | Share link, WhatsApp first. |

### Home

| iOS | Android | Status | Notes |
|---|---|---|---|
| `Views/Home/HomeFeedView.swift` (`HomeFeedView`, `EventRow`) | `lib/views/home/home_feed_view.dart` | planned | Club-context feed: role chooser, invites, guide, profile strength, tiles, live fixtures, upcoming. |
| `Views/Home/OverviewTiles.swift` (`OverviewTiles`, `LivePip`) | `lib/views/home/overview_tiles.dart` | planned | Clubs / upcoming / in progress. |
| `Views/Home/LiveFixtureRow.swift` | `lib/views/home/live_fixture_row.dart` | planned | Score-first row for a match in progress. |
| `Views/Home/NotificationsView.swift` | `lib/views/home/notifications_view.dart` | planned | Server-filtered, paged, with read state. |

### Fixtures, calendar and events

| iOS | Android | Status | Notes |
|---|---|---|---|
| `Views/Fixtures/FixturesView.swift` (`FixtureRoute`, `FixturesView`, `FixtureAnswerControl`, `FixturesListPane`, `FixtureRow`, `ScheduleMatchSheet`) | `lib/views/fixtures/fixtures_view.dart` | planned | List / Calendar / Scores segmented control. `ScheduleMatchSheet` → a bottom sheet. |
| `Views/Calendar/AvailabilityCalendarView.swift` (`CalendarPane`) | `lib/views/calendar/availability_calendar_view.dart` | planned | Month grid, three states, bulk "every Saturday". Never colour alone. |
| `Views/Events/EventDetailView.swift` | `lib/views/events/event_detail_view.dart` | planned | One fixture: header, scoring entry, selection card, RSVP, payment, attendees. |
| `Views/Events/EventTicketsView.swift` | `lib/views/events/event_tickets_view.dart` | planned | Book, pay, cancel; headcount and who owes, for a secretary. |

### Selection

| iOS | Android | Status | Notes |
|---|---|---|---|
| `Views/Selection/SelectionBoardView.swift` (`SelectionBoardView`, `CandidateRow`) | `lib/views/selection/selection_board_view.dart` | planned | Pool, ranking, assistant proposal and its reasons, publish; plus the delay / call-off sheet. |

### Chat

| iOS | Android | Status | Notes |
|---|---|---|---|
| `Views/Chat/ChatListView.swift` | `lib/views/chat/chat_list_view.dart` | **done** | Unread counts and a proposals badge. |
| `Views/Chat/ChatThreadView.swift` (`ChatThreadView`, `MessageBubble`) | `lib/views/chat/chat_thread_view.dart` | **done**, minus proposals | Messages and the composer. Opens at the bottom, on the man-of-the-match card when the last message carries one — a card renders *under* its message, so scrolling to the message hides it. `ProposalCard` is **not** ported: applying a proposal is a captain's decision and goes with the rest of the assistant work. |
| `Views/Chat/ManOfTheMatchCard.swift` (`ManOfTheMatchCard`, `CandidateRow`) | `lib/views/chat/man_of_the_match_card.dart` | **done** | Both elevens on the ballot; the tally hidden until you vote; the order held still while the vote is open; "Close the vote" offered to everyone, with the server's refusal shown as a plain sentence. |

### Clubs

| iOS | Android | Status | Notes |
|---|---|---|---|
| `Views/Clubs/ClubsTeamsView.swift` (`ClubsTeamsView`, `ClubRoute`, `ClubRowView`, `ClubCrest`, `NewClubSheet`, `ClubDetailView`) | `lib/views/clubs/clubs_teams_view.dart` | planned | Server-side search, filter and paging with infinite scroll; `ClubDetailView` splits into `lib/views/clubs/club_detail_view.dart`. |
| `Views/Clubs/ClubAdminView.swift` (+ `RosterList`, `RoleBadge`, `RoleSheet`, `PolicyForm`, `FeesList`) | `lib/views/clubs/club_admin_view.dart` | planned | Roster, roles, assistant policy, outstanding fees and chasing. |
| `Views/Clubs/ClubExtras.swift` (`ClubWelcomeSheet`, `TeamRosterView`, `AddTeamSheet`, `GroundsSection`, `AddGroundSheet`, `PublicPageEditorView`, `SharedPlayerCardView`) | `lib/views/clubs/club_extras.dart` | planned | Sheets become bottom sheets or full-screen dialogs by weight. |
| `Views/Clubs/ClubQRView.swift` (`ClubQRView`, `QRImage`, `QRScannerView`) | `lib/views/clubs/club_qr_view.dart` | planned | Code drawn on device from `payload` (the server's `svg` is ignored, as on iOS). Camera permission asked at point of use. |
| `Views/Clubs/ClubStatsView.swift` | `lib/views/clubs/club_stats_view.dart` | planned | Season board and Play-Cricket leaderboards. |

### Cricket

| iOS | Android | Status | Notes |
|---|---|---|---|
| `Views/Cricket/ScoreHubView.swift` (`ScoreHubPane`, `ScoreFixtureRow`, `QuickMatchSheet`) | `lib/views/cricket/score_hub_view.dart` | planned | State filters, server-paged. |
| `Views/Cricket/CricketScoringFlowView.swift` (+ `TeamSheetEditor`, `OfficialsEditor`, `CaptainNameSheet`) | `lib/views/cricket/cricket_scoring_flow_view.dart` | planned | Offline-first setup wizard → live scorer. |
| `Views/Cricket/LiveScorerView.swift` (+ 12 sheets) | `lib/views/cricket/live_scorer_view.dart` | planned | The ball-by-ball scorer. Its twelve sheets stay in the same file, as bottom sheets. |
| `Views/Cricket/CricketScorecardView.swift` (`FollowedScorecardView`, `CricketScorecardView`, `CricketScoreSummary`) | `lib/views/cricket/cricket_scorecard_view.dart` | planned | The follower view reloads off `LiveStream`. |
| `Views/Cricket/OppositionPickerView.swift` | `lib/views/cricket/opposition_picker_view.dart` | planned | Scan, search, or type a name. |
| `Views/Cricket/WagonWheelView.swift` (`FieldBackdrop`, `WagonWheelPicker`, `ShotLine`, `WagonWheelChart`) | `lib/views/cricket/wagon_wheel_view.dart` | planned | `cricketRegion` already ported and tested, mirroring for left-handers included. |
| `Views/Cricket/ShotIconView.swift` | `lib/views/cricket/shot_icon_view.dart` | planned | Mirrors `web/src/components/ShotIcon.tsx`. |
| `Views/Cricket/Moments.swift` (`Moment`, `MomentsBanner`, `MomentCard`) | `lib/views/cricket/moments.dart` | planned | FOUR / SIX / OUT!, diffed from before/after state. An undo is not a celebration. |

### Profile

| iOS | Android | Status | Notes |
|---|---|---|---|
| `Views/Profile/ProfileView.swift` (+ `ShareProfileScreen`, `VerifyAccountScreen`) | `lib/views/profile/profile_view.dart` | planned | Hero, Overview / Batting / Bowling tabs, reliability, season stats. |
| `Views/Profile/ProfileHeroView.swift` | `lib/views/profile/profile_hero_view.dart` | planned | Photo picker for the avatar. |
| `Views/Profile/ProfileEditView.swift` | `lib/views/profile/profile_edit_view.dart` | planned | Each field group is a sub-page. |
| `Views/Profile/ProfileForms.swift` (`AboutForm`, `SportsPicker`, `SportDetailForm`, `LogisticsForm`) | `lib/views/profile/profile_forms.dart` | planned | Shared by first-run setup and the edit sheet. |
| `Views/Profile/ProfileFieldViews.swift` (18 types incl. `AvatarView`, `ReliabilityRing`, `TierSelector`, `DivisionLadder`, `StatFieldRow`, `WeekdayPicker`) | `lib/views/profile/profile_field_views.dart` | planned | The profile widget library; `AvatarView` is used app-wide. |
| `Views/Profile/ProfileStrengthSection.swift` (+ `ProfileStrengthRing`) | `lib/views/profile/profile_strength_section.dart` | planned | Model **done** (`lib/models/profile_strength.dart`). Disappears at 100%. |
| `Views/Profile/SeasonStatsSection.swift` | `lib/views/profile/season_stats_section.dart` | planned | Shows an error row rather than vanishing. |
| `Views/Profile/CareerStatsView.swift` (+ `Totals`) | `lib/views/profile/career_stats_view.dart` | planned | Season by season, with career sums. |
| `Views/Profile/PlayerProfileView.swift` | `lib/views/profile/player_profile_view.dart` | planned | Same figures, no contact details — `TeammateProfile` has nowhere to put them. |
| `Views/Profile/APIServerSettingsView.swift` | `lib/views/profile/api_server_settings_view.dart` | planned | `AppConfig` and `FishersRing` are **done**; the panel that drives them is not. See [Rings](#rings). |
| `Views/Profile/DeleteAccountView.swift` | `lib/views/profile/delete_account_view.dart` | planned | Two-step, App Store 5.1.1(v). |

### Shop and tournaments

| iOS | Android | Status | Notes |
|---|---|---|---|
| `Views/Shop/ShopView.swift` (`ShopView`, `CheckoutView`) | `lib/views/shop/shop_view.dart` | planned | Club picker, cart, checkout. |
| `Views/Tournament/TournamentView.swift` (+ `SetUpSheet`, `AddEntrantsSheet`, `ResultSheet`) | `lib/views/tournament/tournament_view.dart` | planned | Schedule / Table / Entrants. |
| `Views/Tournament/EntryInvitationsSection.swift` | `lib/views/tournament/entry_invitations_section.dart` | planned | Tournaments another club has asked this one into. The models and the API calls are **done**; only the section is missing. |

---

## 2. Stores

`ios/Fishers/ViewModels/` (9 files, 11 classes) → `lib/stores/`. **State
management: `provider`.** It is the closest thing Flutter has to
`ObservableObject` + `@EnvironmentObject`, which is what every one of these is
built on, so each store becomes a `ChangeNotifier` with the same published
fields and the same methods, and the port stays a translation rather than a
redesign.

| iOS | Android | Status | Published state |
|---|---|---|---|
| `SessionStore.swift` | `lib/stores/session_store.dart` | **done** | `user`, `isAuthenticated`, `isLoading`, `errorMessage`. `justStarted` and `needsQuickStart` wait on the quick start being ported |
| `ClubContextStore.swift` | `lib/stores/club_context_store.dart` | planned | `clubs`, `activeClubId` (persisted), `roleInfo`, `isLoading` |
| `CartStore.swift` | `lib/stores/cart_store.dart` | planned | `lines`, `clubId`; `totalCents` derived |
| `ChatStore.swift` | `lib/stores/chat_store.dart` | **done**, minus the assistant | `conversations`, `messages`, `isLoading`, `isSending`, `errorMessage`. `proposals`, `isThinking` and `agentSummary` go with the assistant work |
| `MotmStore.swift` | `lib/stores/motm_store.dart` | **done** | One per card, not one for the app: a thread can carry several finished fixtures' votes at once and they are independent. `view`, `isLoading`, `isVoting`, `errorMessage` |
| `ClubAdminStore.swift` | `lib/stores/club_admin_store.dart` | planned | `members`, `settings`, `fees`, `isLoading`, `isSaving`, `isChasing`, `errorMessage`, `invite` |
| `SelectionStore.swift` | `lib/stores/selection_store.dart` | planned | `board`, `proposal`, `selected`, `reserves`, `isLoading`, `isThinking`, `isPublishing`, `errorMessage` |
| `CalendarViewModel.swift` | `lib/stores/calendar_store.dart` | planned | `month`, `days`, `events`, `fixtures`, `bulkBusy`, `isLoading`, `errorMessage`, `cricketSeasonOnly` |
| `TournamentStore.swift` → `TournamentStore` | `lib/stores/tournament_store.dart` | planned | `entrants`, `schedule`, `standings`, `isLoading`, `isGenerating`, `errorMessage` |
| `TournamentStore.swift` → `TicketStore` | `lib/stores/ticket_store.dart` | planned | `booking`, `isWorking`, `errorMessage` |
| `ProfileFormModel.swift` | `lib/stores/profile_form_model.dart` | planned | `@Observable`, not `ObservableObject` — a `ChangeNotifier` here too, since Flutter draws no such distinction |
| `Views/Onboarding/GettingStarted.swift` → `GettingStartedStore` | `lib/stores/getting_started_store.dart` | planned | Declared inside a view on iOS; moved to `stores/` here |

---

## 3. Models

All **done**. One Dart file per Swift file, every `CodingKeys` string copied
across. Tested by decode → encode → decode against real captured JSON, plus a
check that no wire key is silently dropped.

| iOS | Android | Types |
|---|---|---|
| `Models/Models.swift` | `lib/models/models.dart` | `PublicUser`, `AuthTokens`, `SocialSignedIn`, `Club`, `Team`, `Venue`, `EventSubtype`, `Event`, `AvailabilityStatus`, `Availability`, `RsvpStatus`, `AttendeeSummary`, `Product`, `Order` |
| `Models/Fixtures.swift` | `lib/models/fixtures.dart` | `FixtureAnswer`, `MyFixture`, `FixtureList` |
| `Models/Clubs.swift` | `lib/models/clubs.dart` | `ClubMembershipRow`, `ClubListFilters`, `ClubListRole`, `ClubListSort`, `RoleChoice`, `ClubPageSettings`, `TeamMemberRow`, `SharedPlayerCard`, `ClubSetupStep` |
| `Models/ClubAdmin.swift` | `lib/models/club_admin.dart` | `ClubMemberDetail`, `ClubInvite`, `AppNotification`, `ApiPage`, `NotificationFeed`, `ClubSettings`, `SelectionAutonomy` |
| `Models/ClubIdentity.swift` | `lib/models/club_identity.dart` | `ClubIdentity`, `ClubQrCode`, `MatchOfficialRow`, `ScorerHandover`, `BallCommentary`, `SquadPlayer`, `SideSquad`, `MatchSquads` |
| `Models/RBAC.swift` | `lib/models/rbac.dart` | `ClubRole` (6), `ClubRoleInfo` |
| `Models/PlayerProfile.swift` | `lib/models/player_profile.dart` | `Sport`, `SkillTier`, `Division`, `AgeGroup`, `TransportMode`, `Weekday`, `SportProfile`, `PlayerLocation`, `ReliabilityBand`, `ReliabilityScore`, `ProfileUpdate` |
| `Models/SportStats.swift` | `lib/models/sport_stats.dart` | `StatField`, `StatFieldKind`, `SportStats` |
| `Models/ProfileStrength.swift` | `lib/models/profile_strength.dart` | `ProfileStrength`, `ProfileStrengthItem` |
| `Models/TeammateProfile.swift` | `lib/models/teammate_profile.dart` | `TeammateProfile` |
| `Models/Selection.swift` | `lib/models/selection.dart` | `SelectionState`, `SelectionCandidate`, `RankedCandidate`, `PositionQuota`, `SquadRequirements`, `SelectionBoard`, `SquadProposal`, `OutstandingFee`, `OutstandingFees` |
| `Models/SeasonStats.swift` | `lib/models/season_stats.dart` | `PlayCricketLinks`, `PlayCricketPlayerLink`, `PlayerSeasonStats`, `UserAchievement`, `MeStatsResponse`, `PlayCricketClubSite`, `ClubSeasonStats`, `ClubSeasonBoard` |
| `Models/Tournament.swift` | `lib/models/tournament.dart` | `TournamentFormat`, `FixtureBlock` (with its entry, squad and playing rules), `EntryStatus`, `TournamentEntrant`, `InviteEntrantResult`, `EntryInvitation`, `ScheduleRow`, `Standing`, `EventTicket`, `TicketSummary`, `TicketBooking`, `CricketFixtureRow` |
| `Models/Chat.swift` | `lib/models/chat.dart` | `ConversationSummary`, `Conversation`, `ChatMessage`, `ProposalKind`, `AgentProposal`, `ProposalPayload`, `AgentRun`, `AgentAnalysis` |
| `Models/ManOfTheMatch.swift` | `lib/models/motm.dart` | `MotmPoll`, `MotmCandidate`, `MotmPollView` — the poll's own fields arrive flattened in beside the ballot, so `fromJson` reads both out of one object |
| `Models/Onboarding.swift` | `lib/models/onboarding.dart` | `RoleIntent`, `VerificationStatus`, `VerificationChannelStatus`, `VerificationChannel`, `VerificationSent`, `PendingInvite`, `ShareLinkToken` |
| `Cricket/CricketTypes.swift` | `lib/models/cricket_types.dart` | The nine enums the brief names, plus `MatchOfficials`, `MatchConditions`, `MatchPlayer`, `ShotRecord`, `cricketRegion`, `ScoringEventKind` (20 cases), `ScoringEvent`, `BatterStats`, `BowlerStats`, `FallOfWicket`, `DeliveryRecord`, `InningsState`, `MatchState`, `DlsPar`, `CricketMatchDto`, `ScoreboardShareResponse` |
| — (new) | `lib/models/json.dart` | The decoding layer Swift gets free from `Codable`: the multi-format ISO-8601 reader, the encoder, `JsonValue`, and the id and enum helpers |
| — (new) | `lib/models/fishers_models.dart` | Barrel |

### Not ported with the types

`MatchState.history` (the local undo stack, never serialised) and the mutating
helpers only the engine calls — `swapStrike`, `ensureBowler`, `batterIndex`,
`bowlerIndex` — land with `lib/cricket/cricket_engine.dart`. Everything
read-only that screens use is already here.

---

## 4. Services

| iOS | Android | Status | Notes |
|---|---|---|---|
| `Services/NetworkService.swift` | `lib/services/network_service.dart` | **done** | Base URL + `/api/v1`, bearer token, single-flight refresh-then-retry-once, multipart upload, `ApiException` with the API's own sentence |
| `Services/FishersAPI.swift` | `lib/services/fishers_api.dart` | **done** | 122 of 126 — see [Endpoints](#6-endpoints) |
| `Services/LiveStream.swift` | `lib/services/live_stream.dart` | **done** | SSE parser and the five events; one connection, shared; reconnect with backoff and jitter |
| `Services/KeychainStore.swift` | `lib/services/keychain_store.dart` | **done** | `flutter_secure_storage` with `EncryptedSharedPreferences` |
| `Services/SocialAuth.swift` | `lib/services/social_auth.dart` | partial | `SocialAuthConfig` is **done**; the Google sign-in call lands with the auth layer (`google_sign_in`). Apple is a **gap** |
| `Services/ProfileReminder.swift` | `lib/services/profile_reminder.dart` | planned | `flutter_local_notifications`, plus the Android 13+ `POST_NOTIFICATIONS` runtime permission iOS does not need |
| `Config/AppConfig.swift` | `lib/config/app_config.dart` | **done** | Four-source resolution, `FishersRing` |
| `Theme/FishersTheme.swift` | `lib/theme/fishers_theme.dart` | **done** | Same hex values; `FishersColors` theme extension for what `ColorScheme` has no slot for |
| — (new) | `lib/services/uuid.dart` | **done** | v4 ids, for the multipart boundary and the device-minted match id |

---

## 5. Cricket engine and offline scoring

Not started. This is the hardest layer and the brief says to plan for it first.

| iOS | Android | Status | Notes |
|---|---|---|---|
| `Cricket/CricketTypes.swift` | `lib/models/cricket_types.dart` | **done** | Types only |
| `Cricket/CricketEngine.swift` | `lib/cricket/cricket_engine.dart` | planned | `replay` folds an ordered log; `apply` applies one event with sequence checking. `ios/FishersTests/CricketEngineTests.swift` gets translated to Dart **first**, as a red suite |
| `Cricket/CricketMatchStore.swift` | `lib/cricket/cricket_match_store.dart` | planned | Append event → engine apply → autosave. Never waits on the network. The match id is minted on the device before the API is involved |
| `Cricket/CricketSyncService.swift` | `lib/cricket/cricket_sync_service.dart` | planned | Background sweep on `connectivity_plus`; active match first; one writer at a time |
| `Cricket/LocalCricketModels.swift` (SwiftData) | `lib/cricket/local_cricket_models.dart` | planned | `drift` — typed SQLite with migrations |
| `Cricket/CricketDLS.swift` | `lib/cricket/cricket_dls.dart` | planned | Mirrors `backend/domain/src/cricket/dls.rs` |
| `Cricket/CricketCommentary.swift` | `lib/cricket/cricket_commentary.dart` | planned | Lines written from the log, not from typed text |

---

## 6. Endpoints

117 functions in `lib/services/fishers_api.dart`, in the order they appear in
`FishersAPI.swift`. Each is checked for the exact method, path, query string
and body it sends.

| Function | Request |
|---|---|
| `myClubRole` | `GET /clubs/{id}/my-role` |
| `deleteAccount` | `POST /me/delete` |
| `inviteToEvent` | `POST /events/{id}/invite` |
| `signup` | `POST /auth/signup` |
| `login` | `POST /auth/login` |
| `googleAuthConfig` | `GET /auth/google` |
| `signInWithGoogle` | `POST /auth/google` |
| `me` | `GET /me` |
| `setRoleIntent` | `PATCH /me` |
| `verificationStatus` | `GET /me/verification` |
| `sendVerificationCode` | `POST /me/verification/{channel}` |
| `confirmVerification` | `POST /me/verification/{channel}/confirm` |
| `myInvites` | `GET /invites/mine` |
| `profileShareLink` | `POST /me/share-link` |
| `updateProfile` | `PATCH /me` |
| `fixtureBlocks` | `GET /clubs/{id}/fixture-blocks` |
| `createTournament` | `POST /fixture-blocks` |
| `entrants` | `GET /fixture-blocks/{id}/entrants` |
| `addEntrants` | `POST /fixture-blocks/{id}/entrants` |
| `inviteEntrant` | `POST /fixture-blocks/{id}/invite` |
| — (no store yet) | `GET /fixture-blocks/{id}` — one tournament and its rules |
| `tournamentInvitations` | `GET /clubs/{id}/tournament-invites` |
| `respondToEntry` | `POST /entrants/{id}/respond` |
| `tournamentSchedule` | `GET /fixture-blocks/{id}/schedule` |
| `standings` | `GET /fixture-blocks/{id}/standings` |
| `generateSlots` | `POST /fixture-blocks/{id}/slots` |
| `generateSchedule` | `POST /fixture-blocks/{id}/schedule` |
| `generateKnockout` | `POST /fixture-blocks/{id}/knockout` |
| `recordResult` | `POST /events/{id}/result` |
| `tickets` | `GET /events/{id}/tickets` |
| `bookTicket` | `POST /events/{id}/tickets` |
| `payTicket` | `POST /tickets/{id}/pay` |
| `cancelTicket` | `POST /tickets/{id}/cancel` |
| `selectionBoard` | `GET /events/{id}/selection` |
| `suggestSquad` | `POST /events/{id}/selection/suggest` |
| `agentSquad` | `POST /events/{id}/selection/agent` |
| `setSquad` | `POST /events/{id}/selection` |
| `respondToSelection` | `POST /events/{id}/selection/respond` |
| `updateFixtureStatus` | `POST /events/{id}/status` |
| `outstandingFees` | `GET /clubs/{id}/fees/outstanding` |
| `chaseFees` | `POST /clubs/{id}/fees/chase` |
| `conversations` | `GET /conversations` |
| `createConversation` | `POST /conversations` |
| `messages` | `GET /conversations/{id}/messages?limit=` |
| `postMessage` | `POST /conversations/{id}/messages` |
| `markRead` | `POST /conversations/{id}/read` |
| `proposals` | `GET /conversations/{id}/proposals` |
| `analyseConversation` | `POST /conversations/{id}/agent/analyse` |
| `applyProposal` | `POST /agent/proposals/{id}/apply` |
| `dismissProposal` | `POST /agent/proposals/{id}/dismiss` |
| `clubQrCode` | `GET /clubs/{id}/qr` |
| `teamQrCode` | `GET /teams/{id}/qr` |
| `rotateClubQrCode` | `POST /clubs/{id}/qr` |
| `lookupOpponent` | `POST /opponents/lookup` |
| `searchOpponents` | `GET /opponents/search?q=` |
| `matchOfficials` | `GET /cricket/matches/{id}/officials` |
| `appointOfficial` | `POST /cricket/matches/{id}/officials` |
| `removeOfficial` | `DELETE /cricket/matches/{id}/officials/{userId}` |
| `handOverScoring` | `POST /cricket/matches/{id}/handover` |
| `scorerTrail` | `GET /cricket/matches/{id}/scorer-trail` |
| `commentary` | `POST /cricket/matches/{id}/commentary` |
| `squads` | `GET /cricket/matches/{id}/squad` |
| `match` | `GET /cricket/matches/{id}` |
| `proposeTerms` | `POST /cricket/matches/{id}/propose` |
| `abandonMatch` | `POST /cricket/matches/{id}/abandon` |
| `deleteMatch` | `DELETE /cricket/matches/{id}` |
| `agreeTerms` | `POST /cricket/matches/{id}/agree` |
| `notifications` | `GET /notifications?page&per_page[&kind][&unread][&q]` |
| `teammate` | `GET /users/{id}` |
| `playerSeasons` | `GET /users/{id}/stats` |
| `playerAchievements` | `GET /users/{id}/achievements` |
| `markNotificationRead` | `POST /notifications/read` |
| `submitXi` | `POST /cricket/matches/{id}/xi` |
| `clubMembers` | `GET /clubs/{id}/members` |
| `addClubMember` | `POST /clubs/{id}/members` |
| `createClubInvite` | `POST /invites` |
| `acceptInvite` | `POST /invites/{token}/accept` |
| `setMemberRole` | `PATCH /clubs/{id}/members/{userId}` |
| `myClubs` | `GET /me/clubs?sort&page&per_page[&q][&role][&sport][&public_page]` |
| `venues` | `GET /clubs/{id}/venues` |
| `createVenue` | `POST /clubs/{id}/venues` |
| `clubPage` | `GET /clubs/{id}/page` |
| `updateClubPage` | `PATCH /clubs/{id}/page` |
| `teamMembers` | `GET /teams/{id}/members` |
| `sharedPlayerCard` | `GET /players/card/{token}` |
| `invite` | `POST /invites` |
| `removeClubMember` | `DELETE /clubs/{id}/members/{userId}` |
| `clubSettings` | `GET /clubs/{id}/settings` |
| `updateClubSettings` | `PATCH /clubs/{id}/settings` |
| `clubs` | `GET /clubs` |
| `createClub` | `POST /clubs` |
| `createTeam` | `POST /clubs/{id}/teams` |
| `teams` | `GET /clubs/{id}/teams` |
| `events` | `GET /events?page&per_page&` (unwraps the page) |
| `eventPage` | `GET /events?page&per_page&[club_id&][cricket_season&]` |
| `createEvent` | `POST /events` |
| `event` | `GET /events/{id}` |
| `myFixtures` | `GET /events/mine?from&to` |
| `setAvailabilityForDates` | `POST /availability/bulk` |
| `markTicketPaid` | `POST /tickets/{id}/mark-paid` |
| `withdrawEntrant` | `POST /entrants/{id}/withdraw` |
| `promoteReserves` | `POST /events/{id}/selection/promote` |
| `rsvp` | `POST /events/{id}/rsvp` |
| `attendees` | `GET /events/{id}/attendees` |
| `availability` | `GET /availability?from&to` |
| `setAvailability` | `POST /availability` |
| `products` | `GET /clubs/{id}/products` |
| `placeOrder` | `POST /orders` |
| `paymentIntent` | `POST /payments/intent` |
| `createCricketMatch` | `POST /events/{id}/cricket-match` |
| `cricketMatchForEvent` | `GET /events/{id}/cricket-match` |
| `cricketMatch` | `GET /cricket/matches/{id}` |
| `cricketFixtures` | `GET /cricket/fixtures?page&per_page&order[&club_id][&state][&q]` |
| `claimScorer` | `POST /cricket/matches/{id}/claim-scorer` |
| `postCricketEvents` | `POST /cricket/matches/{id}/events` |
| `cricketScorecard` | `GET /cricket/matches/{id}/scorecard` |
| `shareScoreboard` | `POST /cricket/matches/{id}/share` |
| `uploadAvatar` | `POST /me/avatar` (multipart) |
| `mySeasonStats` | `GET /me/stats[?season]` |
| `clubSeasonBoard` | `GET /clubs/{id}/stats?season` |
| `syncClubStats` | `POST /clubs/{id}/stats/sync` |

**Not ported, deliberately:** `appleAuthConfig` (`GET /auth/apple`) and
`signInWithApple` (`POST /auth/apple`).

**Naming:** Swift overloads `setAvailability`; Dart cannot, so the bulk one is
`setAvailabilityForDates`. `myFixtures` sends its timestamps with a `Z` rather
than an offset, because a `+` in a query string reads as a space.

---

## 7. Live stream

`GET /api/v1/stream`, signed like any other request. Events say what changed,
never the content, so every listener re-fetches through the normal endpoints,
which do their own access checks.

| Event | Dart | Means |
|---|---|---|
| `message` | `LiveMessage(conversationId, id)` | A new message in one of your threads |
| `notification` | `LiveNotification()` | One arrived, or was read on another device |
| `conversations` | `LiveConversations()` | You joined or left a thread |
| `match` | `LiveMatch(id, seq)` | A ball, the toss, a handover, the result |
| `resync` | `LiveResync()` | Events may have been missed: re-fetch |
| `ready` | `LiveResync()` | Connected — treated as a resync |

Anything else is ignored. Reconnection is itself a resync.

---

## 8. Deliberate divergences

| What | iOS | Android | Why |
|---|---|---|---|
| **Push registration** | `registerDevice` / `unregisterDevice`, called after sign-in; APNs delivers man-of-the-match and chat notifications | **Half shipped.** The server sends to Android over FCM; the app does not yet register a token, so nothing arrives | The server half is built and tested (`backend/notifications/src/fcm.rs`). The client half needs a Firebase project and its `google-services.json`, which is not something the repo can carry — until it does, every notification is still stored server-side, so the bell fills up and only the buzz is missing |
| **Sign in with Apple** | `AuthView` renders the button, `SocialAuth` runs the native flow | **Not shipped.** `/auth/apple` is never called, the button never rendered | Settled before this work started. On Android it is a web redirect, not a native flow, and that cost is not worth paying before the app is in people's hands. The auth screen still drives its buttons off the server's config, so a third provider slots in without rework |
| **Back** | No equivalent obligation | The system back gesture and button work on every screen and inside every sheet | Android |
| **Sheets** | `.sheet` | Material bottom sheet or full-screen dialog, by the weight of the iOS presentation | Android |
| **Tabs** | `TabView` | Bottom `NavigationBar`, same five destinations, same order | Android |
| **Share** | `UIActivityViewController` | The Android share intent | Android |
| **Permissions** | Asked on iOS's timing | Asked at point of use — camera for the QR scanner, `POST_NOTIFICATIONS` on API 33+ | Android |
| **Push** | Registers for none | None added. In-app notifications come from the API and the SSE stream | Parity |
| **Local notifications** | `UNUserNotificationCenter` in `ProfileReminder.swift` | `flutter_local_notifications`, plus the API 33+ runtime permission | Android |
| **Debug fallback host** | Simulator → `127.0.0.1:7312` | Emulator → `10.0.2.2:$API_PORT` (7312 by default) | An emulator does not share this Mac's network stack; `127.0.0.1` inside it is the emulator itself. The port follows `.env` via `--dart-define=API_PORT=…`, because `.env` moves it and iOS's hard-coded 7312 is wrong the moment it does |
| **Loopback rejection** | Keyed off `targetEnvironment(simulator)` | Keyed off `kReleaseMode` | Dart has no simulator flag, and "is this a release build" is the same question in every case that matters |
| **Touch target** | 44 pt | 48 dp (`FishersTheme.minTap`; the iOS value stays as `minTapIOS`) | Material's minimum is larger |
| **Type** | SF Rounded / New York / SF Text | Weight and role carry the distinction on Material's type scale | Android's system font has no equivalent trio. Sizes stay at Material's defaults so the system font-size setting scales them |
| **JSON codecs** | `Codable` + `CodingKeys` | Hand-written `fromJson`/`toJson`, not `json_serializable` | The brief's architecture table names `json_serializable`. **This is a deviation and wants a reviewer's opinion.** Twelve of the Swift models have hand-rolled `init(from:)` with defaults, lossy dates and non-keyed decoding (`ClubQrCode` reads its identity from the same object; `AppNotification` flattens mixed-type values to strings; `NotificationFeed` defaults five fields so an older server still works). Expressing those through generated code needs a custom converter each, which is more machinery than the codec it replaces — and generated files are not where a reviewer looks for a wire name. Hand-written keeps every `CodingKeys` string visible on one line and drops `build_runner`, `json_annotation` and `json_serializable` from the dependency set. The tests enforce what the generator would have: a wire key typed wrong fails a round trip |
| **UUIDs** | Swift `UUID`, encoded upper-case | Lower-case strings | Postgres is case-insensitive and lower case is what it sends; keeping the received string avoids a dependency and makes `MatchState.playerNames` lookups work without a second normalisation |

---

## 9. Where `ios/` and the brief disagree

The brief says the Swift wins. These are the places it matters.

### Rings

The brief names four — `int`, `test`, `acc`, `www.fishers.cloud` — and
`devops/ring-promoter/fishers-apps.yaml` deploys all four.
`Views/Profile/APIServerSettingsView.swift` offers only **two** as quick picks
(`int` and `www`), alongside a hard-coded LAN address (`192.168.1.177:7312`)
and Simulator loopback. `lib/config/app_config.dart` carries all four in
`FishersRing`, because the brief is explicit that testers must be able to reach
int, test and acc; the settings panel will offer four where iOS offers two.
Flagged rather than assumed.

### `GET /cricket/matches/{id}/scorecard` answers a superset

The reply is a `MatchState` **plus** a `dls` block. iOS decodes it as
`MatchState`, which has no key for `dls`, so the DLS par reaches both apps
through `CricketMatchDTO.dls` instead. Faithfully ignored here too, and noted
in the round-trip test.

### `MatchState.abandoned` is read but never written

The property sits outside iOS's `CodingKeys`, so Swift's synthesised encoder
does not write it. Neither does this one. A round trip is therefore
byte-compatible with what iOS posts, and `abandoned` only ever arrives.

### `SocialAuthConfig` has no Android client id

`GET /auth/google` answers `{enabled, client_id, ios_client_id}`. There is no
`android_client_id`. `SocialAuthConfig` reads one if it ever appears and falls
back to `client_id`, which is the server client id `google_sign_in` wants as
its `serverClientId` — so **no backend change is needed**, and none was made.
Worth confirming when the Google button is wired up: if the ring's
`GOOGLE_CLIENT_ID` is an iOS OAuth client rather than a web one, an Android
build will not be able to verify its token, and that is a configuration change
in Vault, not a code change.

### Nothing else needs a backend change

Every endpoint the foundation calls exists and answers the shape the models
expect. `backend/`, `web/`, `devops/` and `ios/` are untouched on this branch.

---

## 10. Tests

| Layer | Where | What |
|---|---|---|
| Theme | `test/theme/fishers_theme_test.dart` | Hex values against the Swift, the two contrast ratios its comments claim, dark not flattened to grey, system text scaling honoured |
| Config | `test/config/app_config_test.dart` | The four-source resolution order, what counts as a host, `/api/v1` URL building, the four rings |
| Models | `test/models/models_round_trip_test.dart` | Every model against real captured JSON: decode → encode → decode, field-by-field fidelity, and no dropped wire key |
| Scoring log | `test/models/scoring_events_test.dart` | All 20 `ScoringEventKind` cases, the nine enums, `cricketRegion`, `MatchConditions` |
| Model logic | `test/models/model_logic_test.dart` | Notification sentences, profile strength, reliability, RBAC, filters, slugs, fixture clashes, stat catalogs |
| Network | `test/services/network_service_test.dart` | Request shape, tokens, refresh-then-retry-once, single-flight under six concurrent 401s, errors, multipart |
| Live stream | `test/services/live_stream_test.dart` | The SSE parser line by line, backoff and jitter, one shared connection, 401 → renew |
| API surface | `test/services/fishers_api_test.dart` | Method, path, query and body for the endpoints, and that nothing reaches `/auth/apple` |
| App | `test/app/fishers_app_test.dart` | The root renders in both appearances |

### Fixtures

`test/fixtures/api/` holds **real captures**, not invented JSON. The stack was
brought up with `scripts/start.sh --api-only` and seeded with
`scripts/seed-demo.sh`, and the responses were recorded off it;
`MANIFEST.json` names the endpoint each one came from, and a test asserts every
entry names a real method and path.

The scoring log needed more than the seed had written: the seeded world's
matches supplied 13 of the 20 event kinds, and the other seven were posted to a
live match through `POST /cricket/matches/{id}/events`. The API accepted the
log, moved the match to `complete`, and the rows were read back out of
`cricket_scoring_events`. A wrong key would have been a 4xx, not a fixture.

### Not verifiable on this machine

There is no Android SDK here. `flutter build apk`, `flutter build aab` and
`flutter test integration_test` cannot run, so nothing below the Dart layer is
proved: the Gradle build, `minSdk 26`, the manifest, `flutter_secure_storage`
against the real Keystore, and any behaviour that needs a device or emulator.
`flutter analyze` and `flutter test` are what stands behind this branch.
