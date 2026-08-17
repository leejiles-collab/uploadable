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
