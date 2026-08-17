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
- **Publish the privacy answers.** Saving them is not enough and it blocks
  submission.

## Store listing

Written at phase 5. Support and privacy pages go in `docs/` on GitHub Pages,
support email `leejiles@gmail.com`.
