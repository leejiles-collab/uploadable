# Shipping Uploadable

Everything outside this repository, in the order it has to happen. Filled in
properly at phase 5; what is here already are the steps that must not be
improvised and the traps that have already cost time on other apps.

| | |
|---|---|
| Team ID | `PT3HD7UTA5` (Individual) |
| App bundle ID | `com.leejiles.uploadable` |
| Share extension bundle ID | `com.leejiles.uploadable.share` |
| App Group | `group.com.leejiles.uploadable` |
| In-app purchase product ID | `com.leejiles.uploadable.pro` |
| Price | $9.99, non-consumable, one payment |
| App Store name | `Uploadable` — was `Fits`, which collided with fitness apps across the whole category |
| App Store subtitle | `Visa & passport photo sizing` |
| Apple ID | `6802146013` |
| Free tier | `Config.freeExports` exports, currently 2 |

`BundleConfig.swift` is the single source for the identifiers and `project.yml`
carries the team, so `./Tools/generate-project.sh` regenerates a correctly
configured project at any time.

---

## Before every submission

**1. Re-check the specs.**

```
cd Tools/uploadablecli && swift run -c release uploadablecli specs --check
```

It prints every preset with its numbers, official URL and verification date,
oldest first, and flags anything unverified or older than
`Config.specStaleAfterDays` (90). Re-read the official page for anything it
names and update `SpecCatalog.swift`, including `verifiedOn`.

Governments change these numbers without announcing it. A stale preset turns a
portal's rejection into our fault.

**2. Do not ship an unverified preset without saying so in the UI.** A preset
with `verifiedOn: nil` must render as unverified wherever it appears.

**3. The DV Lottery preset is seasonal.** It is the one spec with a hard annual
spike. Registration opens around early October and runs about five weeks, and
the DV-YYYY Program Instructions PDF — the only official statement of the photo
requirements — publishes only when it opens. Outside that window
dvprogram.state.gov shows the previous year's closed programme and nothing
usable. When the PDF appears: read it, set a real `verifiedOn`, and move
`usDVLottery` from `drafts` into `all`. Until then it stays out of the app.
Secondary sources disagree over whether the requirement is exactly 600 × 600 or
a 600–1200 range, and a one-entry-per-year application with no appeals process
is the worst possible place to be approximately right.

**4. App Store copy may not claim** that any specific portal rejects Display P3,
or cite rejection rates, until that has been tested against the real form. It
may say that Uploadable converts to sRGB, removes location data, and lands the file
inside the required range — all three are verifiable from the output.

*This prohibition stands, and the test behind it is deliberately not being run.*
Settling it would mean starting a real DS-160 application to see what a
validator does with a colour profile, which is not a reasonable thing to do for
a marketing sentence. It is also unnecessary: the State Department's page states
the requirement outright — **"in sRGB color space"** — so converting to sRGB is
a documented requirement, not a precaution, and its correctness does not depend
on whether the validator enforces it. Nothing shipping makes the untested claim,
so nothing is blocked.

The matched pair stays in `Fixtures/out` and `uploadablecli pair` stays in the
CLI. If the claim is ever wanted, the experiment is one upload away — but wanting
the claim is what would justify the cost, and it has not.

---

## How we are allowed to describe what Uploadable does

The State Department pages say *"Do not use any kind of filter or retouching
tools to change your appearance"* and *"We check all photos to ensure you are
not using artificial intelligence tools."*

Uploadable does not alter anyone's appearance. It re-encodes a file, changes its pixel
dimensions and converts its colour space — it does not touch faces, skin,
lighting or background. But the line between re-encoding a file and editing a
photo is not one a reviewer is obliged to draw where we would, and a listing
that reads as photo editing invites exactly the wrong reading.

So, in App Store copy, screenshots, the in-app UI and support pages:

- **Say:** converts the format, resizes to the required dimensions, brings the
  file inside the required size range, converts to sRGB, removes location data.
