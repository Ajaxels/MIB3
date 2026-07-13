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
| `LayoutSource` | `uidropdown` | Items: `{'Grid','Position file','Filename pattern'}` Default: `'Grid'` | `updateBatchOptFromGUI` |
| `InputPath` | `uieditfield` (text) | Default: `''` | `updateBatchOptFromGUI` |
| `selectInputBtn` | `uibutton` | Text: `'Browse…'` | `selectInputBtn_Callback` |
| `SubfolderMode` | `uicheckbox` | Text: `'Subfolder mode'` Default: `false` | `updateBatchOptFromGUI` |

### Grid group (`uipanel` Name: `gridPanel`, Title: "Grid")

| Handle | Class | Items / Limits / Default | Callback method |
|------|-------|--------------------------|-----------------|
| `GridRows` | `uispinner` | Limits: `[0 10000]` Step: 1 RoundFractionalValues: true Default: `0` | `updateBatchOptFromGUI` |
| `GridCols` | `uispinner` | Limits: `[0 10000]` Step: 1 RoundFractionalValues: true Default: `0` | `updateBatchOptFromGUI` |
| `TileOrder` | `uidropdown` | Items: `{'Horizontal','Horizontal snake','Vertical','Vertical snake'}` Default: `'Horizontal'` | `updateBatchOptFromGUI` |
| `OverlapX` | `uispinner` | Limits: `[0 90]` Step: 1 Default: `10` | `updateBatchOptFromGUI` |
| `OverlapY` | `uispinner` | Limits: `[0 90]` Step: 1 Default: `10` | `updateBatchOptFromGUI` |

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
| `TransformType` | `uidropdown` | Items: `{'Translation'}` Default: `'Translation'` | `updateBatchOptFromGUI` |
| `QualityThreshold` | `uispinner` | Limits: `[0 1]` Step: `0.05` Default: `0.30` | `updateBatchOptFromGUI` |
| `NominalPositionWeight` | `uispinner` | Limits: `[0 1]` Step: `0.01` Default: `0.10` | `updateBatchOptFromGUI` |
| `SubpixelPlacement` | `uicheckbox` | Text: `'Sub-pixel placement'` Default: `false` | `updateBatchOptFromGUI` |

Labels:

| Handle | Text |
|------|------|
| `transformTypeLabel` | `'Transform type'` |
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
| `measureBtn` | `uibutton` | `'Measure'` | `measureBtn_Callback` |
| `solveBtn` | `uibutton` | `'Solve'` | `solveBtn_Callback` |
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
