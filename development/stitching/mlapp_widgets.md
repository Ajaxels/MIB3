# StitchingGUI.mlapp — Widget Specification

Blueprint for building `mib/+views/StitchingGUI.mlapp` in MATLAB App Designer.

All widget **handles** (component names in App Designer's Component Browser)
must match exactly — the controller references them via
`obj.view.handles.<handle>` (populated by `core.ChildView`, which also copies
each component name into its `Tag` property).

**BatchOpt naming rule:** every widget that maps to a BatchOpt parameter has a
handle **exactly matching its BatchOpt field** (PascalCase, e.g. `TileOrder`,
`GridRows`; exception: `showWaitbar` is lowercase by MIB3 convention). This is
what makes `utils.updateBatchOptFromGUI_Shared` work — it writes
`BatchOpt.(widget.Tag)`, and the Tag equals the handle.

---

## Conventions

- All **callbacks** are wired in `addCallbacks.m`; leave every `*Fcn` property empty in App Designer.
- Layout: two-column form on the left, preview `uiaxes` on the right, action buttons across the bottom.

---

## Widget Table

### Input group (`uipanel` Name: `inputPanel`, Title: "Input")

| Handle | Class | Items / Limits / Default | Callback method |
|------|-------|--------------------------|-----------------|
| `LayoutSource` | `uidropdown` | Items: `{'Grid','Position file','Filename pattern','Bio-Formats metadata'}` Default: `'Grid'` | `updateBatchOptFromGUI` |
| `InputPath` | `uilistbox` (preferred) or `uieditfield` (text) | Default: empty. As a **listbox** it displays one selected path per row (best for multi-folder input) and is populated by Browse — the controller detects the type (`isprop(...,'Items')`) and keeps `BatchOpt.InputPath` as the newline-joined string either way. A listbox is display-only (no `ValueChangedFcn`); an editfield keeps the typed-path sync. | `updateBatchOptFromGUI` (editfield only) |
| `selectInputBtn` | `uibutton` | Text: `'Browse…'` | `selectInputBtn_Callback` |
| `SubfolderMode` | `uicheckbox` | Text: `'Tiles are folders (Z-stacks)'` Default: `false` | `updateBatchOptFromGUI` |
| `infoLabel` | `uilabel` | Multi-line (`WordWrap='on'`, ~2 lines tall). Non-BatchOpt. The controller sets `.Text` to a short description of the selected `LayoutSource` (via `updateInfoLabel`, guarded by `isfield`). | — |

### Tile settings group (`uipanel` Name: `TileSettingsPanel`, Title: "Tile settings")

| Handle | Class | Items / Limits / Default | Callback method |
|------|-------|--------------------------|-----------------|
| `GridRows` | `uispinner` | Limits: `[0 10000]` Step: 1 RoundFractionalValues: true Default: `0` | `updateBatchOptFromGUI` |
| `GridCols` | `uispinner` | Limits: `[0 10000]` Step: 1 RoundFractionalValues: true Default: `0` | `updateBatchOptFromGUI` |
| `TileOrder` | `uidropdown` | Items: `{'Horizontal','Horizontal snake','Vertical','Vertical snake'}` Default: `'Horizontal'` | `updateBatchOptFromGUI` |
| `OverlapX` | `uispinner` | Limits: `[0 90]` Step: 1 Default: `10` | `updateBatchOptFromGUI` |
| `OverlapY` | `uispinner` | Limits: `[0 90]` Step: 1 Default: `10` | `updateBatchOptFromGUI` |
| `EstimateOverlap` | `uicheckbox` | Text: `'Estimate overlap'` Default: `true` | `updateBatchOptFromGUI` |

Labels for spinners (not interactive; `uilabel`):

| Handle | Text |
|------|------|
| `gridRowsLabel` | `'Rows (0=auto)'` |
| `gridColsLabel` | `'Cols (0=auto)'` |
| `tileOrderLabel` | `'Tile order'` |
| `overlapXLabel` | `'Overlap X (%)'` |
| `overlapYLabel` | `'Overlap Y (%)'` |

### Registration group (`uipanel` Name: `registrationPanel`, Title: "Registration")

| Handle | Class | Items / Limits / Default | Callback method |
|------|-------|--------------------------|-----------------|
| `TransformType` | `uidropdown` | Items: `{'Translation','Rigid','Similarity','Affine'}` Default: `'Translation'` (Items/Value are overwritten by `updateWidgets` from BatchOpt — the mlapp list only needs to be non-empty) | `updateBatchOptFromGUI` |
| `AllowRotation` | `uicheckbox` | Text: `'Allow rotation'` Default: **unchecked**. Controller enables it only when `TransformType ≠ 'Translation'` (moot otherwise). Tooltip: stage-tiled data does not rotate — keep off so noisy overlaps cannot inject spurious rotations; tick only when tiles are genuinely rotated. Place right under `TransformType`. | `updateBatchOptFromGUI` |
| `RegistrationMethod` | `uidropdown` | Items: `{'Phase correlation','Feature-based'}` Default: `'Phase correlation'`. Controller disables it (measurement fixed to feature-based) when `TransformType ≠ 'Translation'`. | `updateBatchOptFromGUI` |
| `FeatureDetectorType` | `uidropdown` | Items: the 8 detectors (SURF/SIFT/MSER/Harris/BRISK/FAST/MinEigen/ORB — same list as `controllers.Alignment`) Default: SURF. Enabled when the feature-based estimator will run: `RegistrationMethod='Feature-based'` OR `TransformType ≠ 'Translation'` | `updateBatchOptFromGUI` |
| `configureFeaturesBtn` | `uibutton` | Text: `'Settings…'` — opens the detector-parameter + downsampling + RANSAC dialog. Same enable rule as `FeatureDetectorType` | `configureFeaturesBtn_Callback` |
| `QualityThreshold` | `uispinner` | Limits: `[0 1]` Step: `0.05` Default: `0.30` | `updateBatchOptFromGUI` |
| `NominalPositionWeight` | `uispinner` | Limits: `[0 1]` Step: `0.01` Default: `0.10` | `updateBatchOptFromGUI` |
| `SubpixelPlacement` | `uicheckbox` | Text: `'Sub-pixel placement'` Default: `false` | `updateBatchOptFromGUI` |

Labels:

| Handle | Text |
|------|------|
| `transformTypeLabel` | `'Transform type'` |
| `registrationMethodLabel` | `'Registration method'` |
| `featureDetectorTypeLabel` | `'Feature detector'` |
| `qualityThresholdLabel` | `'Quality threshold'` |
| `springWeightLabel` | `'Nominal position weight'` |

### Output group (`uipanel` Name: `outputPanel`, Title: "Output")

| Handle | Class | Items / Limits / Default | Callback method |
|------|-------|--------------------------|-----------------|
| `OutputMode` | `uidropdown` | Items: `{'In memory','OME-Zarr (BigData)'}` Default: `'In memory'` | `updateBatchOptFromGUI` |
| `OutputPath` | `uieditfield` (text) | Default: `''` Enable: `false` | `updateBatchOptFromGUI` |
| `selectOutputBtn` | `uibutton` | Text: `'Browse…'` Enable: `false` | `selectOutputPath_Callback` |
| `BlendMode` | `uidropdown` | Items: `{'Feather','Average','Max','Overwrite'}` Default: `'Feather'` | `updateBatchOptFromGUI` |
| `SaveProject` | `uicheckbox` | Text: `'Save project JSON'` Default: `true` | `updateBatchOptFromGUI` |

`BatchOpt.showWaitbar` intentionally has **no GUI widget** — it is a batch-only
option (progress bars are always shown in interactive GUI runs).

Labels:

| Handle | Text |
|------|------|
| `outputModeLabel` | `'Output mode'` |
| `outputPathLabel` | `'Output path'` |
| `blendModeLabel` | `'Blend mode'` |

### Preview axes

| Handle | Class | Properties |
|------|-------|------------|
| `previewAxes` | `uiaxes` | XLabel: `'X (pixels)'` YLabel: `'Y (pixels)'` Title: `'Layout preview'` YDir: `'reverse'` |

### Status and RMSE labels

| Handle | Class | Default Text |
|------|-------|--------------|
| `statusLabel` | `uilabel` | `'0 tiles | 0 edges measured | solved: no'` |
| `rmseLabel` | `uilabel` | `'RMSE: —'` |

### Action buttons (bottom row)

| Handle | Class | Text | Callback method |
|------|-------|------|-----------------|
| `previewLayoutBtn` | `uibutton` | `'Preview layout'` | `previewLayoutBtn_Callback` |
| `editLayoutCheckbox` | `uicheckbox` | `'Edit layout (drag tiles)'` — toggles the preview between static rectangles and draggable tile ROIs (Phase 3). Non-BatchOpt (a UI mode). | `previewLayoutBtn_Callback` |
| `measureOverlaps` | `uibutton` | `'Measure overlaps'` | `measureOverlaps_Callback` |
| `optimizePositions` | `uibutton` | `'Optimize positions'` | `optimizePositions_Callback` |
| `inspectSeamsBtn` | `uibutton` | `'Inspect & fix…'` — opens the seam inspector (worst-first manual QC, see plan_inspector.md). Controller enables it only when edges + positions exist. Place next to `optimizePositions` / the rating chip. | `inspectSeams_Callback` |
| `stitchBtn` | `uibutton` | `'Stitch'` | `stitchBtn_Callback` |
| `saveProjectBtn` | `uibutton` | `'Save project'` | `saveProjectBtn_Callback` |
| `loadProjectBtn` | `uibutton` | `'Load project'` | `loadProjectBtn_Callback` |
| `helpButton` | `uibutton` | `'Help'` | `helpBtn_Callback` |
| `closeButton` | `uibutton` | `'Close'` | `closeWindow` |

---

## startupFcn (App Designer)

Add a `startupFcn` in App Designer (Component Browser → app → Add → startupFcn):

```matlab
function startupFcn(app, winController)
    % Intentionally empty — controller's constructor wires everything via addCallbacks.
end
```

This follows the pattern established in CropDatasetGUI.mlapp (plan_crop.md).

---

## Notes for App Designer layout

1. Window size: approximately 900 × 650 px to accommodate the preview axes.
2. Left column (≈ 300 px wide): stacked panels — Input, Grid, Registration, Output.
3. Right area: `previewAxes` fills the remaining width.
4. Bottom strip (≈ 40 px tall): action buttons in a row.
5. Status strip at the very bottom: `statusLabel` (left) + `rmseLabel` (right).
6. All numeric spinners: set `RoundFractionalValues = 'on'` where the BatchOpt has `'on'` as 3rd element.
7. `GridRows` and `GridCols` allow `0` (auto) — set `AllowEmpty = 'off'` and `Limits = [0 10000]`.

---

# StitchingInspectorGUI.mlapp (seam inspector — plan_inspector.md Phases B–C)

New mlapp `mib\+views\StitchingInspectorGUI.mlapp`. **No BatchOpt** — this is a
purely interactive tool, so ALL handles use descriptive lowerCamel names. Same
conventions as the main GUI: figure property named `Figure`, empty
`startupFcn(app, winController)`, `Visible = 'off'` initially (the controller
shows it after wiring).

Window ≈ 1000 × 640 px. Left column (≈ 360 px): seam table on top, mini-map
below, status label at the bottom. Right area: pair view axes with the overlay
dropdown + offset label above and the action buttons below.

### Left column

| Handle | Class | Properties |
|------|-------|------------|
| `seamTable` | `uitable` | 7 columns (controller sets `Data`/`ColumnName`); `SelectionType = 'row'`, `Multiselect = 'off'`. Worst seam on top. |
| `miniMapAxes` | `uiaxes` | Title: `'Layout (click a tile to jump)'`; controller draws score-coloured tile patches; `XTick`/`YTick` cleared by controller. |
| `statusLabel` | `uilabel` | Default: `'0 seams'`; spans the column. |

### Right area

| Handle | Class | Properties |
|------|-------|------------|
| `overlayModeDropdown` | `uidropdown` | Items: `{'Falsecolor','Flicker','Checkerboard','Difference'}` Default: `'Falsecolor'` |
| `offsetLabel` | `uilabel` | Default: `''` — current vs measured offset + scores readout (next to the dropdown). |
| `pairAxes` | `uiaxes` | The seam composite; controller manages everything (`YDir`, ticks). |

### Action buttons (bottom row of the right area)

| Handle | Class | Text | Callback (controller wires it) |
|------|-------|------|-------------------------------|
| `confirmBtn` | `uibutton` | `'Confirm (Enter)'` | `confirmSeam_Callback` |
| `excludeBtn` | `uibutton` | `'Exclude (X)'` | `excludeSeam_Callback` |
| `resolveBtn` | `uibutton` | `'Re-solve'` | `resolveBtn_Callback` |
| `saveProjectBtn` | `uibutton` | `'Save project'` | (delegates to the Stitching window) |
| `closeButton` | `uibutton` | `'Close'` | `closeWindow` |

### Phase C widgets (interactive fixing — all guarded, add anytime)

| Handle | Class | Properties / Text | What it drives |
|------|-------|-------------------|----------------|
| `roiSizeSpinner` | `uispinner` | Limits `[32 512]`, default `128`, step `16` | Click-to-correlate ROI edge length (px). Keep it SMALLER than the overlap strip on small tiles. |
| `searchRadiusSpinner` | `uispinner` | Limits `[8 256]`, default `64`, step `8` | Correlation search radius around the current offset (px per side). |
| `twoClickBtn` | `uibutton` | `'Two-click match'` | `twoClickBtn_Callback` — side-by-side full tiles, click the same landmark in each (for offsets beyond any search radius). Press again to cancel. |
| `fixModeDropdown` | `uidropdown` | Items `{'Fix XY','Fix Z (match slices)'}`, default `'Fix XY'` | What a fix edits on 3D pairs (2D pairs ignore it). **Fix Z** = slice-matching across the Z boundary: PgUp/PgDn steps tile j's slice (Ctrl = tile i's) to propose the correspondence; Shift+click/drag/arrows apply it (as dz) together with the in-plane offset. |
| `undoFixBtn` | `uibutton` | `'Undo fix (Z)'` | `undoFix_Callback` — restore the original automatic edge. |
| `fitViewBtn` | `uibutton` | `'Fit view (F)'` | `fitView_Callback` — reset the pair-view wheel zoom to fit the whole pair. |
| `autoResolveCheckbox` | `uicheckbox` | Text `'Auto re-solve'`, default **checked** | Re-solve + re-rank automatically after each fix. When the widget is absent the controller defaults to ON. |
| `refuseBtn` | `uibutton` | `'Re-fuse'` | `refuseBtn_Callback` (Phase D) — full fuse with the corrected positions, delegated to the parent's `stitchBtn_Callback` (both output modes); a pending re-solve runs first. |

