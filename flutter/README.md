# Fishers for Android

The Flutter app, beside `ios/` (the iPhone app), `web/` (the dashboard) and
`backend/` (the API both clients call).

`ios/Fishers/` is the specification. Where this app and the Swift disagree, the
Swift is right. `PARITY.md` maps every iOS screen, store, model and endpoint to
its counterpart here, and records the handful of places the two deliberately
differ.

## Running it

```sh
flutter pub get
flutter analyze
flutter test
```

`flutter test` needs no server: the fixtures under `test/fixtures/api/` are
real responses captured from a local stack, and the network is stubbed.

To run the app against a ring:

```sh
flutter run --dart-define=FISHERS_API_URL=https://int.fishers.cloud
```

Resolution order is environment → stored override (the in-app API server panel)
→ the build's `--dart-define=FishersAPIBaseURL` → a fallback, which is
`10.0.2.2:$API_PORT` for a debug build (an emulator's view of the host machine)
and production for a release one. `lib/config/app_config.dart` has the detail.

To run against a local stack whose ports `.env` has moved, pass the two ports:

```sh
set -a; . ../.env; set +a
flutter run --dart-define=API_PORT=$API_PORT --dart-define=WEB_PORT=$WEB_PORT
```

They reach the build as compile-time constants, which is the only way a port
can reach an app on a device: the emulator has its own process environment
rather than this Mac's. Without them the fallback is `scripts/start.sh`'s own
defaults, 7312 and 7311 — right for a stock checkout, and wrong the moment
`.env` moves them, which is why the port is no longer hard-coded.

Pass the two ports rather than `--dart-define-from-file=../.env`: that flag
turns **every** key in the file into a compile-time constant baked into the
artifact, and `.env` holds `JWT_SECRET`, `ANTHROPIC_API_KEY` and the push
credentials.

A local stack comes up with `../scripts/start.sh --api-only` and seeds with
`../scripts/seed-demo.sh`.

## Layout

`lib/` sits one-to-one beside `ios/Fishers/`, so a reviewer holding a Swift
file can find its counterpart without searching.

```
lib/
  app/        entry point, root widget, providers   ← App/FishersApp.swift
  config/     API/web base URL resolution           ← Config/AppConfig.swift
  theme/      colour ramp, typography, dark mode    ← Theme/FishersTheme.swift
  models/     wire types, enums, JSON codecs        ← Models/, Cricket/CricketTypes.swift
  services/   API client, SSE, secure storage       ← Services/
  stores/     state holders                         ← ViewModels/
  cricket/    engine, local store, sync             ← Cricket/
  views/      screens, mirroring the iOS folders    ← Views/
```
