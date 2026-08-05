# Stitching — seam inspector (manual QC + fix)

Companion to [`plan_stitching.md`](plan_stitching.md). Builds on the measured edge graph
(`measureAllPairs`), the global solvers, the sidecar (`saveProject`/`loadProject`) and the pair
composite rendering (`imfuse` falsecolor, proven in `previewFeatureMatch`).

**Status: IMPLEMENTED and verified** — all phases (A: headless core, B: inspector shell,
C: interactive fixing, D: re-fuse integration) done. Controller `@StitchingInspector` +
`views\StitchingInspectorGUI.mlapp`; launched from Stitching's `inspectSeamsBtn` (enabled once
edges+positions exist).

## The problem it solves

Automatic stitching fails two ways: **rejected edges** (quality below threshold — solver already
reports `nPruned`/`disconnectedTiles`) and **confidently wrong edges** (phase-corr/RANSAC locks
onto a repetitive pattern one period off, HIGH quality). On a chain-like graph (sparse overlaps,
no loops) the solver residual is exactly zero for the second case — it cannot see the error.

**Load-bearing decision:** rank by a pixel-based **seam score** (masked NCC of the two overlap
strips re-read at the SOLVED positions), not solver residual. A wrong-but-confident edge scores
poorly at the solved placement even when the residual is zero. The alignment chip in the main
Stitching window folds this in too (`refreshQualityChip`, see `plan_stitching.md`'s pitfalls list).

## Workflow

Ranked seam table (worst first) + mini-map (tiles/edges tinted by seam score, low-res fused preview
once tiles are built) + pair view (complete tile pair at the current solved offset — not just the
overlap strip, so large corrections stay tractable; falsecolor/flicker/checkerboard/difference
overlays). Per seam: **Confirm** / **Exclude** (toggle — springs take over, coarse fix) / drag or
arrow-nudge / **Shift+click-to-correlate** (human picks WHERE, `localCorrelate` finds EXACTLY,
snaps only if confident) / **two-click landmark match** (for offsets beyond any search radius —
click the same spot in each tile's full view, click difference = coarse offset + NCC refine) /
**undo** (`Z`, restores the original automatic edge). **Re-solve** re-runs the global solve with
user edges dominating; the table re-ranks. No Fuse/Save button here — see below.

## Trust model (how user fixes steer the global solve)

Edge fields: `.source` (`'auto'`|`'user'`|`'confirmed'`), `.seamScore`. Solver option
`userEdgeWeight` (default 5.0, well above any quality ≤1) — user edges are never pruned by the
quality threshold and never demoted to springs; two contradictory user fixes average rather than
fight. `measureAllPairs` preserves `source='user'` edges on a re-measure (warns instead of
silently discarding a QC session).

## Fix XY vs Fix Z (`fixModeDropdown`)

Settled after five rejected interpretations (stepping a tile's slice, any 3D pair, auto-zoom,
cross-layer-edges-only) — the user's actual model, confirmed by explicit choice: **each mosaic
OUTPUT SLICE is a "layer"**. Fix Z shows one tile at consecutive output slices z-1 (cyan) vs z
(magenta); a fix shifts THAT SLICE AND EVERY SLICE ABOVE IT across the whole mosaic (slices below
stay put — "they are all interconnected"). This lives OUTSIDE the tile/solver model:
`Stitching.zSliceFixes` ([z dy dx] rows, cumulative) → `planCanvas` grows the canvas and shifts
every tile on/above that slice at fuse time; no re-solve involved. Fix XY is the ordinary
per-seam in-plane offset (drag/Shift+click/two-click), unrelated to `zSliceFixes`.

A cross-layer (`'z'`-direction) edge's XY offset is still fixed through the ordinary Fix XY path;
its correction propagates through the solver to the whole layer above (pinned by test
`zBoundaryFix_shiftsAllLayersAbove`).

## Keyboard — never mutates alignment

**Rule, load-bearing:** the keyboard never moves a tile. `Enter` confirm+next, `X` exclude,
`Space` flicker, `N`/`P` navigate, `Z` undo, `F` fit view. `Q`/`W` and `Up`/`Down` browse Z slices
in BOTH fix modes (view-only); `Left`/`Right` nudge X only (1 px, `Shift` 10, `Ctrl` 0.25) — all
positional edits happen by mouse (drag / Shift+click / two-click). See [[ux-navigation-keys]]
(memory) for the incident that established this rule project-wide.

## Where it lives

`mib\+controllers\@StitchingInspector\` + `mib\+views\StitchingInspectorGUI.mlapp` — sibling child
controller (not a mode inside `@Stitching`), sharing handles to the parent's
`layout/edges/positions/tforms` (mutated in place; `SeamsUpdated` event syncs the parent's
widgets). No BatchOpt/batch mode — inherently interactive.
`controllers.StitchingInspector(mibModel, stitching, struct('createView', false))` builds the
inspector headlessly (scored/ranked, no window) for controller-level tests.

**One tile reader per session, built by `obj.tileReader()`** — never
`utils.stitch.makeTileReader` directly. Four call sites used to build their own with no arguments,
which cost two things: separate LRU caches (so the pair view could not reuse what scoring had just
read) and, worse, **no intensity correction** — with a correction selected the inspector reviewed
and SCORED different pixels from the ones the mosaic is measured and fused on, the exact split
`makeTileReader` exists to prevent. `obj.tilesAreResident(idx)` (from `makeTileReader`'s second
output) tells a free read from one that will stall on disk, which is what gates the pair view's
"Reading tile..." dialog: a whole-tile decode is seconds on a large mosaic, but `Q`/`W` slice
browsing re-renders constantly and must not flash a dialog every keypress.

## Fuse / persist — Stitch is the single entry point

The inspector has **no Re-fuse and no Save-project button** (removed — they were thin delegations
to the parent's `stitchBtn_Callback`/`saveProjectBtn_Callback`, and the inspector mutates the
parent's `edges`/`positions` in place, so the parent's buttons already see every fix with no
hand-off). The one asymmetry to preserve: `stitchBtn_Callback` must run any pending inspector
re-solve (`resolvePending` — set by deferred/auto-off fixes, undo, exclude; a DEPENDENT alias of
`Stitching.resolvePending`, where the flag actually lives, because the debt belongs to the mosaic
and not to this window: while it was stored on the inspector, closing that window dropped it, the
chip went quiet and Stitch fused the pre-fix placement) BEFORE fusing, or it
silently fuses stale positions. Inspector bottom row: Confirm / Exclude / Re-solve / Close.

## mlapp widgets

Full spec (handles, classes, defaults, Phase C additions) in
[`mlapp_widgets.md`](mlapp_widgets.md#stitchinginspectorguimlapp-seam-inspector--plan_inspectormd-phases-bc).
`excludeBtn` must be an App Designer **State Button** (push-button re-include was invisible); the
controller drives its pressed/color/text state from the edge, never reads it back.

## Verification

`tests\utils\StitchInspectorTest.m` (scoreSeams/localCorrelate/solver weighting/sidecar v2
round-trip) + `tests\controllers\StitchingInspectorControllerTest.m` (headless controller:
ranking, applyUserFix, undo, exclude/re-solve, Fix-Z per-slice corrections). GUI smoke:
[`smoke_tests.md`](smoke_tests.md) test 12 (sabotaged chain — full worst-first workflow) and
test 3 (Fix Z on a 3D dataset).
