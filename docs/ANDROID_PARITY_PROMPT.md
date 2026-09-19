# Build the Fishers Android app in Flutter — prompt

Hand the whole of the next section to a coding agent working in this repo.
It is a brief, not a tutorial: it says what "done" means, where the truth
lives, and which decisions are already made. Everything it asserts about the
iOS app is checkable in `ios/`, and where the two disagree, `ios/` wins.

---

## Mission

Build an Android app for Fishers in Flutter with **feature and behaviour
parity to the existing iPhone app**, in this repository, against the existing
Fishers API. No new product, no redesign, no feature invention: a member who
uses the iPhone app must be able to pick up an Android phone and find the same
app — same screens, same flows, same rules, same states, same vocabulary.

## Ground truth — read this before planning

The specification is the iOS source, not this document. This document is a map;
`ios/Fishers/` is the territory. **Read it before you write anything.**

| Where | What it settles | Size |
|---|---|---|
| `ios/Fishers/Views/` (50 files) | Every screen, its states, its copy | ~14,500 lines |
| `ios/Fishers/Models/` (15) | Wire shapes, `CodingKeys`, enums | ~3,000 |
| `ios/Fishers/Services/` (6) | API client, SSE, keychain, social auth | ~2,000 |
| `ios/Fishers/ViewModels/` (9) | Stores: session, club context, chat, selection, cart, tournament, club admin, calendar, profile form | ~1,150 |
| `ios/Fishers/Cricket/` (7) | Offline scoring engine, sync, DLS, commentary | ~3,200 |
| `ios/Fishers/Theme/FishersTheme.swift` | Colour ramp, type, dark mode | ~220 |
| `ios/Fishers/Config/AppConfig.swift` | API/web base URL resolution | ~160 |
| `ios/FishersUITests/` | **Expected behaviour, executably** | 13 files |
| `docs/PLATFORM.md` | Domain spine, platform events, RBAC | — |
| `docs/CRICKET_SCORING.md` | Scoring rules | — |
| `docs/RBAC.md` | Permission matrix | — |
| `backend/` | The API that both clients call | — |

`ios/FishersUITests/` is the most valuable file set you have. `QuickStartTour`,
`OnboardingTour`, `FixturesTour`, `ClubsTour`, `ScoreTour`, `LiveTour` and
`AreaTour` walk the app the way a user does and assert what should be on
screen. **Treat them as the acceptance criteria for the Android app.** Mirror
their accessibility identifiers in Flutter (`Semantics(identifier:)` / widget
keys) so the equivalent `integration_test` suite can assert the same things.

## What parity means here — the success predicate

The app is done when **all** of these hold. They are checkable; do not declare
done on a subset.

1. **Screens.** Every screen in `ios/Fishers/Views/` has an Android counterpart
   reachable by the same navigation path, with the same information on it and
   the same controls, in the same order of visual priority. The single agreed
   exception is the Sign in with Apple button, which v1 does not ship.
2. **Tabs.** Five, in this order, matching `MainTabView.swift`: Home, Fixtures,
   Chats, Clubs, Profile — plus the live-match alert overlay (`LiveAlerts`)
   that floats above all of them.
3. **Gating.** `RootView` logic exactly: not authenticated → auth; authenticated
   but `needsQuickStart` → quick start; otherwise → tabs. Same 250ms crossfade
   between states.
4. **Wire compatibility.** Every request is byte-compatible with what iOS sends
   and every response decodes from what the API already returns. You change
   **zero** backend files. If a response seems wrong, it is your decoder.
5. **Roles.** The six `ClubRole` values and the permission matrix gate the same
   controls on the same screens. A member must not see a secretary's buttons.
6. **Offline scoring.** A match can be started, scored ball-by-ball and
   completed with the device in airplane mode, and it syncs when signal
   returns — see "Offline scoring" below. This is non-negotiable and is the
   hardest part; plan for it first, not last.
7. **Live updates.** The SSE stream drives the same refreshes as iOS.
8. **Look.** The Fishers palette, light and dark, at the same contrast ratios,
   with system text scaling respected throughout.
