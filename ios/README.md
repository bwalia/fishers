# Fishers iOS app

SwiftUI, iOS 17+, MVVM. `project.yml` is the source of truth — `Fishers.xcodeproj` is generated and gitignored.

## Run

```sh
brew install xcodegen     # once
xcodegen generate
open Fishers.xcodeproj    # Fishers scheme, any iOS 17+ simulator
```

Or from the command line:

```sh
xcodebuild -project Fishers.xcodeproj -scheme Fishers \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Signing is set to automatic with no team, which is all a simulator needs. To run on a device, pick your team under Signing & Capabilities (or set `DEVELOPMENT_TEAM` in `project.yml`).

## Demo mode vs a live API

Demo mode is on by default: `MockAPIClient` serves the London Lords dataset in `Core/Mock/MockData.swift`, so every screen works offline and mutations (RSVP, availability taps, payments, orders, profile edits) persist for the session.

Turn it off in **Profile → Settings → Demo mode** to talk to the Rust backend. The host comes from the `apiBaseURL` user default and falls back to `http://localhost:8080`:

```sh
xcrun simctl spawn booted defaults write uk.co.fishers.app apiBaseURL "http://192.168.1.10:8080"
```

`Info.plist` sets `NSAllowsLocalNetworking` so plain-HTTP local development works.

## Layout

```
App/           app entry, AppState (session + demo mode), root routing
Core/Models/   wire models — user + player profile, sports catalog, per-sport stat catalog, events, commerce
Core/Networking/  Endpoint DSL, APIClient (bearer + 401 refresh), FishersAPI protocol
Core/Auth/     AuthService, Keychain token store
Core/Mock/     MockAPIClient + London Lords dataset
Features/      one folder per tab: Home, Calendar, ClubsTeams, Shop, Profile, Events, Auth, Shared
```

First launch lands on profile setup (`Features/Profile/ProfileSetupView.swift`) and stays there until the player has a sport with a stated level. Profile → *Redo profile setup* clears the saved demo profile and replays it.
