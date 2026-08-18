# Notes carried forward

Decisions made during one phase that the next phase has to honour. Not a
backlog — everything here is a conclusion someone already reached, with the
reason attached, so it does not get re-litigated or quietly dropped.

---

## Phase 2 — the UI

### The Spec screen must let the user place the crop

**Required, not a refinement.** The engine centre-crops to the spec's aspect
ratio. That is the correct default and it is not going to be made cleverer —
**no face detection, ever**, for the reasons in the brief.

But centre-crop on a real portrait is frequently the wrong frame. A
4284 × 5712 photo cropped square lands as a tight head-and-shoulders shot that
clips the top of the head. The file is correct in every measurable way — right
dimensions, right byte band, right colour space, every check green — and it is
a correct file of the wrong part of the photograph. Nothing in the engine can
detect that, and nothing should try.

So the Spec screen shows the crop rectangle over the thumbnail *before* fitting,
and the user drags it. Constrained to the spec's aspect ratio, so it can only be
moved and scaled within legal shapes; the engine still receives an exact rect
and still refuses to upscale.

Two reasons this is not optional:

- Without it, Uploadable ships correct files of wrong framings and the user only finds
  out when the portal rejects them — which is precisely the failure mode the
  whole product exists to remove.
- The US Passport upload page states that the applicant crops inside the State
  Department's own tool after uploading. Every serious portal expects a human to
  place the crop. Doing it silently and centrally is us guessing at something
  the form already assumes a person will decide.

Verified against real fixtures in phase 1: quality is not the issue.
IMG_1335 at 7.9 MB down to 213 KB for DS-160 shows no visible degradation at
1:1. Framing is the issue.

### Warnings belong beside the result, never instead of it

`Fit.warnings` already carries `belowCommonMinimum` and `softerThanPreferred`.
The Done screen shows the green ticks *and* the warnings together. A warning is
never a failure — the file measurably meets the stated requirements, and Uploadable
does not get to overrule a government about its own form.

Both warnings are written about the file, not the photograph. A test enforces
that the wording never strays onto the picture; keep that true in the UI copy
too. See the language section in `SHIPPING.md`.

### Unverified presets never appear

`SpecCatalog.all` is the offered list and everything in it has been read off its
official page. `SpecCatalog.drafts` is never shown as a choice. If a draft is
ever promoted, the Spec screen still shows its verification date — that row
already exists in the design for a reason.

---

## Phase 5 — ship prep

### Three things are provisional until the user decides

Everything else is finished. These are wired with a working placeholder so the
build is never broken, and each has a one-command swap:

- **The icon.** Direction A (corner marks) in indigo is in
  `Assets.xcassets`. Four directions × three colourways were rendered at true
  home-screen size for the choice. `./Tools/set-icon.sh <1024.png>` swaps it.
- ~~**The screenshot photograph.**~~ **Done.** Pexels 19601394, free for
  commercial use, no attribution required, not AI-generated. Licence and source
  URL are in `SHIPPING.md`; the file itself is not in the repository because
  `Fixtures/` is ignored, which is why the Pexels ID is written down.
- ~~**The GitHub repository.**~~ **Done.**
  `github.com/leejiles-collab/uploadable`, public, Pages on `main` / `/docs`.
  All three pages verified live over anonymous HTTPS. URLs are in
  `SHIPPING.md`.

### The captions must never state a number

The five captions say nothing measurable — "Every requirement, met." and so on.
That is what makes the photograph swappable at the last minute: every number a
viewer sees is inside the screenshot and was produced by the engine on whatever
photo was passed in. A caption naming a size would have to be re-checked by hand
every time the source changes, and one day it would not be.

### The privacy manifest is derived, not asserted

`Support/PrivacyInfo.xcprivacy` was checked line by line against the source and
two entries were wrong — a `UserDefaults` reason code that did not account for
the App Group, and a declared API the app never calls. Both are recorded in
`SHIPPING.md` and `SCALLAPP.md` with the greps that find them. Re-run those
greps rather than trusting the file, because nothing in the toolchain will.

### The harness stays, behind `#if DEBUG`

`App/ScreenshotHarness.swift` is permanent. Store screenshots have to be
regenerated whenever the photo or the numbers change, and a pipeline that
requires editing source first is a pipeline nobody runs. It cannot exist in a
shipping binary — a launch argument that rewrites app state has no business
there — so it is compiled out of Release entirely.

