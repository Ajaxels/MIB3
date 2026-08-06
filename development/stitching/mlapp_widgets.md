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

This applies to `Autocrop` too — it shipped briefly as App Designer's
auto-generated `AutocropCheckBox` and was renamed, which is the right fix rather
than carrying a `CheckBox` suffix into batch protocols and project sidecars.

---

## Conventions

- All **callbacks** are wired in `addCallbacks.m`; leave every `*Fcn` property empty in App Designer.
- Tooltips are set by `addCallbacks` too (BatchOpt widgets reuse `BatchOpt.mibBatchTooltip`) — the mlapp stays layout-only.
- Dropdown `Items` in the mlapp are placeholders: `updateWidgets` overwrites `.Items`/`.Value` from
  `BatchOpt` for `LayoutSource`, `TileOrder`, `TransformType`, `RegistrationMethod`,
  `FeatureDetectorType`, `OutputMode`, `BlendMode`, `IntensityCorrection` and `CanvasColor`. The lists
  only need to be non-empty and to contain the mlapp's own `Value`.
- **Widgets the controller can live without** are read behind `isfield(handles, '<name>')` in both
  `updateWidgets` and `addCallbacks` (`inspectSeamsBtn`, `EstimateOverlap`, …). This is what lets the
  `.m` side of a feature land before the mlapp is edited: the tool runs, the parameter keeps its
  BatchOpt default, and batch protocols can already set it. Drop the guard once the widget is built —
  as `IntensityCorrection` did — accepting that an older mlapp then errors rather than silently
  ignoring the parameter.

---

## Container hierarchy (finalised 2026-07-27)

```
Figure  (623 × 750, Name 'Stitching')
└── mainGridLayout          ColumnWidth {22, 70, 90, '1x', 130, 100, 80}
                            RowHeight   {22, 70, '1x', '1x', 22}
    ├── row 1–2, col 1–2  Image                 puffin_stitching_96px.png (ScaleMethod 'none')
    ├── row 1             LayoutsourceLabel + LayoutSource      ← 1. header
    ├── row 2             infoLabel
    ├── row 3, col 1–7    TabGroup                              ← 2. settings tabs
    │   ├── inputTab           'Input tiles'   → inputGridLayout        {22, 60, '1x'} × {22, '1x'}
    │   ├── tileSettingsTab    'Tile settings' → tileSettingsGridLayout
    │   └── registrationTab    'Registration'  → registrationGridLayout
    ├── row 4, col 1–7    OutputPanel  'Output', BorderType 'none'      ← 3. output + preview
    │                     └── outputGridLayout  {110, 110, 80, 22, '1x', '1x'} × {22,22,22,22,'1x',22,22}
    └── row 5             helpButton (col 1) | inspectSeamsBtn (col 2–3) | ← 4. action strip
                          AutocropCheckBox (col 5) | stitchBtn (col 6) | closeButton (col 7)
```

**The container handles are not referenced by any controller code.** `@Stitching` addresses every
widget by its own handle (`obj.view.handles.<name>`) and `core.ChildView.getChildren` recurses
through `uigridlayout` / `uipanel` / `uitabgroup` / `uitab`, so the flat `handles` struct is
identical no matter which container a widget sits in. Re-parenting widgets — as the
panels → tab-group restructure did — is therefore a **pure mlapp change**: the earlier
`inputPanel` / `TileSettingsPanel` / `registrationPanel` handles were spec-only names that no `.m`
file ever read.

---

## Widget Table

### 1. Header (direct children of `mainGridLayout`)

| Handle | Class | Items / Limits / Default | Callback method |
|------|-------|--------------------------|-----------------|
| `Image` | `uiimage` | `ImageSource = 'puffin_stitching_96px.png'`, `ScaleMethod = 'none'`. Decoration only. | — |
| `LayoutsourceLabel` | `uilabel` | Text: `'Layout source'`, right-aligned | — |
| `LayoutSource` | `uidropdown` | Items: `{'Grid','Position file','Filename pattern','Bio-Formats metadata'}` Default: `'Grid'` (set from BatchOpt by `updateWidgets`) | `updateBatchOptFromGUI` |
| `infoLabel` | `uilabel` | `WordWrap='on'`, `VerticalAlignment='top'`, italic, ~2 lines tall. Non-BatchOpt — `updateInfoLabel` writes a short description of the selected `LayoutSource` (what to pick, what to set). | — |

