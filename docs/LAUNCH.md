# Launching a brand on the App Store and Google Play

What is already done, what only you can do, and the order to do it in.

Everything here is per brand. The worked example is **Gully Cricket**
(`app.gullycricket`, www.gullycricket.app); Fishers is the same with its own
values and its own two blockers at the end.

---

## 1. What you have to supply

Six things. Nothing in the repo can invent them, and five of the six are the
reason a submission would be refused rather than merely rejected.

### 1.1 The legal entity and the jurisdiction

Both live privacy policies currently name **nobody**:

> "[the legal entity that runs Gully Cricket] is the data controller."

That is a placeholder, it has been live since 17 September, and a privacy
notice naming no controller names nobody accountable.

Edit `brands/gullycricket.yaml`:

```yaml
legalEntity: <the exact registered company name>
jurisdiction: <India, or England and Wales — whose courts the terms answer in>
```

`node tools/brand/index.mjs check` lists what is still unfilled. The same two
lines go in `brands/fishers.yaml`.

They appear on `/privacy`, on `/terms`, and in the App Store copyright line.

### 1.2 The App Review contact

Apple rings this if review goes wrong. Four files, under
`ios/fastlane/store/gullycricket/review_information/`:

| File | What |
|---|---|
| `first_name.txt`, `last_name.txt` | a person |
| `phone_number.txt` | with the country code, e.g. `+44 7700 900123` |
| `email_address.txt` | one somebody reads |

### 1.3 A demo account that works on production

**This is the one that fails a submission silently.** Every screen past the
first belongs to a club, so review sees nothing without an account — and it
has to exist on **www.gullycricket.app**, not on a ring.

It needs to be in a club with fixtures, a played match and a thread, or review
sees an empty app and rejects it as incomplete.

It does **not** go in the repository. This one is public, and a committed
`demo_password.txt` is a working login to production for anybody who clones
it — so both files are gitignored, and `upload_metadata` writes them at run
time from two values it reads beside the signing material:

```
ASC_DEMO_USER       the email the account signed up with
ASC_DEMO_PASSWORD   its password
```

Put them in `kv/<brand>/ios` in WSLVault, next to `ASC_KEY_ID`. They are per
brand, which a repository secret could not be. The lane stops and names the
missing one rather than uploading a listing App Review cannot sign into.

Make the club **invite-only**, so a demo side does not turn up in front of
real ones. Review is a member, so it sees it either way.

Play asks for the same thing under **App access → All functionality requires
credentials**.

### 1.4 The copyright line

`ios/fastlane/store/gullycricket/copyright.txt` — `2026 <registered name>`.

### 1.5 Android signing

Android has **never produced a release build**. Every run of
`android_release.yml` since 28 September has failed at the same step, "Upload
keystore", because the signing secret is not set.

Make an upload key once. Keep the file and the passwords somewhere permanent:
lose them and the only way back is Play App Signing key reset.

```sh
keytool -genkeypair -v \
  -keystore upload-keystore.jks \
  -alias upload \
  -keyalg RSA -keysize 2048 -validity 10000
```

Then set **five** repository secrets. The workflow checks four of them by name
and fails on the first that is missing:

```sh
base64 -i upload-keystore.jks | gh secret set ANDROID_KEYSTORE_B64
gh secret set ANDROID_KEYSTORE_PASSWORD    # the store password
gh secret set ANDROID_KEY_ALIAS            # "upload", from the command above
gh secret set ANDROID_KEY_PASSWORD         # the key password
gh secret set PLAY_SERVICE_ACCOUNT_JSON < play-service-account.json
```

The service account comes from Play Console → Setup → API access → create a
service account in Google Cloud, then grant it **Release manager** on the app.

> **These are one set of repository secrets, and both brands sign with them.**
> `docs/ANDROID_RELEASE.md` says each brand needs its own upload keystore,
> because each is a separate Play app — and it is right, but the workflow has
> no per-brand path for it the way iOS has `kv/<brand>/ios` in Vault. Signing
> both brands with one key works and Play will accept it; separating them later
> means a key reset. If Gully Cricket is the only one launching now, generate
> its keystore and treat these secrets as its own, rather than as a shared pair.

### 1.6 The two store records

Neither API can create an app.

* **App Store Connect** — Gully Cricket already exists, with version 1.0 in
  Prepare for Submission. Nothing to do.
* **Play Console** — create the app under `app.gullycricket` by hand, then
  upload the first bundle manually. Play refuses an API upload to a track that
  has never had a build.

---

## 2. The two questionnaires nobody can automate

Apple's API key cannot set either, and Play's cannot either. Both are filled
in once, by hand. These are the answers the code supports — check them rather
than trust them, because you are the one signing.

### 2.1 Age rating (App Store) and content rating (Play)

