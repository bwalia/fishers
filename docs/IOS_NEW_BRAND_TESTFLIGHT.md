# Putting a brand on TestFlight

A checklist for a brand that has never shipped. GullyCricket is the worked
example; a third brand follows the same steps.

For how the pipeline itself works — the lanes, the secrets, the runner — see
[IOS_RELEASE.md](IOS_RELEASE.md). This is only the part that is *missing* for a
new brand.

---

## The short answer

**You do not need any new keys from Apple.**

The App Store Connect API key, the issuer id and the team id are **per team**,
not per app. Fishers already uses them, they are already in CI, and they
already work for GullyCricket — the run on 6 October got as far as:

```
Creating authorization token for App Store Connect API
[!] Could not find an app on App Store Connect with app_identifier: app.gullycricket
```

It authenticated. It then asked Apple about an app that does not exist.

So there is exactly **one** thing standing between GullyCricket and TestFlight:
the app record, which is made by hand in a browser once. Everything else is
optional polish.

---

## Step 1 — create the app on Apple (in a browser, once)

This is the only manual step, it takes about two minutes, and it is done once
per brand forever.

**It cannot be automated from this pipeline.** fastlane's `produce` is the
action for it, and `produce` has no `api_key` option — it signs in with an
Apple ID through Spaceship, and this pipeline deliberately has no Apple ID,
only an App Store Connect API key. A `bootstrap_app` target was added on
2026-10-06 and removed on 2026-10-07 for exactly that reason:

```
[!] Could not find option 'api_key' in the list of available options:
    username, app_identifier, ..., skip_devcenter, team_id, team_name, ...
```

### 1a. Register the App ID

[developer.apple.com → Identifiers](https://developer.apple.com/account/resources/identifiers/list)

1. **+** → **App IDs** → Continue → **App** → Continue
2. Description: `Gully Cricket`
3. Bundle ID: **Explicit**, `app.gullycricket`
4. Tick **Sign In with Apple** and **Push Notifications**
5. Continue → Register

Those two capabilities come from `ios/Fishers/Fishers.entitlements`. They must
be on the App ID *before* a provisioning profile can carry them — a profile
without them fails later, at signing, with an error about provisioning that
never mentions capabilities.

### 1b. Create the App Store Connect record

[appstoreconnect.apple.com → Apps](https://appstoreconnect.apple.com/apps)

1. **+** → **New App**
2. Platform: **iOS**
3. Name: `Gully Cricket`
4. Primary language: whatever you want it listed in
5. Bundle ID: pick `app.gullycricket` from the list — it appears because of 1a
6. SKU: anything unique to the account; `app.gullycricket` is fine
7. Create

That is the whole of it. Nothing else about Apple is per-brand.

## Step 2 — release it

**Actions → iOS Release → Run workflow**

| field | value |
|---|---|
| brand | `gullycricket` |
| target | `testflight` |

From here it is identical to Fishers: build number, signing, IPA, upload,
TestFlight.

After this, every merge to `main` that touches `ios/**` releases **both**
brands automatically. Until it exists, those merges will keep showing a red
`gullycricket → testflight` job beside a green `fishers` one — noise, not
breakage, and it stops the moment step 1 is done.

---

## Step 3 — Google sign-in on iOS (optional)

"Continue with Google" will not be configured in the GullyCricket iOS app
until this is done. Nothing else is affected: the build succeeds without it,
because the loader treats these two as optional.

1. In the Google Cloud console, create an **OAuth client → iOS** for bundle id
   `app.gullycricket`.
2. Send me the client id and the reversed client id, or put them in Vault
   yourself at `kv/gullycricket/ios`:

```
GOOGLE_IOS_CLIENT_ID
GOOGLE_REVERSED_CLIENT_ID
```

Fishers' equivalent path holds exactly those two keys and nothing else.

---

## What you do NOT have to do

Things people reasonably expect to need, which are already handled:

| | |
|---|---|
| **A second Apple developer membership** | No. One team, many apps. |
| **New certificates or provisioning profiles** | No. fastlane mints and reuses them from the same API key, into the runner's persistent keychain. |
| **Creating the TestFlight groups** | No. `find_or_create_beta_group!` creates both the internal group (`Gully Cricket Team`) and the external one. |
| **Export compliance answers** | No. `ITSAppUsesNonExemptEncryption: false` is declared in `project.yml` and `Info.plist`, and the lanes pass `uses_non_exempt_encryption: false`. |
| **Screenshots** | Not for TestFlight. They are an App Store submission thing, and there is a separate `screenshots` target for them. |
| **A new icon** | No. The brand pipeline renders GullyCricket's own icon into the asset catalogue — verified 1024×1024, no alpha, fully opaque, which is what Apple requires. |

---

## Watch-outs

**The Beta App Review text is Fishers-worded.** External TestFlight goes
through Apple's Beta App Review, and the lane submits a description that
defaults to *"Fishers is a club sports app for fixtures, live cricket scoring,
chat, and team selection."* Override per run:

```
TESTFLIGHT_BETA_DESCRIPTION   the app description Apple's reviewer reads
TESTFLIGHT_CHANGELOG          "what to test" for this build
```

Internal testers do not wait for that review at all.

**Apple may ask for app-record details** before Beta App Review passes —
privacy policy URL, contact information, a category. Those live on the App
Store Connect record and only come up on the external path.

**Who gets invited.** Defaults to `balindersinghwalia@icloud.com` and
`harchran001@gmail.com`, for every brand. Override with `TESTFLIGHT_TESTERS`
(comma-separated).

**The public TestFlight link in the invite email is Fishers'.** App Store
Connect only issues a brand its own link once its external group has passed
Beta App Review, so GullyCricket's invite will quote the wrong backup link
until then.

---

## If a run fails

| what it says | what it means |
|---|---|
| `Could not find an app on App Store Connect with app_identifier: app.gullycricket` | Step 1 has not been done. |
| `ERROR: ... is missing required key(s): ASC_KEY_ID, ASC_ISSUER_ID, APPLE_TEAM_ID` | The team-wide credentials are not reaching the runner. Not a per-brand problem — Fishers would be failing too. |
| A signing or provisioning error naming the bundle id | The App ID exists but is missing a capability. Check Sign in with Apple and Push Notifications on it. |
| `You must provide a value for the attribute 'contactEmail'` | The app is new and has no Beta App Review contact. The `beta` lane now sends one on the first upload (`TESTFLIGHT_CONTACT_*` overrides it); a build that hit this was still uploaded and processed. |