- **Never say:** edit, enhance, retouch, improve, fix, beautify, optimise your
  photo, AI, smart, automatic enhancement, or anything implying the photograph
  itself has been changed.

The distinction to hold on to: Uploadable changes the *file*, never the *picture*.
That is also the honest description, which is why it is easy to keep to.

---

## Distribution

**Choose App Store Connect. Never "TestFlight Internal Only."**

That option permanently stamps the build `INTERNAL_ONLY`. It uploads, processes,
reports "Validated" and installs through TestFlight — and can never be attached
to an App Store version. The Add Build dialog silently refuses it with no error;
the API says `ENTITY_ERROR.RELATIONSHIP.INVALID`. The audience type cannot be
changed after upload and a build number can never be reused, so the only way out
is a new upload. App Store Connect distribution delivers to TestFlight anyway,
so the "fast path" saves nothing.

## Traps already paid for

- **App Store Connect rejects any image carrying an alpha channel** —
  screenshots, review images, everything, silently. Check every file with
  `sips -g hasAlpha` before uploading.
- **Swift principal classes must be module-qualified** —
  `$(PRODUCT_MODULE_NAME).ShareViewController`. A bare name resolves to nothing
  and the user gets a blank sheet with no error anywhere. Already correct in
  `Support/UploadableShare-Info.plist`.
- **An extension cannot write to the app's Files folder.** Separate sandboxes.
  Stage into the App Group and let the app file it on next launch, and say so
  honestly in the UI rather than claiming the file is somewhere it is not yet.
- **A `.storekit` file must be a project member**, not merely referenced by the
  scheme, or the paywall silently talks to the real App Store and shows no
  price. `project.yml` adds it with `buildPhase: none`;
  `generate-project.sh` fixes the scheme path XcodeGen writes one level short.
- **IAPs need price and availability set** before a build can be attached.
- **Set App Pricing to Free.** The IAP is the $9.99, not the download.
- **Age rating: everything No.** No web access, no user content, no social.
- **Contact info is required and "Sign-in required" must be unchecked.**
- **Screenshots: largest size per family only** — 1320 × 2868 for iPhone,
  2064 × 2752 for iPad. Apple scales the rest itself.
- **A 6.5" drop zone does not mean 6.5" is required.** 1320 × 2868 is the
  required **6.9"** size; 6.5" (1284 × 2778 / 1242 × 2688) is required *only*
  when no 6.9" screenshots are provided, so the 6.5" zone is the fallback slot
  showing itself because the 6.9" slot is still empty. Pick the display size in
  the version page's selector rather than resizing anything.
- **Publish the privacy answers.** Saving them is not enough and it blocks
  submission.

## The in-app purchase

**Created — product `6802328412`, state `MISSING_METADATA`.** Localization and
price schedule (USD, manual) are both in place; the one thing outstanding is the
**review screenshot**, which is why the state has not advanced to *Ready to
Submit*. The product cannot be attached to the version until it does.

Until an IAP exists at all, a shipped build's paywall reads "Get Uploadable Pro"
with no price and tapping it shows *"The store isn't available right now."* —
`Product.products(for:)` returns nothing. A reviewer who reaches the paywall
cannot buy, which is a Guideline 2.1 rejection rather than a cosmetic gap. Check
state by API rather than by eye:

```
GET /v2/inAppPurchases/<id>?include=inAppPurchaseLocalizations,iapPriceSchedule,appStoreReviewScreenshot
```

`appStoreReviewScreenshot` with `data: null` is the whole diagnosis. Note that
`GET /v2/inAppPurchases/<id>/iapPriceSchedule` returns 404 even when a schedule
exists — read the relationship off the product instead, or fetch
`/v1/inAppPurchasePriceSchedules/<id>`. A 404 on that path is not evidence of a
missing price.