9. **Tests.** `flutter test` and `flutter test integration_test` pass, and the
   integration suite covers the flows the Swift UI tours cover.
10. **Builds.** A release APK/AAB builds from CI and installs on Android 8.0
    (API 26) and above.

## Explicit non-goals

- Do **not** modify `backend/`, `web/`, `devops/` or `ios/`. If Android needs a
  new endpoint, stop and say so rather than adding one.
- Do **not** ship the Flutter app's iOS target. The native SwiftUI app stays the
  iPhone product; Flutter is the Android product. Keep the generated `ios/`
  folder inside the Flutter project unshipped and unsigned.
- Do **not** redesign. Where an iOS idiom has no Android equivalent, adapt it
  (see "Where to diverge") — never improve it on your own initiative.
- Do **not** add analytics, crash reporting, ads or third-party SDKs beyond what
  auth and payments require.

## Where the project lives

Create the Flutter app at **`flutter/`** at the repo root, beside `ios/`, `web/`
and `backend/`. Name the package `fishers`. The iPhone app's bundle id is
`com.fishers.app`, so use **`com.fishers.app`** as the Android application id —
the two stores are separate namespaces and sharing the identifier keeps the
product one product. Confirm this against the Play Console before the first
upload, because an application id cannot be changed after publishing.

Do not put it at `android/`: a Flutter project generates its own `android/` and
`ios/` subfolders, and a top-level `android/` would collide confusingly with
the repo's existing `ios/`.

## Architecture — decisions already made

Match the iOS structure so the two apps can be read side by side. A reviewer
holding `ios/Fishers/Views/Cricket/ScoreHubView.swift` should find
`flutter/lib/views/cricket/score_hub_view.dart` without searching.

```
flutter/lib/
  app/          entry point, root widget, providers      ← App/FishersApp.swift
  config/       API/web base URL resolution              ← Config/AppConfig.swift
  theme/        colour ramp, typography, dark mode       ← Theme/FishersTheme.swift
  models/       wire types, enums, JSON codecs           ← Models/
  services/     api client, SSE, secure storage, auth    ← Services/
  stores/       state holders                            ← ViewModels/
  cricket/      engine, local store, sync                ← Cricket/
  views/        screens, mirroring the iOS folders       ← Views/
```

| Concern | iOS | Use on Android |
|---|---|---|
| State | `ObservableObject` + `@EnvironmentObject` | `provider` or `riverpod` — pick one, use it everywhere |
| Local DB | SwiftData (`LocalCricketMatch`, `LocalScoringEvent`) | `drift` (SQLite, typed, migrations) |
| Secrets | Keychain (`KeychainStore.swift`) | `flutter_secure_storage` |
| Prefs | `UserDefaults` | `shared_preferences` |
| Live | SSE over `URLSession` (`LiveStream.swift`) | SSE over `http` — reconnect with backoff |
| Google | `GoogleSignIn` SDK | `google_sign_in` |
| Apple | `AuthenticationServices` | **Out of scope for v1** — see below |
| Network state | `NWPathMonitor` | `connectivity_plus` |
| JSON | `Codable` + `CodingKeys` | `json_serializable` — mirror every `CodingKeys` exactly |

Prefer the smallest dependency set that does the job. Every package you add is
one someone has to keep alive.

## Feature inventory

Each line is a screen or behaviour that must exist. The Swift file is the spec.

**Auth & onboarding** — `Views/Auth/`, `Views/Onboarding/`
Email/password sign-up and sign-in; Google sign-in (config fetched from
`/auth/google`, and the button hides when the server says the provider is off);
contact verification by email/SMS code; quick start (sport + squad number, both
skippable); role chooser; getting-started guide with live progress; pending club
invites; share-profile screen.

**Sign in with Apple is out of scope for v1** — see "Where to diverge". Build
the auth screen so a third provider slots in without rework: the iOS screen
already drives its buttons off the server's config, so keep that shape and let
the Apple button simply never be configured.