| Question | Answer | Why |
|---|---|---|
| Violence, sexual content, drugs, gambling, horror | None | there is none |
| **User-generated content** | **Yes** | chat, profiles, photographs, marketplace listings |
| Can users communicate? | Yes | club chat and seller messages |
| Is there moderation? | **Yes** | reporting and blocking, both in the app |
| Does it share location with other users? | Yes, approximate | an area or postcode the member typed, for lifts and selection |
| Unrestricted web access | No | no in-app browser |
| Ads | None | |

That lands at **12+** on the App Store and **Teen** on Play, which is normal
for an app with chat. Declaring no UGC with a chat in the app is the single
most common cause of removal after release.

### 2.2 App Privacy (Apple) and Data safety (Play)

Everything below is **collected, linked to the user, and not used for
tracking**. There is no advertising, no data broker, no cross-app tracking and
no third-party analytics SDK.

| Category | Collected | What exactly |
|---|---|---|
| Contact info | Yes | name, email, mobile, emergency contact |
| User content | Yes | profile photograph, chat messages, marketplace listings and their photographs, report notes |
| Identifiers | Yes | account id, push device token |
| Location — **coarse** | Yes | the area/postcode **typed by the member**. The app asks for no device location: there is no CoreLocation anywhere in it and no location usage string in `Info.plist` |
| Purchases | Yes | match fees and shop orders. Card details never reach the API — Stripe takes those, and only the record that it was paid is kept |
| Usage data | Yes | availability, attendance, ball-by-ball scoring |
| Diagnostics / crash data | No | no crash SDK |
| Health, financial account, browsing, contacts, sensitive info | No | |

**Purpose** for all of it: *App Functionality*. Not Analytics, not
Personalisation, not Advertising.

**Data deletion** — Play asks for a URL. Use
`https://www.gullycricket.app/profile#delete`. Deletion is also in the app, at
Profile → Delete account, which is what Apple requires.

**Encryption in transit:** yes. **Can a user request deletion:** yes.

---

## 3. What is already done

* Listing text for both brands, in the repo, uploaded by a workflow:
  `ios/fastlane/store/<brand>/` and `android/fastlane/metadata/<brand>/`.
  Every claim in it is one the code supports — there is no calendar export and
  no StoreKit, so neither is mentioned.
* **Screenshots** for Gully Cricket, shot from the real app against Punjab and
  Delhi demo data rather than the Hertfordshire seed: `./scripts/store-screenshots.sh`
  with `BRAND=gullycricket`, from `scripts/seed-area.py --area india`.
* **Reporting and blocking**, on web, iOS and Android, enforced in the four
  places somebody can reach you. Required by App Store guideline 1.2 and by
  Play's UGC policy.
* **Privacy and terms** that name the right law per brand: UK GDPR and the ICO
  for Fishers, the DPDP Act 2023 and the Data Protection Board of India for
  Gully Cricket, with the child age at 13 and 18 respectively.
* `/support`, because the support URL is a required field in both stores.
* A readiness gate: `store_status` reports every blank field before anything
  is submitted.

---

## 4. Shipping it

### App Store

```sh
# What is still missing — read this first, every time.
gh workflow run ios_release.yml -f brand=gullycricket -f target=store_status

# The listing text. Refuses while any value is still in brackets.
gh workflow run ios_release.yml -f brand=gullycricket -f target=metadata

# The screenshots, from the runner's ~/fishers-store-screenshots/<brand>/en-GB/
gh workflow run ios_release.yml -f brand=gullycricket -f target=screenshots

# Age rating and App Privacy, by hand in App Store Connect. Then:
gh workflow run ios_release.yml -f brand=gullycricket -f target=store_status

# Only when that reports nothing outstanding:
gh workflow run ios_release.yml -f brand=gullycricket -f target=app_store
```

`app_store` **promotes the build already on TestFlight** — it does not archive
a new one, so what ships is what was signed off.

> Gully Cricket's listing was created by hand as version **1.0** while every
> build carries `project.yml`'s **1.0.0**, and Apple only lets a build join a
> version whose number matches its own train. `release` renames the version to
> match, but only where nothing is attached to orphan. If you would rather ship
> as "1.0", set `MARKETING_VERSION: 1.0` in `ios/project.yml` and send a fresh
> build to TestFlight instead.

### Play

```sh
# Internal track first — it is the only one worth being wrong on.
gh workflow run android_release.yml -f brand=gullycricket -f track=internal
gh workflow run android_release.yml -f brand=gullycricket -f track=production
```

The listing text, content rating and Data safety are entered in Play Console;
`android/fastlane/metadata/<brand>/en-GB/` holds the text to paste.

**Play still needs a feature graphic**, 1024×500 PNG or JPEG. There is no way
to derive one from the brand files that would be worth looking at — it is a
designed banner, not a generated one.

---

## 5. Before you press submit

- [ ] `store_status` reports nothing outstanding
- [ ] The demo account signs in **on production** and lands in a club with a played match
- [ ] `/privacy` and `/terms` name a real company, on the live site
- [ ] Fishers only: production API redeployed — it is behind GullyCricket's and
      still answers signup errors with raw validator output