| | |
|---|---|
| Product ID | `com.leejiles.uploadable.pro` |
| Type | Non-Consumable |
| Reference Name | `Uploadable Pro` (internal only) |
| Price | $9.99, base country United States |

The product ID comes from `BundleConfig.proProductID` and must match exactly. It
is permanent once created — it cannot be changed or reused, even after deletion.

**Apps → Uploadable → Monetization → In-App Purchases → ✚**, then fill all four
sections or it never leaves *Missing Metadata*:

1. **Availability** — all countries and regions.
2. **Price Schedule** — price points, not numbered tiers any more. $9.99 USD.
3. **App Store Localization**, English (U.S.):
   - Display Name (30 char limit): `Uploadable Pro`
   - Description (45 char limit): `Unlimited exports. One payment.` (31)
   - Avoid "unlock" — it reads as feature-gating to some reviewers.
4. **Review Information** — screenshot plus notes:

```
Fitting photos is free and unlimited. The first two exports are free.
To reach this screen: open a photo, choose a destination, tap Make it
fit, then export the result three times. The third export shows the
purchase screen.
```

Then **attach it to version 1.0** in the version page's *In-App Purchases and
Subscriptions* section. A first-version IAP is reviewed alongside the app; if it
is not attached it is simply not reviewed, and the app ships with a dead paywall
regardless of how complete the product looks.

### Screenshot display types, if this is ever automated

There is **no `APP_IPHONE_69`** in the API. Straight from the live API's own
validation error — better evidence than the docs — the accepted iPhone values are
`APP_IPHONE_35`, `_40`, `_47`, `_55`, `_58`, `_61`, `_65`, `_67`, and for iPad
`APP_IPAD_97`, `_105`, `APP_IPAD_PRO_129`, `APP_IPAD_PRO_3GEN_11`,
`APP_IPAD_PRO_3GEN_129`. So 6.9" files go into the **`APP_IPHONE_67`** set and
13" iPad files into `APP_IPAD_PRO_3GEN_129`. The display-type name lags the
hardware; the pixel dimensions are what Apple validates.

To ask the API what it accepts rather than guessing, POST a deliberately invalid
value and read the error — it enumerates every valid one:

```
POST /v1/appScreenshotSets   {"data":{"type":"appScreenshotSets",
  "attributes":{"screenshotDisplayType":"NONSENSE"}, ...}}
```

### The review screenshot is 1290 x 2796, not the listing size

**This field rejects 1320 x 2868.** The error is *"The dimensions of one or more
screenshots are wrong"*, which names no size. Apple's help text for the field
says 640 x 920 *minimum* — true, and actively misleading, because clearing the
floor is not sufficient. The field wants **6.7"**, 1290 x 2796. That is the size
App Store Connect accepted for Smaller, confirmed by reading the delivered asset
back rather than by guessing:

```
GET /v2/inAppPurchases/<id>/appStoreReviewScreenshot   ->  imageAsset 1290 x 2796
```

`./Tools/screenshots.sh` produces it at
`~/Desktop/Uploadable-AppStore/iap-review_1290x2796/paywall.png` — a plain device
capture, no caption and no bezel, since a reviewer wants the purchase screen as
the app draws it. It is reached honestly, by spending both free exports.

The capture happens on a dedicated 6.7" simulator (`Uploadable-IAP-67`, an iPhone
16 Plus), which the script creates if it is absent. **iPhone 16 Pro Max is 6.9",
not 6.7"** — the 6.7" devices are 16 Plus, 15 Plus and 14/15 Pro Max. A 6.9"
capture is not resized down to fit, because the two aspect ratios differ slightly
and a resize would either distort the screen or letterbox it.

The button on it has no price. **This is not fixable from the pipeline.** The
`.storekit` configuration is a *scheme launch* setting that Xcode applies when
Xcode launches the app; `simctl launch` bypasses it, and there is no
`simctl storekit` subcommand to apply it another way. Do not spend an hour on
this. Either:

- **Use it as is.** The field documents where the purchase appears, which it
  does. This is enough to get the IAP to *Ready to Submit* and unblock
  everything else.
- **Retake it from TestFlight** after the IAP exists and the build is uploaded,
  when the real $9.99 renders. Only worth doing if the price-less button
  actually bothers you.

## Store listing

Paste these verbatim. Every claim here is one the app demonstrably makes good
on, and nothing in it describes editing a photograph — see *How we are allowed
to describe what Uploadable does* above before changing a word.

### Name and subtitle

```
Uploadable
Visa & passport photo sizing
```

### Description

The first paragraph is the only part most people read, and the App Store
truncates the rest behind *more*. It leads with the problem, names no features,
and contains no marketing language.

```
A portal rejected your photo and didn't tell you why. It was probably the file:
the wrong dimensions, too many kilobytes, too few, a PNG where JPEG was
required, or a profile the form can't read. Uploadable changes the file until it
matches what the form asks for, then shows you every requirement it met.

WHAT IT CHANGES

- Dimensions, to exactly what the form requires
- File size, into the kilobyte range it asks for, not merely under the maximum
- Format, to JPEG
- Colour, to sRGB
- Location data and camera metadata, removed

WHAT IT LEAVES ALONE

Your photograph. No filters, no retouching, no background removal, no AI. It
changes the file, never the picture. Government photo pages ask you not to alter
your appearance and say they screen for it, so Uploadable stays well clear of
that line.

DESTINATIONS

US Visa (DS-160), US Passport, UK Passport, India eVisa, Canada PR Card, New
Zealand Visa / NZeTA. Each one shows the date its requirements were last read
off the official government page, with a link to that page. Anything we could
not confirm is not offered.

If yours isn't listed, Custom takes the numbers straight off your form.

YOU PLACE THE CROP

A square crop centred on a portrait usually cuts off the top of someone's head.
Uploadable shows you the crop rectangle over your photo and lets you drag and
resize it before anything happens. It does not guess at framing — it does not
look at the picture at all.

IT CHECKS ITS OWN WORK

Before handing you a file, Uploadable re-reads it from disk: the pixel
dimensions, the byte count, that it is genuinely a JPEG, that sRGB is embedded,
that the location data is gone. A file that fails any check is discarded rather
than given to you. When it cannot meet a requirement — a photo too small to
reach the minimum, a range it cannot land inside — it says so and stops, instead
of enlarging your photo and inventing detail that was never there.

NOTHING LEAVES YOUR PHONE

No account, no sign-in, no upload, no analytics, no tracking, no third-party
code. It works in Airplane Mode, which is the easiest way to prove it to
yourself.

PRICE

Fitting photos is free and unlimited — run any photo against any destination and
see the full result before paying anything. The first two exports are free.
After that, Uploadable Pro is $9.99 once. No subscription.

Uploadable cannot tell you whether your photograph itself will be accepted. Head
size, expression, lighting and background are the photographer's problem. It
makes the file correct.
```

### Promotional text (170 characters, editable without a new build)

Paste as a single line — the wrapping below is this file's, not the field's.

```
Rejected photo, no explanation? Usually it's the file. Uploadable resizes it, lands it inside the required kilobyte range, converts to JPEG/sRGB, strips location data.
```

### Keywords (100 characters, comma-separated, no spaces)

```
ds160,kb,jpeg,resize,compress,crop,id,headshot,immigration,esta,eta,ircc,embassy,green,card,nz,form
```

99 characters. Two rules govern this field and both cost real terms:

- **Never repeat the name or subtitle.** Apple already indexes those, so
  `visa`, `passport`, `photo`, `sizing` and `uploadable` here would be dead
  weight. This is why the list reads oddly — the obvious words are already
  working elsewhere.
- **Apple builds phrases from the list**, so `green` + `card` covers "green
  card" without spending characters on the phrase.