**Home** — `Views/Home/`
Club-context feed, overview tiles, live fixture row that appears when a match in
your club is in progress, notifications list with read state, getting-started
guide that reloads when the club context arrives.

**Fixtures & calendar** — `Views/Fixtures/`, `Views/Calendar/`, `Views/Events/`
Fixture list with status; event detail; availability calendar with the three
states (yes / maybe / no — sage, gold, red, and never colour alone); bulk
availability; event tickets — book, pay, cancel.

**Selection** — `Views/Selection/`
Selection board, AI squad suggestion, agent squad, set squad, respond to
selection, submit XI.

**Cricket** — `Views/Cricket/` and `Cricket/`
Score hub with its state filters; the ball-by-ball live scorer; the scoring
flow; full scorecard; wagon wheel; shot icons; match moments; opposition picker;
terms proposal and agreement; officials appointment; scorer handover with trail;
commentary; DLS. Enums to reproduce exactly: `CricketMatchStatus` (9 cases),
`DismissalKind` (9), `ExtraKind` (5), `ShotKind` (13), `BallType` (5),
`GroundType` (3), `MatchSide`, `TossDecision`, `SyncStatus`.

**Clubs** — `Views/Clubs/`
Clubs and teams list; club stats; club admin (roster, roles, invites, venues,
settings, outstanding fees and chasing); club QR code with rotation; club page
settings.

**Chat** — `Views/Chat/`
Thread list with unread counts; thread view with send; the AI assistant's
proposals — analyse, apply, dismiss. The assistant proposes; a human applies.

**Profile** — `Views/Profile/`
Profile view and hero; edit with all field types; profile strength; season
stats; career stats; teammate profiles; achievements; API server settings panel;
delete account.

**Shop & tournaments** — `Views/Shop/`, `Views/Tournament/`
Cart and orders; payment intent; tournament entrants, slot and schedule
generation, knockout, standings, results.

## Cross-cutting behaviour

### API client
Mirror `Services/NetworkService.swift`: base URL from config, `/api/v1` prefix,
bearer access token, **automatic refresh on 401 then one retry** (via
`POST /api/v1/auth/refresh` with the refresh token — never a silent re-login),
multipart upload for avatars, and the shared ISO8601 date decoding —
`decodeISO8601Date` handles more than one format, so copy its logic rather than
assuming. Access and refresh tokens live in secure storage and are reloaded on
launch, as `KeychainStore` + `loadTokensFromKeychain()` do on iOS.

`Services/FishersAPI.swift` has 119 typed endpoint functions. Port them all.
Do not hand-roll URLs at call sites.

### Environment / ring switching
Port `AppConfig.swift`'s resolution order: env var → stored override → build
config → fallback. The in-app API server settings panel
(`Views/Profile/APIServerSettingsView.swift`) must work, because it is how
testers point a build at int/test/acc. Rings: `int.fishers.cloud`,
`test.fishers.cloud`, `acc.fishers.cloud`, `www.fishers.cloud`. Default for a
release build is production.

### Live stream
Port `LiveStream.swift`'s parser and semantics. The stream is
`GET /api/v1/stream`, signed like any other request; the events are
`message`, `notification`, `conversations`, `match`, `resync` (plus `ready`,
which is treated as `resync`). **Events say what
changed, never the content** — always re-fetch through the normal endpoints,
which do their own access checks. Reconnect on drop and treat reconnection as
`resync`.

### Offline scoring — the hard part
Port `Cricket/CricketMatchStore.swift` and `CricketSyncService.swift` faithfully:

- The match id is minted **on the device, before the API is involved**, so
  scoring starts on a ground with no signal.
- Every mutation is: append event → `engine.apply` → autosave. It **never**
  waits on the network.
- Events are an append-only log; the scorecard is a fold over them. `undoLast`
  is an event, not a mutation.
- A background sweep pushes pending events when the network returns; the active
  match syncs first; one writer at a time.
- Surface `SyncStatus` (saved / syncing / offline) in the UI as iOS does.

Port `CricketEngine.swift`'s rules with its unit tests
(`ios/FishersTests/CricketEngineTests.swift`) translated to Dart **first**, as
a red suite, then make them pass. Do not reimplement cricket from memory.