### 2a. `inputTab` — "Input tiles" (`inputGridLayout`)

| Handle | Class | Items / Limits / Default | Callback method |
|------|-------|--------------------------|-----------------|
| `selectInputBtn` | `uibutton` | Text: `'Pick tiles'`, Icon `open_16px.png` | `selectInputBtn_Callback` |
| `SubfolderMode` | `uicheckbox` | Text: `'Tiles are folders (Z-stacks)'` Default: `false` | `updateBatchOptFromGUI` |
| `InputPathLabel` | `uilabel` | Text: `'Input tiles'`, right-aligned, top | — |
| `InputPath` | `uilistbox` (built) or `uieditfield` (text) | Default: empty. As a **listbox** it displays one selected path per row (best for multi-folder input) and is populated by *Pick tiles* — `refreshInputPathWidget` detects the type (`isprop(...,'Items')`) and keeps `BatchOpt.InputPath` as the newline-joined string either way. A listbox is display-only, so `addCallbacks` wires **no** `ValueChangedFcn` for it; an editfield keeps the typed-path sync. | `updateBatchOptFromGUI` (editfield only) |

### 2b. `tileSettingsTab` — "Tile settings" (`tileSettingsGridLayout`)

| Handle | Class | Items / Limits / Default | Callback method |
|------|-------|--------------------------|-----------------|
| `GridRows` | `uispinner` | Limits: `[0 10000]` Step: 1 RoundFractionalValues: true Default: `0` | `updateBatchOptFromGUI` |
| `GridCols` | `uispinner` | Limits: `[0 10000]` Step: 1 RoundFractionalValues: true Default: `0` | `updateBatchOptFromGUI` |
| `TileOrder` | `uidropdown` | Items: `{'Horizontal','Horizontal snake','Vertical','Vertical snake'}` Default: `'Horizontal'` | `updateBatchOptFromGUI` |
| `OverlapX` | `uispinner` | Limits: `[0 90]` Step: 1 Default: `10` | `updateBatchOptFromGUI` |
| `OverlapY` | `uispinner` | Limits: `[0 90]` Step: 1 Default: `10` | `updateBatchOptFromGUI` |
| `EstimateOverlap` | `uicheckbox` | Text: `'Estimate overlap'` Default: `true` | `updateBatchOptFromGUI` |

Labels (not interactive; `uilabel` — App Designer auto-names, kept as built):

| Handle | Text |
|------|------|
| `gridRowsSpinnerLabel` | `'Rows (0=auto)'` |
| `gridRowsSpinnerLabel_2` | `' Cols (0=auto)'` |
| `gridRowsSpinnerLabel_3` | `'Overlap X (%)'` |
| `OverlapYLabel` | `' Overlap Y (%)'` |
| `TileorderLabel` | `'Tile order'` |

### 2c. `registrationTab` — "Registration" (`registrationGridLayout`)

| Handle | Class | Items / Limits / Default | Callback method |
|------|-------|--------------------------|-----------------|
| `TransformType` | `uidropdown` | Items: `{'Translation','Rigid','Similarity','Affine'}` Default: `'Translation'` (Items/Value are overwritten by `updateWidgets` from BatchOpt — the mlapp list only needs to be non-empty) | `updateBatchOptFromGUI` |
| `AllowRotation` | `uicheckbox` | Text: `'Allow rotation'` Default: **unchecked**. Controller enables it only when `TransformType ≠ 'Translation'` (moot otherwise). Tooltip: stage-tiled data does not rotate — keep off so noisy overlaps cannot inject spurious rotations; tick only when tiles are genuinely rotated. Place right under `TransformType`. | `updateBatchOptFromGUI` |
| `RegistrationMethod` | `uidropdown` | Items: `{'Phase correlation','Feature-based'}` Default: `'Phase correlation'`. Controller disables it (measurement fixed to feature-based) when `TransformType ≠ 'Translation'`. | `updateBatchOptFromGUI` |
| `FeatureDetectorType` | `uidropdown` | Items: the 8 detectors (SURF/SIFT/MSER/Harris/BRISK/FAST/MinEigen/ORB — same list as `controllers.Alignment`) Default: SURF. Enabled when the feature-based estimator will run: `RegistrationMethod='Feature-based'` OR `TransformType ≠ 'Translation'` | `updateBatchOptFromGUI` |
| `configureFeaturesBtn` | `uibutton` | Icon `settings_16px.png`, Text `''` (icon-only) — opens the detector-parameter + downsampling + RANSAC dialog. Same enable rule as `FeatureDetectorType`. Sits right of `FeatureDetectorType`. | `configureFeaturesBtn_Callback` |
| `QualityThreshold` | `uispinner` | Limits: `[0 1]` Step: `0.05` Default: `0.30` | `updateBatchOptFromGUI` |
| `NominalPositionWeight` | `uispinner` | Limits: `[0 1]` Step: `0.01` Default: `0.10` | `updateBatchOptFromGUI` |
| `SubpixelPlacement` | `uicheckbox` | Text: `'Sub-pixel placement'` Default: `false` | `updateBatchOptFromGUI` |
| `measureOverlaps` | `uibutton` | Text: `'Measure overlaps'` — **pipeline step 1**, lives on this tab because it consumes these settings | `measureOverlaps_Callback` |
| `optimizePositions` | `uibutton` | Text: `'Optimize positions'` — **pipeline step 2**, same reason | `optimizePositions_Callback` |