The one judgement call is `resize`, which may stem close enough to the
subtitle's `sizing` to be redundant. It is the highest-volume term left
available and worth the risk; if a later version needs the six characters, that
is where to find them.

### Everything else on the form

| Field | Value |
|---|---|
| Category | Primary **Utilities**, secondary **Travel** |
| Age rating | 4+ — every question answered No |
| Price | **Free**. The $9.99 is the IAP, not the download |
| Copyright | `2026 Lee Jiles` |
| Privacy Policy URL | `https://leejiles-collab.github.io/uploadable/privacy.html` |
| Support URL | `https://leejiles-collab.github.io/uploadable/support.html` |
| Marketing URL | `https://leejiles-collab.github.io/uploadable/` (optional) |
| Support email | `leejiles@gmail.com` |
| Sign-in required | **Unchecked** |

### App Privacy answers

Answer **"Data Not Collected"** and nothing else. Then press **Publish** —
saving is not enough and an unpublished answer set blocks submission.

This is verifiable rather than aspirational: the app contains no `URLSession`,
no network code of any kind, no analytics and no third-party SDKs. See *Privacy
manifest* below.

### Review notes

```
No account or sign-in is required. Everything works offline — Airplane Mode is
a good way to see that nothing is uploaded.

Fitting a photo is free and unlimited. The first two exports are free; after
that the $9.99 non-consumable unlocks unlimited exports. To reach the purchase
screen: open a photo, choose a destination, tap Make it fit, then export the
result three times.

Uploadable does not edit photographs. It changes file properties only —
dimensions, format, colour profile, byte size, metadata. There is no filter,
retouching, background removal, face detection or AI anywhere in the app.
```

### Screenshots

`./Tools/screenshots.sh path/to/portrait.jpg` produces both required sizes into
`~/Desktop/Uploadable-AppStore/` and verifies each file. Details in *Screenshot
pipeline* below.

Support and privacy pages live in `docs/` and are served by GitHub Pages.

---

## Privacy manifest

`Support/PrivacyInfo.xcprivacy`, added as a **resource** to both the app and the
extension in `project.yml`. Confirm it is in both built bundles rather than
assuming — a manifest that is a project member but not in the resources build
phase compiles fine and ships nothing:

```
ls "$APP/PrivacyInfo.xcprivacy" "$APP/PlugIns/UploadableShare.appex/PrivacyInfo.xcprivacy"
```

The declarations were checked against the source, not guessed, and the check
found two errors worth remembering:

- **`UserDefaults(suiteName:)` needs `1C8F.1`, not `CA92.1`.** `CA92.1` covers
  the app's own defaults; `1C8F.1` covers an App Group shared with extensions.
  The manifest said `CA92.1` while `ExportStore` reads an App Group suite and
  never touches `UserDefaults.standard`. Any app with a share extension that
  shares state is likely to have this exact mismatch.
- **`NSPrivacyAccessedAPICategoryDiskSpace` was declared and never used.** No
  capacity API appears anywhere in the app. Removed. Declaring an API you do not
  call is not caught by anything and quietly makes the manifest untrue.

To re-check after any change, grep for what each category actually covers:

```
grep -rn "UserDefaults" App ShareExtension UploadableKit/Sources
grep -rnE "creationDate|modificationDate|attributesOfItem|getattrlist" App ShareExtension UploadableKit/Sources
grep -rnE "volumeAvailableCapacity|systemFreeSize|statfs" App ShareExtension UploadableKit/Sources
grep -rnE "systemUptime|mach_absolute_time" App ShareExtension UploadableKit/Sources
grep -rn "activeInputModes" App ShareExtension UploadableKit/Sources
```

The last three must return nothing, or the manifest needs a new entry.

**The "no network" claim is verifiable and was verified**, because the privacy
page and the description both state it outright:

```
grep -rnE "URLSession|NWConnection|dataTask|CFStream|getaddrinfo|socket\(|Analytics|Firebase|Crashlytics" App ShareExtension UploadableKit/Sources
```

Nothing. Every import across the three targets is an Apple framework —
CoreGraphics, CryptoKit, Foundation, ImageIO, Observation, Photos, PhotosUI,
Security, StoreKit, SwiftUI, UIKit, UniformTypeIdentifiers — plus the one local
package. There are no third-party dependencies, so no bundled SDK manifests to
reconcile.

---

## Screenshot pipeline

```
./Tools/screenshots.sh                       # Fixtures/screenshot-source.jpg
./Tools/screenshots.sh ~/Desktop/model.jpg   # any portrait
```

Builds for both simulators, drives the app to each screen, captures, composites
the captions, and verifies every output file. Result:
`~/Desktop/Uploadable-AppStore/` with one folder per required size.

**The photograph is the only input.** Every number a viewer sees — dimensions,
kilobytes, the ticks — is inside the screenshot and was produced by the engine
running on that photo. The captions therefore state no numbers at all, so
swapping the photograph can never turn a caption into a false claim. Keep that
property.

`App/ScreenshotHarness.swift` drives it, behind `#if DEBUG`, so no launch
argument that rewrites app state exists in a shipping binary. It reaches the
paywall by spending the free exports the way a person would rather than by
setting a flag, and it drags the crop to the top of the frame the way a person
would — `select` leaves the crop centred, and a centred square on a
head-and-shoulders portrait clips the crown.

The source photo must be a licensed portrait with a model release covering App
Store screenshots — see *What the source photo has to be* below.

Traps this pipeline already handles, all of which cost time:

- **Alpha is rejected silently.** Every file is checked with `sips -g hasAlpha`
  and the script exits non-zero if any carries one.
- **Another app of ours left running becomes a `◀ AppName` back-breadcrumb** in
  the status bar, because iOS believes it launched us. The script terminates
  every other `com.leejiles.*` app first. Caught only by reading a finished
  screenshot closely.
- **The status bar is overridden** to 9:41, full bars, charged — otherwise it
  shows whatever the simulator drifted to.
- **Only the largest size per family is uploaded.** 1320 × 2868 iPhone,
  2064 × 2752 iPad. Apple scales the rest.

---

## Publishing the support and privacy pages

**Done.** `https://github.com/leejiles-collab/uploadable`, public, Pages
serving `main` / `/docs`. All three pages verified live over anonymous HTTPS:

| | |
|---|---|
| Privacy Policy URL | `https://leejiles-collab.github.io/uploadable/privacy.html` |
| Support URL | `https://leejiles-collab.github.io/uploadable/support.html` |
| Marketing URL | `https://leejiles-collab.github.io/uploadable/` |

Set up the same way for a future app, entirely from the command line:

```
gh repo create <owner>/<repo> --public --source=. --remote=origin --description "…"
git push -u origin main
gh api -X POST repos/<owner>/<repo>/pages -f "source[branch]=main" -f "source[path]=/docs"
```

The `repo` scope on an existing `gh auth login` covers all three; no separate
token is needed. Pages on a **private** repository requires a paid plan, and
Apple has to reach both URLs anonymously, so public is the cheap answer.

Then verify rather than assume — the first Pages build takes a minute and a
missing `style.css` still returns a page, just an unstyled one:

```
curl -s -o /dev/null -w "%{http_code}\n" https://<owner>.github.io/<repo>/privacy.html
```

Before pushing, check what is about to become public:
`git grep -nIE "AuthKey|PRIVATE KEY|api[_-]?key|secret|token"` over tracked
files, and confirm `.p8` keys, entitlements and `Fixtures/` are ignored. Note
that `SHIPPING.md` itself publishes the Team ID and the app's Apple ID —
neither is a secret (the Team ID is in every signed app, the Apple ID is in the
store URL), but know that it is happening rather than discover it.

