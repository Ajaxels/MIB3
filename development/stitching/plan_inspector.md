# Stitching — seam inspector (manual QC + fix when automatic stitching fails)

Design for Phase 4 of [`plan_stitching.md`](plan_stitching.md).

**Status (2026-07-16): Phase A (headless core) IMPLEMENTED and verified** —
`utils.stitch.scoreSeams` (NCC at solved positions + worst-first ranking, NaN for
no-overlap placements), `utils.stitch.localCorrelate` (click-seeded `normxcorr2`
with peak/prominence confidence gate — refuses periodic content — and subpixel
parabolic refinement; unconfident results never move the offset),
edge `.source`/`.seamScore` provenance in `measureAllPairs` (+`preserveEdges`
option: user fixes survive a re-measure), `userEdgeWeight` (default 5.0, never
pruned) in BOTH solvers, sidecar `schemaVersion 2` with v1 back-compat.
Tests: new `tests\utils\StitchInspectorTest.m`; StitchCoreTest 36/36 and
StitchLayoutTest 25/25 regression-clean.

**Status (2026-07-16): Phase B (inspector shell) IMPLEMENTED** — controller
`@StitchingInspector` (15 files): ranked seam table with score-coloured rows,
clickable mini-map (tiles coloured by worst incident seam), pair view with
Falsecolor/Flicker/Checkerboard/Difference overlays, Confirm/Exclude, Re-solve
(delegates to the parent's `optimizePositions_Callback`, then re-scores +
re-ranks), Save-project delegation, keyboard loop (`Space` flicker, `Enter`
confirm+next, `X` exclude, `N`/`P` navigate). Launched from Stitching's
`inspectSeamsBtn` (guarded; enabled when edges+positions exist); the parent's
`layout/edges/positions/tforms` are the single source of truth (inspector
mutates in place, `SeamsUpdated` event syncs the parent's widgets; parent
closes the inspector with itself; `dataValid` guards against a layout rebuild
mid-session). New smoke dataset `stitch_smoke_sabotage`: honest measurement of
a 1×3 chain + a **+24 px / quality 0.95 corruption injected into the 2-3
edge**, saved as a project file (image-level sabotage was tried and defeated:
phase correlation whitens the spectrum, so even a 55% stripe band with a 12 px
phase shift is measured correctly — the corrupted-edge project reproduces the
failure state itself). Headless milestone verified: corruption residual-
invisible (RMSE 0.009 while tile 3 is 24 px off), seam score 0.09 vs 1.00
ranks it first, exclude + re-solve recovers to the ~5 px cut jitter (the seam
score then only IMPROVES — exclusion is coarse; the true fix is Phase C).
Permanent test `sabotagedChain_caughtRankedAndRecovered` (zero-jitter chain →
exact recovery); StitchInspectorTest **11/11**.
**Status (2026-07-17): Phase C (interactive fixing) IMPLEMENTED** — every fix
funnels through `applyUserFix` (one auto-edge backup per seam for undo, then
`source='user'` / `quality=1` / `tform=[]`, auto re-solve unless deferred or
`autoResolveCheckbox` off). Tools: **pair-view mouse** (`pairViewButtonDown`
state machine: **Shift+hover** shows the ROI box under the cursor
(`pairViewMotion`, click-transparent yellow box; Shift tracked via
key press/release, crosshair pointer) and **Shift+click** → `correlateAtPoint`
→ `utils.stitch.localCorrelate` with `roiSizeSpinner`/`searchRadiusSpinner`
settings, snap only when confident; plain click = deliberate no-op so stray
clicks never move tiles; drag → live two-layer overlay — grey tile
*i* + 50%-alpha tile *j* moved via `XData`/`YData`, full pair at display
scale, no per-event `imfuse` — release applies the delta); **arrow nudges** (1 px,
`Shift` 10, `Ctrl` 0.25; event's own `Modifier` list, re-solve deferred to
`WindowKeyReleaseFcn` so held keys nudge smoothly); **two-click landmark
match** (`twoClickBtn`: side-by-side full tiles downsampled >1024 px, click
difference = coarse offset, scale-aware small-radius refine, unconfident
refine falls back to the coarse offset — it is the user's explicit statement);
**auto-suggest** (`utils.stitch.suggestFix`: alternate estimator + widened
search on a 2-tile sub-layout through the ordinary `measureAllPairs` path,
seam-NCC verified, offered via quest dialog, never auto-applied); **undo**
(`Z`/`undoFixBtn` restores the backed-up automatic edge). User-fixed edges
display at their fixed offset in the pair view (`currentOffsetYX`) so a fix is
visible before the re-solve. Milestone verified in
`clickFix_recoversSabotagedChainWithinOnePixel`: corrupted chain edge fixed
via one click → all tiles within 1 px of ground truth; plus
`suggestFix_recoversCorruptedEdge` and `suggestFix_flatOverlapNotUsable`.
StitchInspectorTest **14/14**, StitchCoreTest 36/36.
**Removed (2026-07-17, user decision): auto-suggest** — `suggestBtn`,
`suggestBtn_Callback`, `utils.stitch.suggestFix` and its two tests deleted:
Shift+click-to-correlate covers the same need interactively (the user picks
WHERE, the machine finds EXACTLY), so a dialog-driven re-measure was redundant
GUI surface. Recoverable from git history if a batch variant is ever wanted.
**Status (2026-07-17): Phase D (re-fuse integration & polish) IMPLEMENTED** —
**Re-fuse** (`refuseBtn_Callback`) delegates the full fuse to the parent's
`stitchBtn_Callback` (both output modes, cached positions reused); a new
`resolvePending` flag (set by deferred/auto-off fixes, undo and exclude,
cleared by `resolveBtn_Callback`) makes Re-fuse run the pending re-solve
FIRST so it never fuses stale positions. **Mini-map fused preview**:
`ensureTileThumbs` lazily builds jointly-normalised per-tile thumbnails once
(shared LRU reader, mosaic scaled to ~1000 px, skipped above ~1.5 G total
full-res pixels or on any read error), and `renderMiniMap` composites them at
the CURRENT solved positions behind the score patches on every redraw (patch
alpha drops 0.85 → 0.25 so the image reads through). **dz nudge**:
`PgUp`/`PgDn` ±1 slice (`Shift` ±5) on 3D/cross-layer pairs
(`pairHasDepth`), through the same `applyUserFix` path ([dy dx dz] was
already supported) with the re-solve deferred to key release; `currentDz`
mirrors the user-edge display convention; the offset label shows the live dz
next to the seam score and the `dzHint` ("pixels prefer dz±k") from the
Z-aware `scoreSeams`. Earlier same-day additions folded in: pair-view wheel
zoom + `F`/`fitViewBtn` fit, per-slice slab seam scoring + dz-scan hints.
**Partial (dirty-region) BigData re-fuse remains a future optimisation — v1
always re-fuses the full canvas** (the placement delta gives the dirty region
directly; pyramid levels must propagate it block-aligned per level).
**mlapp to-do (user): build `views\StitchingInspectorGUI.mlapp`** — full widget
spec in [`mlapp_widgets.md`](mlapp_widgets.md) (now incl. the Phase C row:
`roiSizeSpinner`, `searchRadiusSpinner`, `suggestBtn`, `twoClickBtn`,
`undoFixBtn`, `autoResolveCheckbox`, plus Phase D `refuseBtn` and `fitViewBtn`
— all controller-guarded), plus `inspectSeamsBtn` in the main StitchingGUI.
Companion to [`plan_transforms.md`](plan_transforms.md); builds on the measured edge
graph (`measureAllPairs`), the global solvers (`solveGlobalLeastSquares` /
`solveGlobalAffine`), the sidecar (`saveProject`/`loadProject`) and the pair-composite
rendering already proven in `previewFeatureMatch` (imfuse falsecolor + overlays).

## The problem

Automatic stitching fails in two distinct ways, and they need different detection:

1. **Rejected edges** (quality below threshold, featureless overlap) — the tile is held
   near nominal by springs and is *visibly* misplaced. The solver already reports these
   (`nPruned`, `disconnectedTiles`).
2. **Confidently wrong edges** — RANSAC/phase-corr locked onto a repetitive pattern one
   period off, with HIGH quality. On a redundant graph the loop inconsistency shows up
   in the solver residuals; **on a chain-like graph (2xN strips, sparse overlaps) the
   residuals are exactly zero and the solve is silently wrong.** Solver residuals alone
   cannot rank these.

**Load-bearing decision — rank by a pixel-based *seam score*, not by solver residual.**
After every solve, re-read each valid edge's overlap strips at the SOLVED positions and
compute their masked NCC (precedent: `estimateOverlap` already NCC-verifies candidate
peaks). A wrong-but-confident edge scores poorly at the solved placement even when the
residual is zero. Ranking = seam score ascending, residual as secondary key, pruned /
disconnected tiles always on top.

## Workflow (user's view)

1. After *Optimize positions* (or *Load project*), press **Inspect & fix…** — enabled
   whenever `edges` + `positions` exist. Opens the inspector as a child controller.
2. Left side: **ranked seam table** (worst first) + a **mini-map** of the layout with
   tiles/edges coloured by seam score (green→red). Click either to open a pair.
3. Right side: **pair view** — the COMPLETE tile pair composited at the current solved
   offset (downsampled >~1400 px; axes stay in full-res tile-i coordinates so click/
   drag maths is scale-free). *Revised 2026-07-17 from overlap-strips-only after user
   feedback: full context makes large corrections tractable.* Overlay modes:
   falsecolor (tile i cyan + tile j magenta → aligned structures WHITE), **flicker**
   (spacebar toggles A/B — the classic registration-QC view, often easier for the eye
   than falsecolor), checkerboard, difference.
4. Per pair the user does ONE of:
   - **Confirm** — seam is fine; mark reviewed, jump to next worst.
   - **Nudge / drag** — arrow keys (1 px; Shift = 10 px; Ctrl = 0.25 px subpixel) or
     mouse-drag tile *j*'s overlay; composite follows live.
   - **Click-to-correlate** (the "human picks WHERE, machine finds EXACTLY" tool) —
     click a distinctive spot in the overlap; a small ROI (default 128 px, configurable)
     around the click is cut from tile *i* and NCC-matched against tile *j* within a
     search radius (default ±64 px) of the current offset; the pair snaps to the peak
     and the peak score is shown. Weak peak → warn, don't snap.
   - **Two-click match** — when the current offset is hopeless (beyond any search
     radius): click the same landmark once in tile *i*'s view and once in tile *j*'s
     view (side-by-side sub-mode); the click difference IS the coarse offset, then a
     ±8 px NCC refine sharpens it. Covers the "tile is a whole period off" case.
   - **Exclude** — mark the edge invalid (springs take over for that constraint).
   - **Auto-suggest** — the inspector tries the *other* estimator (feature-based ↔
     phase corr) and a widened search on this pair in the background and offers its
     result as a one-click "Suggested: shift [dy dx], NCC 0.91 — Apply?" chip.
5. **Re-solve** (button, or auto after each fix — toggle): global solve reruns with the
   user edges dominating (below), table re-ranks, mini-map recolours. The user works
   worst-first until the top of the table is green.
6. **Re-fuse** → hands the corrected positions back to the Stitching window (or fuses
   directly). **Save project** persists all fixes.

Keyboard-first: `Enter` confirm+next, `X` exclude, `Space` flicker, arrows nudge,
`N`/`P` next/prev, `Z` undo-fix (restore the automatic measurement).

## Trust model — how user fixes steer the global solve

New edge fields (sidecar `schemaVersion: 2`):

- `.source` — `'auto'` (default) | `'user'` (drag / click-corr / two-click) |
  `'confirmed'` (reviewed, unchanged).
- `.seamScore` — the NCC at the last solved placement (also useful in the sidecar for
  later audit).
- User edges: `measured`/`tform` replaced by the user's offset, `quality = 1`,
  `valid = true`.

Solver additions (`solveGlobalLeastSquares` + `solveGlobalAffine` options):

- `.userEdgeWeight` (default `5.0`) — weight for `source='user'` rows, well above any
  quality (≤1), so a user fix dominates conflicting auto edges without being an
  absolute pin (two contradictory user fixes then average instead of fighting).
- User edges are **never pruned** by the quality threshold and never demoted to
  springs.

Re-measure semantics: `measureAllPairs` must **preserve user edges** — on a re-measure
it overwrites only `source='auto'` edges and warns if user fixes exist ("N user-fixed
seams kept — Reset fixes to re-measure everything"). Without this, one click on
*Measure overlaps* silently throws away the QC session.

Undo: the inspector keeps the original auto edge per fix (`.autoBackup` in-memory, not
persisted) so `Z` restores it; a "Reset all fixes" button clears every user edge.

## Where it lives

`mib\+controllers\@StitchingInspector\` + `mib\+views\StitchingInspectorGUI.mlapp` — a
sibling child controller, NOT a mode inside `@Stitching`:

- launched from Stitching (`inspectSeamsBtn`) with SHARED handles to
  `layout/edges/positions/tforms` (documented: inspector mutates them in place);
- or launched standalone on a `.mibstitch.json` (ribbon dropdown item later) — the
  sidecar carries everything needed, including tile paths;
- notifies `SeamsUpdated` (custom event); the Stitching controller listens and
  refreshes its status/chip, keeping one source of truth for the pipeline stage.
- No BatchOpt / batch mode — this is inherently interactive. `showWaitbar` only.

Distinction from the Phase-3 edit-layout drag (which edits NOMINAL positions before
measuring): the inspector edits the MEASURED/SOLVED stage after. Keep both, document
the difference in the user docs ("rough placement" vs "seam fixing").

## New computational core (`mib\+utils\+stitch\`, headless-testable)

| File | Purpose |
|------|---------|
| `scoreSeams.m` | For every valid edge: read the two overlap strips at the SOLVED positions (reuse `makeTileReader` + `computeOverlapRegion` maths on solved, not nominal, origins), masked NCC → `edges(k).seamScore`. Downsample strips > ~1k px for speed. Also returns the ranking order (score asc, pruned/disconnected first). |
| `localCorrelate.m` | The click tool: `(tileA, tileB, clickXY, currentOffsetYX, options)` → cut `roiSize` patch around the click from A, `normxcorr2` against the B neighbourhood (`searchRadius`), return `[dy dx]` + peak NCC + a `confident` flag (peak height + peak-to-second-peak ratio, like `pairwiseShift` quality). Full-res inside the ROI regardless of display downsampling. |
| `suggestFix.m` | Auto-suggest: re-measure ONE pair with the alternate estimator and widened search (`expandPx` ↑, or feature-based full-tile), score the result with `localCorrelate`-style NCC, return candidate + score. |

Solver/measure changes: `userEdgeWeight` + never-prune rule (both solvers), user-edge
preservation in `measureAllPairs`, `.source`/`.seamScore` in the edge template and the
sidecar (round-trip + v1 back-compat: missing fields default to `'auto'`/`[]`).

## Pair-view rendering (performance notes)

- Read ONLY the overlap strips (+margin, e.g. 25% of strip) via the existing
  PixelRegion fast path; LRU cache shared with the rest of the tool.
- Composite: `imfuse` falsecolor for the static view (same convention as
  `previewFeatureMatch`: i = green, j = magenta, grey = agreement).
- During a DRAG, do not recompute imfuse per mouse event: render tile *i* as the
  background image and tile *j* as a second `image` object with `AlphaData 0.5` whose
  `XData`/`YData` shift with the pointer; recompute the proper falsecolor on release.
- Flicker mode: two stacked images, `Visible` toggled — instant.
- Non-translation solves: warp tile *j*'s strip by the relative transform
  (`tforms{j}⁻¹∘tforms{i}` restricted to the strip) BEFORE compositing, so the user
  only ever adjusts the residual translation. Rotation/scale hand-editing is out of
  scope (Phase 2 transforms are solved well; the failure mode being fixed here is
  translation-scale misplacement).
- 3D tiles: strips are mean-projections over depth (like `measureAllPairs`); dz
  fixing via `PgUp/PgDn` (integer slice nudge) is listed as a later step, 2D-first.

## Fused-preview & re-fuse

- **Mini-map** = layout rectangles coloured by per-tile worst seam score; cheap, always
  current. Optional low-res fused thumbnail (place `imresize(tile, 1/16)` at
  `placement/16` with Overwrite) behind the rectangles — good enough to SEE a gross
  misplacement, costs one pass over the LRU-cached tiles.
- **Re-fuse**: in-memory jobs simply re-run `fuseInMemory` (seconds). BigData/zarr jobs
  re-run `fuseStreaming` fully in v1; **partial re-fuse** (rewrite only chunks whose
  contributing tiles moved — the placement delta gives the dirty region directly) is a
  listed optimisation, not v1. Warn about pyramid levels: dirty-region logic must
  propagate up the pyramid (block-aligned at each level).

## mlapp widgets (StitchingInspectorGUI)

Non-BatchOpt tool → descriptive lowerCamel handles throughout (per naming rule):

`seamTable` (uitable: rank, i↔j, dir, seamScore, residual, quality, source, reviewed),
`miniMapAxes`, `pairAxes`, `overlayModeDropdown` (Falsecolor/Flicker/Checkerboard/
Difference), `roiSizeSpinner` (32–512, default 128), `searchRadiusSpinner` (8–256,
default 64), `confirmBtn`, `excludeBtn`, `suggestBtn`, `undoFixBtn`, `resolveBtn`,
`autoResolveCheckbox`, `refuseBtn`, `saveProjectBtn`, `statusLabel`, plus the offset
readout label (`offsetLabel`: current [dy dx] vs auto-measured). Keyboard shortcuts via
`WindowKeyPressFcn` on the child figure (child-dialog shortcut conventions:
`development/guides/conversion_ui.md`).

## Phasing

1. **A — core plumbing (headless):** `scoreSeams`, `localCorrelate`, edge
   `.source`/`.seamScore`, solver `userEdgeWeight` + never-prune, `measureAllPairs`
   user-edge preservation, sidecar v2 round-trip (+v1 back-compat). Unit tests for all
   of it. *No GUI yet — everything exercisable from tests.*
2. **B — inspector shell:** controller + mlapp, ranked table + mini-map + pair view
   (falsecolor/flicker), navigation, Confirm/Exclude, Re-solve, handoff event back to
   Stitching, sidecar save. Milestone: open a sabotaged dataset, the corrupted edge
   ranks first, excluding it + re-solve recovers the layout (springs).
3. **C — interactive fixing:** drag + keyboard nudges with live overlay,
   click-to-correlate, two-click match, auto-suggest, undo. Milestone: the corrupted
   edge is FIXED (not just excluded) via one click near a landmark; re-solve lands all
   tiles within 1 px of ground truth.
4. **D — re-fuse integration & polish:** Re-fuse button (full re-fuse both output
   modes), low-res fused thumbnail under the mini-map, dz nudge for 3D pairs, partial
   re-fuse for BigData (optimisation, separate milestone).

Model recommendation: A is solver/metric work → Opus-class; B/C are
controller+mlapp pattern-following → Sonnet-class, except the drag-rendering
performance path (C) if it misbehaves; D's partial re-fuse → Opus-class.

## Verification

- Unit (`StitchCoreTest` or new `StitchInspectorTest`): `scoreSeams` high on a correct
  chop, low on a deliberately shifted edge; `localCorrelate` recovers a known offset
  from a clicked ROI and reports low confidence on flat texture; solver: one user edge
  (weight 5) beats a contradictory auto edge (quality 1) but two contradictory user
  edges average; `measureAllPairs` re-measure preserves `source='user'` rows; sidecar
  v2 round-trip + v1 file loads with defaulted fields.
- New smoke generator `stitch_smoke_sabotage`: 3×3 grid with one **repetitive-texture
  overlap** (striped pattern, period ~24 px) that phase correlation locks onto one
  period off with high quality — the "confidently wrong" case. Checklist: inspector
  ranks that seam first (seam score catches it, residual ~0 on the chain), click-fix
  snaps it, re-solve + re-fuse gives continuous lines.
- GUI smoke additions to `smoke_tests.md`: full worst-first pass over the sabotage set;
  keyboard-only session; BigData re-fuse round-trip.

## Open questions (decide during implementation, defaults proposed)

- Auto re-solve after every fix (proposed: ON — the solve is milliseconds at these
  sizes) vs explicit button for huge graphs (auto-off above ~500 edges).
- Should *Confirm* bump the edge weight too? Proposed: no — confirmation is bookkeeping
  (`source='confirmed'`), weights stay quality-based.
- Seam-score threshold that counts as "reviewed enough" to colour the chip green —
  propose reusing the existing rating bands on `min(seamScore)` rather than inventing
  new ones.