Labels (App Designer auto-names, kept as built):

| Handle | Text |
|------|------|
| `TransformtypeLabel` | `' Transform type'` |
| `TransformtypeLabel_2` | `'Registration method'` |
| `FeatureDetectorTypeLabel` | `'Feature detector'` |
| `QualitythresholdLabel` | `' Quality threshold'` |
| `NominalpositionweightLabel` | `'Nominal position weight'` |

### 3. `OutputPanel` — "Output" (`outputGridLayout`)

Holds the layout preview, the output settings, the project buttons and the two status
readouts — everything about *what comes out* of the tool.

| Handle | Class | Items / Limits / Default | Callback method |
|------|-------|--------------------------|-----------------|
| `previewAxes` | `uiaxes` | Spans rows 1–6 of cols 1–2. `YDir='reverse'`, `XTick=[]`, `YTick=[]`, `Box='on'`, `Toolbar=[]` (the built-in axes toolbar would fight the tile ROIs). Labels/title are set per redraw by `previewLayoutBtn_Callback`. | — |
| `OutputMode` | `uidropdown` | Items: `{'In memory','OME-Zarr3 (BigData)'}` Default: `'In memory'` | `updateBatchOptFromGUI` |
| `OutputPath` | `uieditfield` (text) | Default: `''` Enable: `false` (enabled for OME-Zarr3 only) | `updateBatchOptFromGUI` |
| `selectOutputBtn` | `uibutton` | Text: `'...'` Enable: `false` | `selectOutputPath_Callback` |
| `BlendMode` | `uidropdown` | Items: `{'Average','Feather','Max','Min','Overwrite'}` (alphabetical) Default: `'Overwrite'` | `updateBatchOptFromGUI` |
| `IntensityCorrection` | `uidropdown` | Items: `{'None','Flat-field (shared)','Match tile means'}` Default: `'None'`. Sits directly under `BlendMode` — a pixel-level output choice like blending. | `updateBatchOptFromGUI` |
| `CanvasColor` | `uidropdown` | Items: `{'black','white'}` Default: `'white'`. Row 3, cols 5–6 — the fill for mosaic pixels no tile covers, so it belongs beside the other pixel-level output choices. | `updateBatchOptFromGUI` |
| `SaveProject` | `uicheckbox` | Text: `'Save project JSON'` Default: `true` | `updateBatchOptFromGUI` |
| `previewLayoutBtn` | `uibutton` | Text: `'Preview layout'` | `previewLayoutBtn_Callback` |
| `editLayoutCheckbox` | `uicheckbox` | Text: `'Edit layout'` — toggles the preview between static rectangles and draggable tile ROIs (Phase 3). Non-BatchOpt (a UI mode). | `previewLayoutBtn_Callback` |
| `saveProjectBtn` | `uibutton` | Text: `'Save project'`, Icon `save_16px.png` | `saveProjectBtn_Callback` |
| `loadProjectBtn` | `uibutton` | Text: `'Load project'`, Icon `open_16px.png` | `loadProjectBtn_Callback` |
| `statusLabel` | `uilabel` | `WordWrap='on'`, top-aligned. `'N tiles | N edges measured | solved: yes/no'` | — |
| `rmseLabel` | `uilabel` | The alignment-quality chip (colour + verdict), written by `refreshQualityChip` | — |