Both pages carry the support email and a "Last updated" date. Update the date
whenever the behaviour they describe changes, and push — Pages redeploys on
its own.

---

## The source photo — licence and provenance

The face in the App Store screenshots and in the Display P3 / sRGB matched pair
is the same photograph:

| | |
|---|---|
| File | `pexels-kooldark-19601394.jpg` |
| Source | Pexels, photo ID **19601394** — `https://www.pexels.com/photo/19601394/` |
| Licence | Pexels licence: free for commercial use, no attribution required |
| Attribution | Not required. Photographer credited as *kooldark* if ever wanted |
| Not AI-generated | Confirmed at the source before use |
| Dimensions | 2024 × 3036, sRGB, no alpha |

**`Fixtures/` is git-ignored, so the photograph is not in this repository.** That
is deliberate — it keeps a real person's face out of what may become a public
repo — and it is the reason the Pexels ID above is recorded rather than merely
the filename. To rebuild the screenshots or the matched pair on a fresh
checkout, download it again from that URL and put it at
`Fixtures/pexels-kooldark-19601394.jpg`.

### If it is ever replaced

Licensed stock with terms covering commercial use, since the screenshots show a
real face at full size in a store listing. What the photograph has to be:

| | |
|---|---|
| Aspect | Portrait, 2:3 or 3:4 |
| Minimum | Enough that no offered spec upscales — 2000 × 3000 clears all six |
| Framing | Head and shoulders, real space above the crown |
| Background | Plain, evenly lit, light |
| Format | JPEG |

The headroom matters more than the pixel count. Several destinations want a
square, and a square crop from a tight portrait clips the top of the head —
the exact mistake the crop screen exists to prevent, so a screenshot
demonstrating it would argue against the app. This is not hypothetical: the
first run on this photograph centre-cropped and cut the crown off. Both the
harness and the CLI now place the crop at the top of the frame.

Copy it to `Fixtures/screenshot-source.jpg` and run `./Tools/screenshots.sh`.
Everything regenerates, including every number, and the numbers stay true.

### The Display P3 / sRGB matched pair

```
cd Tools/uploadablecli
swift run -c release uploadablecli pair ../../Fixtures/pexels-kooldark-19601394.jpg \
    --spec us-visa-ds160 --crop-y 0 --out ../../Fixtures/out
```

Two files with identical pixels and dimensions, one tagged sRGB and one tagged
Display P3, both inside the DS-160 band. They exist to settle by upload whether
a portal actually rejects P3 — which `SHIPPING.md` forbids the store copy from
claiming until it has been tested.

The pair needs a **real face**. A synthetic stand-in would be rejected by DS-160
for face reasons that have nothing to do with colour space, which is precisely
the confound the test is designed to remove. `--crop-y 0` matters for the same
reason: a clipped crown is itself a rejection reason.

---

## The app icon

`Assets.xcassets/AppIcon.appiconset/icon-1024.png`, wired via
`ASSETCATALOG_COMPILER_APPICON_NAME`. To swap it:

```
./Tools/set-icon.sh path/to/1024.png
```

It replaces the icon, flattens any alpha channel, and verifies the result — an
icon with alpha is rejected, and so is one with rounded corners already drawn
in. Ship a full-bleed square; iOS applies the mask.

---

## Submission, in order

1. `./Tools/generate-project.sh`
2. Re-check the specs — *Before every submission*, step 1.
3. Run the suite. It must be green.
4. Bump the version and build number in `project.yml`.
5. Archive: **Any iOS Device (arm64)**, Product → Archive.
6. Distribute → **App Store Connect** — never TestFlight Internal Only.
7. In App Store Connect: pricing Free, IAP price and availability set, age
   rating all No, privacy answers **published**, screenshots uploaded, listing
   copy pasted, review notes filled in, both URLs live.
8. Attach the build to the version, then Submit.
