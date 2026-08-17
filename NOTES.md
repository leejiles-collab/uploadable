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
- **The screenshot photograph.** `Fixtures/screenshot-source.jpg` is a synthetic
  placeholder. Licensed stock with a model release goes in the same path and
  `./Tools/screenshots.sh` regenerates all ten files, numbers included. Required
  properties are in `SHIPPING.md` under *What the source photo has to be*.
- **The GitHub repository.** `docs/` is written and ready; there is no remote
  yet. Pages needs a **public** repo unless the account is on a paid plan, and
  Apple must be able to reach both URLs anonymously.

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
