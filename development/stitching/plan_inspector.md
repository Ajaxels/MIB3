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

## The pair view fills its grid cell

`axis image` gives 1:1 pixels and *tight* limits, so a tall pair (two tiles stacked vertically)
drew as a narrow column using ~45% of the width reserved for `pairAxes` in `mainGridLayout` -
measured on the real GUI - and zooming in only made the column taller.
`StitchingInspector.pairAxesFillLimits` grows the SHORTER side of the requested window until its
aspect matches `pairAxes.InnerPosition`, so the composite uses the whole cell. The extra span is
context around the tiles: never a distortion (`DataAspectRatio` stays `[1 1 1]`) and never a crop
(the window only ever grows). `InnerPosition` is the region *available* for the plot box - it
excludes the title but is **not** shrunk by the aspect letterbox, so reading it is not circular.

Applied at every place that writes the limits: `renderPairView` (fit and restored-zoom),
`fitView_Callback`, `scrollWheel_Callback`, the drag preview and the two-click side-by-side.

Two consequences in `scrollWheel_Callback`, both load-bearing:

- the snap-back-to-fit test is `&&`, not `||` - the fitted window is deliberately wider than the
  content in one direction, so an OR snapped on the first click of the wheel;
- the border clamp is left as it was: when the window is wider than the content both correction
  terms fire and cancel down to "centre on the content", which is exactly what that direction wants.

### The zoom level survives a seam change

Selecting another seam (table click, `Up`/`Down`, `Enter`, a mini-map jump) **keeps the
magnification** and re-anchors only the CENTRE, onto the new pair's overlap - the part being judged.
Reviewing a mosaic means looking at every seam at the same magnification, and re-zooming after each
`Enter` was the most repetitive thing in a pass. The centre has to be recomputed rather than carried
because `pairAxes` is in tile-*i* full-res pixels and those coordinates mean something different for
every pair; a carried span at least as wide as the new union in both directions just fits instead
(`renderPairView/carriedZoomOnNewSeam`). `pairZoom.edgeIdx` is rewritten as part of this, so only
`F` (`fitView_Callback`) and a fix-mode switch still reset to fit.

**A window resize does not re-fill** (the figure's `SizeChangedFcn` never fires while
`AutoResizeChildren` is `'on'`, and with it off the callback reads a stale `InnerPosition` - the
grid has not relaid out yet). The next render, wheel zoom or `F` picks the new shape up.

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
`Space` flicker, `Up`/`Down` navigate the seam ranking, `Z` undo, `F` fit view. `Q`/`W` browse Z
slices in BOTH fix modes (view-only). There is NO keyboard nudge at all — every positional edit
happens by mouse (drag / Shift+click / two-click). See [[ux-navigation-keys]] (memory) for the
incident that established this rule project-wide.

**The arrows walk the seam TABLE, not the stack** (changed 2026-08-06; `N`/`P` retired, and the
arrows no longer browse Z). The left half of the window is a ranked list, and arrows over a list is
the stronger convention — it also agrees with what the focused `uitable` does with `Down` on its
own, which the old binding contradicted. This is a deliberate DIVERGENCE from the main MIB window,
where the arrows browse slices; `Q`/`W` is the key pair the two windows still share, so slice
browsing keeps a common binding while the arrows follow whatever the window's primary list is.

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

## Tile order (Overwrite drawing order) and the falsecolor colours

Added 2026-09-28 at the user's request, after re-exposure damage made "which tile wins an overlap" a
real choice. `Stitching.tileStack` ([1 x N], bottom first, `[]` = default) is edited from the pair
view's **right-click menu** (a submenu per tile of the seam on screen, each with move to top / up /
down / to bottom - the entries name the tile, so nothing is implicit; `tileOrder_Callback`), used by
every fuser, saved as `project.tileStack`, and cleared with the layout.

- **It is a real `ContextMenu`** (`obj.tileOrderMenu`, created in `addCallbacks`, set on `pairAxes`
  AND on every image `renderPairView` draws - images do not inherit it), filled by
  `fillTileOrderMenu` in its `ContextMenuOpeningFcn`. **Opening it by hand does not work**: the first
  version called `open(menu, x, y)` from the right-button-up callback; verified with real OS mouse
  events (java.awt.Robot + screen capture) that the menu is built and opened but never appears -
  the window's own right-click handling dismisses it. A synthetic call of the callbacks passed,
  which is why it shipped broken once: only a real click exercises this.