`BatchOpt.showWaitbar` intentionally has **no GUI widget** — it is a batch-only
option (progress bars are always shown in interactive GUI runs).

Labels:

| Handle | Text |
|------|------|
| `OutputmodeLabel` | `' Output mode'` |
| `outputPathEditFieldLabel` | `'Output path'` |
| `blendModeDropDownLabel` | `'Blend mode'` |
| `blendModeDropDownLabel_2` | `'Intensity correction'` |
| `blendModeDropDownLabel_3` | `'Canvas color'` (row 3, cols 3–4) |

### 4. Action strip (row 5 of `mainGridLayout`)

| Handle | Class | Text | Callback method |
|------|-------|------|-----------------|
| `helpButton` | `uibutton` | Icon `help_16px.png`, Text `''` (icon-only), col 1 | `helpBtn_Callback` |
| `inspectSeamsBtn` | `uibutton` | `'Inspect and fix...'`, green `[0.149 0.902 0.180]`, cols 2–3 — opens the seam inspector (worst-first manual QC, see plan_inspector.md). Controller enables it only when edges + positions exist. | `inspectSeams_Callback` |
| `Autocrop` | `uicheckbox` | Text `'Autocrop'`, col 5, Default `false` — trims the uncovered frame off the mosaic. | `updateBatchOptFromGUI` |
| `stitchBtn` | `uibutton` | `'Stitch'`, green, col 6 | `stitchBtn_Callback` |
| `closeButton` | `uibutton` | `'Close'`, orange `[1 0.529 0.102]`, col 7 | `closeWindow` |

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

1. Window is portrait — 623 × 750 px — with the four areas stacked top to bottom (see the
   container hierarchy above), not the two-column form the first draft of this spec described.
2. Everything is inside `uigridlayout`s, so the window resizes without any `mibRescaleWidgets`
   equivalent. `previewAxes` gets fixed 220 px of width (`outputGridLayout` cols 1–2) and takes all
   the vertical slack (`RowHeight` row 5 is `'1x'`).
3. **What goes on which tab** — a widget belongs to the tab whose step consumes it: *Input tiles*
   answers "which files", *Tile settings* "how are they arranged", *Registration* "how are they
   matched" (which is why *Measure overlaps* and *Optimize positions* sit there and not in the
   bottom strip). The bottom strip holds only what must stay reachable from every tab: help, the
   inspector, *Stitch*, close.
4. `LayoutSource` deliberately sits **above** the tab group: it decides which of the tab widgets are
   even enabled, so hiding it inside one tab would make the enable/disable behaviour look arbitrary.
   `infoLabel` under it says what to pick for the selected source.
5. All numeric spinners: set `RoundFractionalValues = 'on'` where the BatchOpt has `'on'` as 3rd element.
6. `GridRows` and `GridCols` allow `0` (auto) — set `AllowEmpty = 'off'` and `Limits = [0 10000]`.
7. Icon-only buttons (`helpButton`, `configureFeaturesBtn`) must keep `Text = ''` **and** an `Icon`;
   the icons resolve from `mib\assets\icons` (`help_16px.png`, `settings_16px.png`, `open_16px.png`,
   `save_16px.png`), the header image from `mib\assets\images\puffin_stitching_96px.png`.

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
| `SeamsworstfirstLabel` | `uilabel` | Text `'Seams (worst first)'` - the heading above `seamTable`. Referenced by nothing in the controller; it exists only to name the table on screen. |
| `seamTable` | `uitable` | 6 columns (controller sets `Data`/`ColumnName`); `SelectionType = 'row'`, `Multiselect = 'off'`. Worst seam on top. |
| `miniMapAxes` | `uiaxes` | Title: `'Layout (click a tile to jump)'`; controller draws score-coloured tile patches; `XTick`/`YTick` cleared by controller. |
| `statusLabel` | `uilabel` | Default: `'0 seams'`; spans the column. |

**The table's label must say SEAMS, not tiles.** It read `'Tile sets'` until 2026-08 - the rows are
seam*s* (tile PAIRS), the first column is headed `Seam` and the tooltip calls them seams, so a label
naming tiles sent readers looking for a tile list. `(worst first)` is carried in the label rather
than the tooltip because nothing else on screen explains why row 1 is the one to look at. Keep the
wording identical to the tooltip and the docs (`worst-first` everywhere) so it reads as one concept.

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
| `excludeBtn` | `uibutton` **state** (`uibutton(parent,'state')`) | `'Exclude (X)'` | `excludeSeam_Callback` |
| `resolveBtn` | `uibutton` | `'Re-solve'` | `resolveBtn_Callback` |
| `closeButton` | `uibutton` | `'Close'` | `closeWindow` |