### The centre crop clips the crown, and it did

The first run on the real photograph centre-cropped and cut the top of the head
off — a correct file of the wrong part of the picture, which is the failure this
whole product exists to remove, demonstrated on our own store page. Two places
now place the crop at the top of the frame instead:

- `App/ScreenshotHarness.swift`, after `select`, which leaves it centred.
- `uploadablecli --crop-y <0..1>`, new, threaded through `fit`, `report` and
  `pair`. 0 is against the top, 0.5 centred, 1 against the bottom — the same
  range of placements the app's handles allow before resizing.

The synthetic stand-in never showed this, because a synthetic face has no crown
to clip. Framing bugs need a real face to be visible at all, which is the second
reason the pair needed one.

### The matched pair is real now

`Fixtures/out/pexels-kooldark-19601394-us-visa-ds160-{srgb,displayp3}.jpg`.
Identical pixels and dimensions at 1200 × 1200, both inside the DS-160 band,
differing only in the colour tag. The synthetic pair is deleted.

`SHIPPING.md` still forbids the store copy from claiming that any portal rejects
Display P3, and **the upload test is deliberately not being run** — settling it
would mean starting a real DS-160 application to watch a validator handle a
colour profile, which is not worth doing for a sentence of marketing copy.

It is also not needed. State's own page states the requirement in words —
"in sRGB color space" — which is recorded against `usVisa` in `SpecCatalog`
with its URL and read date. Converting to sRGB is therefore correct because the
form asks for it, whether or not the validator checks. The claim the test would
support is one nothing we ship makes.

So this is closed, not outstanding. The pair stays where it is and `--crop-y`
stays in the CLI, because the cost of keeping them is nil and the experiment is
one upload away if the claim is ever actually wanted.

---

## Pre-flight (R1–R6)

### The in-app purchase was never created

Checked by API rather than assumed: the app has **0** in-app purchases. All the
StoreKit 2 code works and the paywall renders, but against an empty App Store
Connect `Product.products(for:)` returns nothing, so the button shows no price
and refuses to sell. Steps to create it are in `SHIPPING.md`.

### A Swift 6 isolation warning was hiding in HomeView

`PhotosPicker`'s label closure is not main-actor isolated, so referencing the
`isLoading` @State inside it warned — twice, in Release. `.disabled(isLoading)`
on the same view did not, because `body` itself is isolated; only the closure is
not. Fixed by reading the value on the main actor into a local and capturing that
by value. Warning today, error on a stricter toolchain, and unsound either way.

### The harness is confirmed absent from Release behaviourally

The Release build was installed and launched with `--screen=done`, the exact
argument the Debug build obeys, and stayed on Home. That is the check — grepping
an optimised Swift binary for string literals proves nothing, which is already a
recorded trap.

---

## Build 1 crashed on Save to Photos

`PHPhotoLibrary.performChanges` takes a block that is **not** `@Sendable` in the
SDK, so the closure written inside `DoneView` — a `@MainActor` context — quietly
inherited main-actor isolation. Photos then ran it on
`com.apple.PHPhotoLibrary.changes`, Swift 6 checked the inherited claim, and the
process trapped.

The work now lives in `PhotosLibrary`, a `nonisolated` enum in UploadableKit.
That removes the inference at source, which is the only fix that stays fixed —
`@Sendable` at the call site would work until someone moved the code back.

**Audit result: this was the only instance.** There is no `assumeIsolated`
anywhere in the codebase, and grepping for one would have found nothing. Every
other framework closure was checked by compiler probe (see `SCALLAPP.md`);
`NSItemProvider.loadFileRepresentation` in the share extension is annotated
`@Sendable` in the SDK and does not inherit, so the extension's import path was
never at risk.

**`Tools/uitests.sh` exists because of this.** It grants `photos-add` up front
and stages the fixtures, then runs the UI tests. Two things had to be true before
the new test could fail for the right reason:

- Permission must be pre-granted, or the alert stalls the tap and a real crash
  looks like a timeout.
- The export meter must be reset (`--reset-exports`, DEBUG only), or the paywall
  intercepts the tap and the Photos code never runs. The first version of this
  test "failed" that way and proved nothing.

The test was written against the unfixed code first and reproduced the trap
exactly, with the simulator's crash log naming
`closure #1 in closure #1 in DoneView.saveToPhotos()`. A regression test that has
never been seen to fail is a guess.
