# Android release (Google Play)

Two workflows, the same split as iOS:

| Workflow | Trigger | Does |
|---|---|---|
| `android-kotlin.yml` | any change to `android/**` | build the engine, run the tests, build a debug APK |
| _(release)_ | — | **not written yet** |

> **The release workflow is gone.** It built the Flutter app, which this repo
> no longer has. It had never released anything: the upload job was gated on
> `ANDROID_KEYSTORE_B64`, that secret was never set, and every run skipped it.
> So nothing is lost by its going, and nothing ships from Android until a new
> one is written against `android/`. Everything below about the keystore and
> Play's manual first upload still applies — that part is about Play, not about
> which toolkit built the app.

Skip an automatic release with `[skip release]` or `[skip android]` in the
commit message.

## Before the first automated release

**Google Play's API cannot create an app.** The very first bundle has to be
uploaded by hand in the Play Console, and the listing filled in, before
`android_release.yml` can push anything. Attempting the API first fails with a
package-not-found that reads like a credentials problem and is not one.

Order:

1. Create the app in the Play Console as `com.fishers.app`.
2. Build a signed AAB locally (below) and upload it manually to **internal
   testing**. Complete the store listing and content rating.
3. Then the workflow takes over.

## Signing

Play App Signing holds the real app signing key; what CI holds is the **upload
key**, which only proves a bundle came from us. If it leaks, it can be rotated
in the Play Console without republishing the app — that is the whole point of
the split, and the reason CI never touches the app signing key.

Create the upload keystore once, and keep it somewhere durable — the same
vault the iOS secrets are in:

```bash
keytool -genkey -v \
  -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```

Base64 it for the secret:

```bash
base64 -i upload-keystore.jks | pbcopy   # macOS
```

## Repository secrets

| Secret | What |
|---|---|
| `ANDROID_KEYSTORE_B64` | base64 of `upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | its store password |
| `ANDROID_KEY_ALIAS` | the alias (`upload` above) |
| `ANDROID_KEY_PASSWORD` | that key's password |
| `PLAY_SERVICE_ACCOUNT_JSON` | the whole service-account JSON, pasted |

The release workflow fails with a named error if the keystore or the service
account is missing, rather than quietly signing with debug keys — Play rejects
a debug-signed bundle, but much later and much less legibly.

### The Play service account

1. Play Console → **Setup → API access** → link or create a Google Cloud project.
2. Create a service account, grant it **Release manager** (or narrower: release
   to testing tracks only).
3. Create a JSON key for it and paste the file's contents into
   `PLAY_SERVICE_ACCOUNT_JSON`.

Permissions can take a few hours to propagate. A `403` on the first run
usually means "not yet", not "wrong".

## Versioning

`versionName` comes from `android/app/build.gradle.kts`, or from the tag (`v1.4.0`
ships as `1.4.0`), or from the dispatch input.

`versionCode` is **`github.run_number`**, never pubspec's `+n`. Play refuses a
versionCode it has already seen, and a hand-maintained counter in a file two
people edit is a merge conflict that surfaces as a failed release. The run
number only goes up.

## Tracks

Dispatch chooses: `internal` → `alpha` → `beta` → `production`. Automatic
releases always go to `internal`; production is a deliberate dispatch after QA,
the same way the App Store is on iOS.

## Building locally

```bash
cd android
./gradlew :app:bundleRelease
```

It needs a Rust toolchain and the NDK, like every Android build here: the
cricket engine is Rust, cross-compiled in. There is no fallback that skips it,
because an app with no scoring rules is worse than no app.

Without `android/key.properties` this signs with the **debug** key, so it runs
on a device but cannot be uploaded. That fallback is deliberate — it keeps a
release build working for everyone without a keystore — and it is safe because
uploads only ever happen in the release workflow, which writes `key.properties`
first or fails.

To sign locally, create `android/key.properties` (gitignored):

```properties
storeFile=upload-keystore.jks
storePassword=…
keyAlias=upload
keyPassword=…
```

with the `.jks` beside it in `android/`.

## What the release build does

`isMinifyEnabled` and `isShrinkResources` are on, so the bundle ships an R8
mapping file and native debug symbols, both uploaded to Play. Without them a
release stack trace is unreadable.

`android/app/proguard-rules.pro` keeps only what R8 cannot work out for itself:
kotlinx.serialization finds its serializers by annotation, and without the
keep rules a release build decodes every API response into nothing. Nothing
speculative goes in there — a rule added just in case is a rule nobody can
safely remove later.