**No fuse and no save button here** (both removed from the mlapp 2026-07-26). *Stitch* and *Save
project* live in the Stitching window, which stays reachable while the inspector is open, so a copy
would only be the same action under a second name. The inspector mutates the parent's
`edges`/`positions` in place, so the parent's *Save project* already persists this session's fixes,
and its *Stitch* applies any pending re-solve itself. Do not re-add `refuseBtn` or `saveProjectBtn`.

**`excludeBtn` is a STATE button** (App Designer palette: *State Button*) — excluding a seam is a
two-state action, and as a plain push button the second press ("re-include") was invisible. The
controller pushes the state onto the widget from the EDGE in `refreshExcludeButton`: pressed +
red `[0.92 0.55 0.55]` + text `'Excluded (X)'` while excluded, unpressed + the button's original
background + `'Exclude (X)'` otherwise. It never reads the widget, so the `X` key stays equivalent
and a plain `uibutton` still works (colour + text change, no pressed look) — upgrade the mlapp
whenever convenient.

### Phase C widgets (interactive fixing — all guarded, add anytime)

| Handle | Class | Properties / Text | What it drives |
|------|-------|-------------------|----------------|
| `ROIsizeSpinner` | `uispinner` | Limits `[16 Inf]`, default `128`, step `32` | Click-to-correlate ROI edge length (px). Keep it SMALLER than the overlap strip on small tiles. |
| `SearchradiusSpinner` | `uispinner` | Limits `[8 256]`, default `64`, step `8` | Correlation search radius around the current offset (px per side). |
| `twoClickBtn` | `uibutton` | `'Two-click match'` | `twoClickBtn_Callback` — side-by-side full tiles, click the same landmark in each (for offsets beyond any search radius). Press again to cancel. |
| `fixModeDropdown` | `uidropdown` | Items `{'Fix XY','Fix Z (match slices)'}`, default `'Fix XY'` | What a fix edits on 3D pairs (2D pairs ignore it). **Fix Z** = slice-matching across the Z boundary: PgUp/PgDn steps tile j's slice (Ctrl = tile i's) to propose the correspondence; Shift+click/drag/arrows apply it (as dz) together with the in-plane offset. |
| `undoFixBtn` | `uibutton` | `'Undo fix (Z)'` | `undoFix_Callback` — restore the original automatic edge. |
| `fitViewBtn` | `uibutton` | `'Fit view (F)'` | `fitView_Callback` — reset the pair-view wheel zoom to fit the whole pair. |
| `autoResolveCheckbox` | `uicheckbox` | Text `'Auto re-solve'`, default **checked** | Re-solve + re-rank automatically after each fix. When the widget is absent the controller defaults to ON. |

Pair-view mouse interactions (no mlapp work — the controller wires image
`ButtonDownFcn`s + the figure's `WindowButtonMotionFcn`/`WindowScrollWheelFcn`):
**wheel** zooms about the cursor (scroll up = in; zooming fully out snaps back
to fit; the zoom survives re-renders of the SAME seam — nudges, drags, fixes —
and resets on seam change or `F`/`fitViewBtn`);
**Shift+hover** shows the correlation ROI box under the cursor (yellow,
`ROIsizeSpinner`-sized, click-transparent), **Shift+wheel** resizes it (steps
`ROIsizeSpinner` within its limits) and **Shift+click** = click-to-correlate
within it; DRAG = move tile *j* live (grey background + 50% alpha overlay,
keeping the current zoom), release applies the fix; a plain click is
deliberately a no-op (stray clicks must never move tiles).

All widget **tooltips are set by the controller** in `addCallbacks`
(`setTooltip` guarded per widget) — do not write tooltips into the mlapp, it
stays layout-only.

Keyboard (wired by the controller on the figure, no mlapp work needed):
`Space` flicker, `Enter` confirm+next, `X` exclude, `Down`/`Up` next/prev
SEAM (one row down/up the table — NOT slice browsing; `N`/`P` retired
2026-08-06),
`Q`/`W` browse Z slices previous/next like the main
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