- **Right DRAG still pans.** The native menu opens on the right button RELEASE (Windows), after the
  pan; `pairViewButtonDown` sets `rightDragMoved` once the press moved >= 3 screen px, and
  `fillTileOrderMenu` then leaves the menu EMPTY, which keeps it closed. The flag is reset on read
  (a right-click on the axes background never reaches `pairViewButtonDown`). Unverified on a real
  pan: an empty menu might flash; if it does, that is the place to look.
- First built as a dropdown above `pairAxes` (would have needed an mlapp edit); the menu needs none.
- **`Preview final` overlay**: the pair fused the way Stitch will (`previewFusedPair` mirrors
  `fuseSliceComposite` at display scale: the Stitching window's `BlendMode` - Feather weights from
  `blendWeights` on the downsampled tiles - the drawing order, `CanvasColor` for the uncovered
  frame). The way to judge which tile belongs on top.

- **One function decides the order**: `utils.stitch.tileDrawOrder` (explicit stack > re-exposure
  damage default [first imaged on top] > index order). Both `fuseSliceComposite` and
  `StitchingInspector.currentTileStack` call it, so the tile coloured "on top" is the tile Stitch keeps.
- **The first move freezes the order in force**, then edits it - the damage default can no longer
  shift under a choice the user made.
- **Up/down step past the nearest tile that OVERLAPS the moved one** (`utils.stitch.moveInTileStack`);
  stepping past a non-overlapping tile changes no pixel. Moves that would change nothing are greyed
  out (moveInTileStack returns the stack unchanged for them).
- **Magenta (or red) = the tile on top**, no longer "tile j". A drag still moves tile *j*, so the
  title now ends `| drag moves tile N`. Fix Z boundary view: slice z takes the top colour; the menu
  does not open there (both images are one tile), nor while a two-click match is armed.
- `Falsecolor (green/red)`: R = top, G = bottom, B = 0 -> aligned structure yellow. The cyan/magenta
  composite is R = top, G = bottom, B = max(both) -> white.
- The fusers' option structs are built by hand in three places (`fuseStreaming` chunk path and its
  `streamViaSaver`, `fuseToFiles`), each of which had to be taught `tileStack` - `fuseInMemory` and
  `StitchSliceProvider` pass their whole options through.

## Sticky dialog settings (`sessionSettings.stitchingInspector`)

Overlay mode, Fix mode, ROI size, search radius and Auto re-solve are written on close
(`storeSessionSettings`, from `closeWindow`) and restored on open (`restoreSessionSettings`, BEFORE
the first ranking - the Fix mode decides which seams the table lists), mirroring the Stitching
dialog's `sessionSettings.stitching`. One field table (`inspectorSessionFields`, local to the
classdef) serves both. First opening of a session = mlapp/addCallbacks defaults, i.e. overlay
`Falsecolor (cyan/magenta)`. Values the widget would reject (unknown item, spinner out of limits) are
skipped. **Fix Z is restored only when a tile has Z slices** - on a 2D mosaic it would open on the
"Fix Z needs Z slices" dialog; when restored, the constructor runs the dropdown's own handler so a
single-layer Z-stack still lands on a usable seam. Seam, zoom and browsed slice are review state, not
settings, and are not carried over.

## mlapp widgets

Full spec (handles, classes, defaults, Phase C additions) in
[`mlapp_widgets.md`](mlapp_widgets.md#stitchinginspectorguimlapp-seam-inspector--plan_inspectormd-phases-bc).
`excludeBtn` must be an App Designer **State Button** (push-button re-include was invisible); the
controller drives its pressed/color/text state from the edge, never reads it back.

## Verification

`tests\utils\StitchInspectorTest.m` (scoreSeams/localCorrelate/solver weighting/sidecar v2
round-trip) + `tests\controllers\StitchingInspectorControllerTest.m` (headless controller:
ranking, applyUserFix, undo, exclude/re-solve, Fix-Z per-slice corrections, tile-order moves).
Tile order core: `StitchCoreTest` (tileDrawOrder priority + rejection of foreign stacks,
moveInTileStack skipping non-overlapping tiles, Overwrite following the stack in memory AND
streamed, sidecar round-trip). GUI smoke:
[`smoke_tests.md`](smoke_tests.md) test 12 (sabotaged chain — full worst-first workflow) and
test 3 (Fix Z on a 3D dataset).