### Theme
`FishersTheme.swift` carries the source palette — sage `#8FA28A`, pale sage
`#C7D3C0`, cream `#F7F4ED`, gold `#C8A96B` — plus the darkened ramp that
actually carries text (sage600 `#667964` is 4.68:1 on white; gold700 `#7E673A`
is 5.40:1). Reuse those hex values; do not re-derive them. Dark mode mixes
surfaces from the same sage hue rather than inverting to grey. Map iOS Dynamic
Type to Android text scaling and honour it everywhere.

Use Material 3 components styled to this palette. The app should look like
Fishers on Android, not like iOS transplanted or like stock Material.

## Where to diverge from iOS — deliberately

Parity is behavioural, not pixel-level. Adapt these, and note each in the PR:

- **Back.** Android's system back gesture and button must work on every screen
  and inside every sheet. iOS has no equivalent obligation.
- **Sheets → bottom sheets.** iOS `.sheet` becomes a Material bottom sheet or
  full-screen dialog, whichever matches the weight of the iOS presentation.
- **Tabs.** A bottom `NavigationBar`, same five destinations, same order.
- **Share.** `ShareSheet.swift` becomes the Android share intent.
- **Permissions.** Android asks at point of use (camera for QR, notifications on
  API 33+). iOS's timing will not transfer.
- **Sign in with Apple is not in v1.** Google and email/password are enough to
  ship. On Android it would be a web redirect flow rather than a native one, and
  that cost is not worth paying before the app is in people's hands. Do not call
  `/auth/apple` and do not render the button. This is the one deliberate gap in
  the auth screen's parity with iOS; note it in the parity table and move on.
- **Push notifications.** iOS registers for no remote/APNs push; do not add FCM
  unless asked. In-app notifications come from the API and the SSE stream.
- **Local notifications, however, do exist.** `Services/ProfileReminder.swift`
  schedules local reminders to finish a profile via `UNUserNotificationCenter`.
  Reproduce that with `flutter_local_notifications`, including the Android 13+
  (API 33) `POST_NOTIFICATIONS` runtime permission, which iOS does not need.

## Testing

- **Unit** (`flutter test`): every model's JSON round-trip against real fixtures
  captured from the API; the cricket engine against the translated Swift tests;
  URL resolution; the SSE parser; RBAC gating.
- **Widget**: each screen's loading / empty / error / populated states.
- **Integration** (`integration_test`): the flows the Swift tours cover —
  onboarding, fixtures, clubs, scoring a full 5-over match, live updates.
- Capture fixtures by running the stack locally (`docker-compose.yml`,
  `scripts/`) and recording real responses. Do not invent JSON.

## Definition of done

1. All ten parity criteria above hold.
2. `flutter analyze` is clean; `dart format` applied.
3. Unit, widget and integration suites pass.
4. A release AAB builds in CI and installs on API 26+.
5. `docs/ANDROID.md` written: how to build, run, point at a ring, and test.
6. A parity table in the PR: every iOS screen, its Android counterpart, and any
   deliberate divergence with its reason.

## How to work

1. **Read first.** `ios/Fishers/` and `ios/FishersUITests/` before any code.
   Produce a written parity inventory — every screen, store, model and endpoint
   — and show it before building.
2. **Ask before assuming** on: the state management package, and anything that
   would need a backend change. The project location, the application id and the
   scope of social sign-in are already settled above — do not reopen them.
3. **Build in this order**: config + API client + models → auth + onboarding →
   tabs shell + home → fixtures/events/availability → clubs → chat → profile →
   **cricket engine + offline scoring** → selection → shop/tournaments → polish.
   Ship each layer working, with tests, before starting the next.
4. **Verify against a real ring.** Point the app at `int.fishers.cloud` and use
   it. A screen that has never rendered real data is not done.
5. Commit in reviewable slices with a branch per layer. Never commit to `main`.

When something in `ios/` contradicts this brief, `ios/` is right — say so and
carry on.