Pair-view mouse interactions (no mlapp work — the controller wires image
`ButtonDownFcn`s + the figure's `WindowButtonMotionFcn`/`WindowScrollWheelFcn`):
**wheel** zooms about the cursor (scroll up = in; zooming fully out snaps back
to fit; the zoom survives re-renders of the SAME seam — nudges, drags, fixes —
and resets on seam change or `F`/`fitViewBtn`);
**Shift+hover** shows the correlation ROI box under the cursor (yellow,
`roiSizeSpinner`-sized, click-transparent), **Shift+wheel** resizes it (steps
`roiSizeSpinner` within its limits) and **Shift+click** = click-to-correlate
within it; DRAG = move tile *j* live (grey background + 50% alpha overlay,
keeping the current zoom), release applies the fix; a plain click is
deliberately a no-op (stray clicks must never move tiles).

All widget **tooltips are set by the controller** in `addCallbacks`
(`setTooltip` guarded per widget) — do not write tooltips into the mlapp, it
stays layout-only.

Keyboard (wired by the controller on the figure, no mlapp work needed):
`Space` flicker, `Enter` confirm+next, `X` exclude, `N`/`P` next/prev,
`Q`/`W` AND `Down`/`Up` arrows browse Z slices previous/next like the main
MIB — ALWAYS view-only in BOTH modes (THE KEYBOARD NEVER MOVES A TILE;
offsets are edited by mouse only — drag / Shift+click / two-click): in Fix
XY both tiles step together through the overlap slab; in Fix Z they step
tile *j*'s slice and `Ctrl` steps tile *i*'s, proposing the slice match that
the next fix applies as dz (`Shift` ±5; status note on 2D pairs), `Z` undo
fix, `F` fit view (reset zoom).

Mini-map (Phase D): when the tiles sum to < ~1.5 G full-res pixels a low-res
fused preview (per-tile thumbnails built once, composited at the solved
positions each redraw) is drawn behind the score patches, which then drop to
a light tint — no mlapp work, `miniMapAxes` only.
