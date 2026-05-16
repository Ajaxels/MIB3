# MIB2 → MIB3 Port: `mibAlignmentController` → `controllers.Alignment`

Detailed plan and current state of the port. See `development/guide_to_appdesigner_conversion.md` for the generic GUIDE → AppDesigner rules.

---

## Context

MIB2's `mibAlignmentController` is a ~3000-line GUIDE-based dialog driving image-stack alignment via 8 algorithms (drift correction, template matching, single/three/multi landmark, color-channel landmark, automatic feature-based v1/v2, AMST). It currently mixes:

- a monolithic `continueBtn_Callback` (~800 lines) that inlines the simpler algorithms and delegates to external method files for the heavier ones,
- a "Two stacks" mode that aligns one stack against another loaded from disk/workspace,
- a tangle of `waitbar`, `errordlg`, `warndlg`, `msgbox`, `questdlg` calls across the file.

Goal: port to MIB3 (`+controllers/@Alignment/`) under the AppContainer + AppDesigner framework, while:

1. **Skipping the "Two stacks" mode entirely** — drop `Mode` radio, `secondDatasetPanel`, all `BatchOpt.TwoStacks*` / `SecondDataset*` fields, and the `else` branch in MIB2's `continueBtn_Callback` (lines 1337–1479).
2. **Refactoring `continueBtn_Callback` into a thin dispatcher** that calls one method per algorithm, in dedicated files in `@Alignment/`.
3. **Replacing all `questdlg` calls with `utils.dlgs.inputQuestDlg`** (questdlg-compatible signature); `warndlg`/`msgbox` (informational) with `utils.dlgs.inputUniversalDlg` (`MsgBoxOnly` mode); **`errordlg` and every `try/catch` block with `utils.dlgs.showErrorDialog`** (passing the caught `MException` directly when applicable).
4. **Replacing every `waitbar`/`uiprogressdlg` with `core.PoolWaitbar` constructed `Cancelable=true`**, with `getCancelState()` polled at the top of every loop and before every irreversible operation.
5. **Writing all docblocks in the RST/Sphinx style** from `development/docs_api_sphinx.md`.
6. **Centralising every widget callback through a single `gui_Callbacks(obj, source, event)` dispatcher** that switches on `source.Tag` — matches the pattern already used by `@MeasureTool`, `@MibSelection`, `@MibRoi`, etc. The user's `.mlapp` and `obj.addCallbacks()` wire **every** widget to `@(s,e) obj.gui_Callbacks(s,e)`. The dispatcher routes to per-action methods.

Decisions:
- Backend helpers → `mib/+utils/+align/` subpackage.
- Per-algorithm methods → one `.m` file per algorithm in `@Alignment/`.
- Staged port: Phase 1 = runnable controller with Drift correction + Single landmark + dispatcher; subsequent phases add the rest.
- View `mib/+views/AlignmentGUI.mlapp` is authored by the user against the widget Tag contract below.

---

## File Layout

### Controller package — `mib/+controllers/@Alignment/`

| File | Role | Phase | State |
|---|---|---|---|
| `Alignment.m` | classdef + constructor + `addCallbacks` + `closeWindow` + `returnBatchOpt` + `updateBatchOptFromGUI` + `updateWidgets` + `ViewListner_Callback2` + `findMatchingPairs` + private `defaultAutomaticOptions` / `defaultTooltips` | 1 | ✅ done |
| `gui_Callbacks.m` | Single dispatcher routing every `source.Tag` | 1 | ✅ done |
| `continueBtn_Callback.m` | Thin algorithm-dispatcher; switch on `BatchOpt.Algorithm{1}` | 1 | ✅ done |
| `DriftCorrection_Alignment.m` | In-memory drift correction + template matching; Subarea (Full/Manual/Mask/Selection); IntensityGradient; running-average post-processing | 1 | ✅ done |
| `SingleLandmark_Alignment.m` | Single-landmark-per-slice (Selection-centroid or Annotation paths) | 1 | ✅ done |
| `algorithm_Callback.m` | Toggle widget enable/disable when Algorithm dropdown changes | 1 | ✅ done |
| `subwindowEdit_Callback.m` | minX/maxX/minY/maxY validation | 1 | ✅ done |
| `getSearchWindow_Callback.m` | Pull bounding box from selection | 1 | ✅ done |
| `loadShiftsCheck_Callback.m` | File picker for `.coefXY` shifts | 1 | ✅ done |
| `ThreeLandmarks_Alignment.m` | 3-point affine (MIB2 lines 868–959); `fitgeotrans` + `imwarp` modernisation; warps + crossShiftStacks for image + service layers | 2 | ✅ done |
| `LandmarkMultiPoint_Alignment.m` | Multi-point landmark alignment with per-slice cumulative `fitgeotrans`; cropped + extended modes; warps image + service layers; relocates annotations | 2 | ✅ done |
| `LandmarkMultiPointColor_Alignment.m` | Within-slice colour-channel landmark alignment; pairs annotations by text label, value 1 = fixed channel, value 2 = channel to transform; cropped mode only (matches MIB2) | 2 | ✅ done |
| `AutomaticFeatureBased_Alignment.m` | In-memory v1: per-slice `detectFeatures` + `extractFeatures` + `matchFeatures` + `estgeotform2d` RANSAC → cumulative `tform.T` chain → cropped/extended apply (canvas-replace pattern). Interactive running-average smoothing in GUI mode (figure 125, 3-way dialog, settings loop); BatchOpt-driven in batch mode. Handles `rigidtform2d`/`simtform2d`/`affinetform2d`/`projtform2d` → legacy `affine2d`/`projective2d` `.T` form for composition. | 3 | ✅ done |
| `AutomaticFeatureBasedV2_Alignment.m` | Modern v2 (R2022b+): `estgeotform2d` → `affinetform2d` native, pairwise tforms decomposed into translation / rotation / scale, cumulative via cumsum/cumprod; corner-projection canvas for extended mode; rounds translations for `translation` type; ratio = `1/imgDownsamplingFactorForAnalysis`; allowed types `translation/rigid/similarity/affine`; BatchOpt-driven smoothing on cumulative parameters | 3 | ✅ done |
| `AutomaticFeatureBasedHDD_Alignment.m` | Streaming v1: imageDatastore + parfor detect/extract + sequential match/estgeotform2d compose + per-image read/warp/save to `<InputDir>/HDD_OutputSubfolderName`; cropped + extended (per-slice `affineOutputView` **with `'BoundsStyle','FollowOutput'`** + union canvas + minimum-bounding-box tile placement); interactive smoothing in GUI mode (figure 125, 3-way dialog, settings loop); BatchOpt-driven in batch mode; `rng(0,'twister')` seed for reproducibility | 3 | ✅ done |
| `AutomaticFeatureBasedHDDV2_Alignment.m` | HDD-mode v2: imageDatastore + parfor detect/extract + sequential match/`estgeotform2d` compose with native `affinetform2d` + pairwise→translation/rotation/scale decomposition + cumsum/cumprod cumulative + corner-projection canvas + per-image read/warp/save via `imwarp` with explicit `OutputView`; reuses the interactive smoothing flow from v2 in-memory; `rng(0,'twister')` for reproducibility | 3 | ✅ done |
| `AlignMedianSmoothTemplate_Alignment.m` | Intensity-based registration to a `medfilt3([1,1,MedianSize])` template via `imregtform` (monomodal, `automaticOptions.amst` optimizer knobs); cropped-only (matches MIB2); supports `translation/rigid/similarity/affine`; optional parfor; interactive smoothing in GUI mode (figure 125, 3-way dialog, settings loop) + BatchOpt-driven in batch mode | 3 | ✅ done |
| `alignDriftCorrectionHDD_Alignment.m` | Streaming drift correction over a directory; `imageDatastore` + `io.loadImagesWrapper` reads + FFT cross-correlation pair by pair + cumsum / windowed / first-slice integration + interactive smoothing in GUI mode (figure 155, 3-way dialog, delegates to interactive `subtractRunningAverage`); BatchOpt-driven in batch mode; per-image padded canvas saved via `core.MibImage.save` to `<InputDir>/HDD_OutputSubfolderName` in chosen format (AM/JPG/MRC/NRRD/PNG/TIF) | 3 | ✅ done |
| `previewFeaturesBtn_Callback.m` | Feature detector preview window — slice / slice+1 detect → match → `estgeotform2d` RANSAC → side-by-side `showMatchedFeatures` (with outliers + inliers) in a tagged figure | 3 | ✅ done |
| `HDD_BioformatsReader_Callback.m` | Enable/disable HDD bioformats index | 3 | ⬜ pending (currently inlined in `gui_Callbacks`) |

### Backend helpers — `mib/+utils/+align/`

| File | Source | Phase | State |
|---|---|---|---|
| `windv.m` | `MIB2\Tools\windv.m` | 1 | ✅ done |
| `runningAverageSmoothPoints.m` | `MIB2\Tools\mibRunningAverageSmoothPoints.m` | 1 | ✅ done |
| `calcShifts.m` | `MIB2\Tools\mibCalcShifts.m` | 1 | ✅ done — takes optional `core.PoolWaitbar` via `options.waitbar` |
| `crossShiftStack.m` | `MIB2\Tools\mibCrossShiftStack.m` | 1 | ✅ done — rewritten to consume MIB3 5-D `[h, w, d, c, t]` natively; no permute to MIB2 `[h, w, c, d]` |
| `subtractRunningAverage.m` | `MIB2\Tools\mibSubtractRunningAverage.m` | 1 | ✅ done — uses `inputUniversalDlg` + `inputQuestDlg`; takes parent figure as 1st arg |
| `crossShiftStacks.m` | `MIB2\Tools\mibCrossShiftStacks.m` | 2 | ✅ done — MIB3 layout `[h, w, d, c]` natively; `modelSwitch=1` for 3-D service layers; reuses an existing `core.PoolWaitbar` for cancel polling |
| `detectFeatures.m` | `MIB2\Tools\mibAlignmentDetectFeatures.m` | 3 | ✅ done — pure dispatcher over `detect{SURF,SIFT,MSER,Harris,BRISK,FAST,MinEigen,ORB}Features`; consumes the `obj.automaticOptions` struct |

### View — authored by the user

`mib/+views/AlignmentGUI.mlapp` — see "Widget Tag Contract" below. ⬜ pending.

### Modified files

- `mib/+controllers/@MibRibbon/datasetAlignment_Callback.m` — Dataset → Alignment ribbon button now spawns `controllers.Alignment`. ✅ done.

---

## Widget Tag Contract (`obj.view.handles.<Tag>`)

The `.mlapp` must expose the following Tags. **No `Mode` radio, no `secondDatasetPanel`, no `TwoStacks*` / `SecondDataset*` widgets.** Tags absent from the `.mlapp` are silently skipped by `addCallbacks` and the field-existence guards in `updateWidgets` / `algorithm_Callback`.

**Info display (top, read-only):**
- `existingFnText1`, `existingFnText2` (uilabel) — current dataset path + filename
- `existingDimText` (uilabel) — `W x H x Z`
- `existingPixText`, `existingPixText2` (uilabel) — pixel size

**Algorithm panel:**
- `Algorithm` (uidropdown) — items: `Drift correction`, `Template matching`, `Single landmark point`, `Three landmark points`, `Landmarks, multi points`, `Color channels, multi points`, `Automatic feature-based`, `Automatic feature-based v2`, `AMST: median-smoothed template`
- `CorrelateWith` (uidropdown) — `Previous slice`, `First slice`, `Relative to`
- `correlateWithText` (uilabel)
- `CorrelateStep` (uispinner, integer ≥ 1) — enabled only when `CorrelateWith = Relative to`
- `ColorChannel` (uidropdown)
- `IntensityGradient` (uicheckbox)
- `landmarkHelpText` (uilabel) — populated by `algorithm_Callback`

**Transformation panel:**
- `TransformationType` (uidropdown) — `translate, rigid, non reflective similarity, similarity, affine, projective`
- `TransformationMode` (uidropdown) — `extended, cropped`
- `TransformationDegree` (uidropdown) — `2 (min: 6 pnt), 3 (min: 10 pnt), 4 (min: 15 pnt)`

**Feature detection panel** (used by feature-based + AMST in Phase 3):
- `FeatureDetectorType` (uidropdown) — 8 detectors
- `previewFeaturesBtn` (uibutton)
- `MedianSize` (uispinner, AMST only)
- `UseParallelComputing` (uicheckbox)

**Subarea panel:**
- `Subarea` (uidropdown) — `Full image, Manually specified, Selection, Mask`
- `minX`, `minY`, `maxX`, `maxY` (uispinner)
- `getSearchWindow` (uibutton)

**Background color panel:**
- `BackgroundColor` (uidropdown) — `White, Black, Mean, Custom`
- `BackgroundColorCustom` (uieditfield text) — currently optional; `CustomColorValue` is the spinner used by the runtime
- `CustomColorValue` (uispinner, integer)

**Drift-correction running-average panel:**
- `SubtractRunningAverage` (uicheckbox)
- `SubtractRunningAverageStep` (uispinner)
- `SubtractRunningAverageExcludePeaks` (uispinner)
- `SubtractRunningAverageFixStretch` (uicheckbox)
- `SubtractRunningAverageFixShear` (uicheckbox)
- `SubtractRunningAverageExcludeStretchPeaks` (uispinner)
- `SubtractRunningAverageExcludeShearPeaks` (uispinner)

**Save / load shifts panels:**
- `SaveShiftsToFile` (uicheckbox), `saveShiftsXYpath` (uieditfield)
- `loadShiftsCheck` (uicheckbox), `loadShiftsXYpath` (uieditfield)

**HDD-mode panel:**
- `HDD_Mode` (uicheckbox)
- `HDD_InputDir` (uieditfield), `HDD_SelectDirBtn` (uibutton)
- `HDD_InputFilenameExtension` (uidropdown)
- `HDD_BioformatsReader` (uicheckbox), `HDD_BioformatsIndex` (uispinner)
- `HDD_OutputSubfolderName` (uieditfield)
- `HDD_OutputFileExtension` (uidropdown)

**Bottom buttons:**
- `helpBtn` (uibutton)
- `applyButton` (uibutton — was `continueBtn`)
- `closeButton` (uibutton — was `cancelBtn`)
- `showWaitbar` (uicheckbox)

---

## Constructor & Listener Pattern

Three-signature constructor per `development/guide_to_appdesigner_conversion.md`:

```matlab
controllers.Alignment(mibModel)                  % GUI mode
controllers.Alignment(mibModel, [])              % GUI mode (compat slot)
controllers.Alignment(mibModel, [], BatchOpt)    % headless batch run
controllers.Alignment(mibModel, [], NaN)         % return BatchOpt schema via SyncBatch
```

`addCallbacks` sets `CloseRequestFcn` first then iterates over button-Tag and value-Tag lists, wiring each to `@(s,e) obj.gui_Callbacks(s,e)`.

`ViewListner_Callback2` is the standard guarded static method listening to `UpdateGuiWidgets` and `NewDataset`.

---

## `gui_Callbacks` dispatcher

Routes by `source.Tag`:

```matlab
switch source.Tag
    case 'applyButton'         → obj.continueBtn_Callback()
    case 'closeButton'         → obj.closeWindow()
    case 'helpBtn'             → web(<help URL>, '-browser')
    case 'Algorithm'           → obj.algorithm_Callback() + updateBatchOptFromGUI
    case minX/minY/maxX/maxY   → obj.subwindowEdit_Callback(source) + updateBatchOptFromGUI
    case 'getSearchWindow'     → obj.getSearchWindow_Callback()
    case 'loadShiftsCheck'     → obj.loadShiftsCheck_Callback() + updateBatchOptFromGUI
    case 'previewFeaturesBtn'  → obj.previewFeaturesBtn_Callback() OR error (Phase 3)
    case 'HDD_BioformatsReader' → toggle HDD_BioformatsIndex.Enable + updateBatchOptFromGUI
    case 'HDD_SelectDirBtn'    → uigetdir → write to HDD_InputDir + updateBatchOptFromGUI
    otherwise                  → updateBatchOptFromGUI(source)
end
```

The `otherwise` branch keeps the dispatcher short — every widget that has no side-effect beyond writing back to `BatchOpt` falls through it.

---

## `continueBtn_Callback` — algorithm dispatcher

1. Reject 5D datasets (`image.time > 1 && image.depth > 1`).
2. HDD-mode hard exclusions (only Drift correction, Template matching, and feature-based variants support HDD).
3. Build the shared `parameters` struct from `BatchOpt`:
   - `colorCh`, `backgroundColor` (incl. `Custom` value), `refFrame` (0 / 1 / `-CorrelateStep`)
   - `method`, `TransformationType` (spaces stripped, `piecewise linear` → `pwl`), `TransformationMode`, `transformationDegree` (`2/3/4` → `2/3/4`+1 to match MIB2 indexing)
   - `IntensityGradient`, `UseParallelComputing`
   - `Subarea`, `minX/minY/maxX/maxY` (numeric — already spinner values)
4. Switch on `BatchOpt.Algorithm{1}`:
   - Phase 1: `Drift correction` / `Template matching` → `DriftCorrection_Alignment`; `Single landmark point` → `SingleLandmark_Alignment`.
   - Phase 2/3: emit `showErrorDialog(... 'not yet ported ...')` so the dispatcher is complete and testable from day one.

---

## Dialog patterns

**`questdlg` → `utils.dlgs.inputQuestDlg`** (questdlg-compatible signature):

```matlab
opt.Icon = 'puffin_question';
opt.WindowStyle = 'modal';
answer = utils.dlgs.inputQuestDlg(obj.view.gui, ...
    'Use which layer for landmark detection?', 'Single landmark', ...
    'Annotations', 'Selection', 'Cancel', 'Annotations', opt);
if isempty(answer) || strcmp(answer, 'Cancel'); return; end
```

**`errordlg` → `utils.dlgs.showErrorDialog`** with plain text or with an `MException`:

```matlab
utils.dlgs.showErrorDialog(obj.view.gui, 'Wrong number of landmarks', 'Alignment');
```

**Every `try/catch` block** uses the same helper, passing the caught `MException` directly:

```matlab
try
    shifts = utils.align.calcShifts(I, parameters);
catch ME
    utils.dlgs.showErrorDialog(obj.view.gui, ME, 'Alignment');
    if ~isempty(pwb); pwb.deletePoolWaitbar(); end
    return;
end
```

**`warndlg` / `msgbox` (informational with body)** → `inputUniversalDlg` with `MsgBoxOnly`:

```matlab
dlgOpt.MsgBoxOnly  = true;
dlgOpt.Icon        = 'puffin_warning';
dlgOpt.HeaderLines = 1;
utils.dlgs.inputUniversalDlg(obj.view.gui, 'No landmarks found', {''}, ...
    {'Add landmarks via the Annotation tool, then retry.'}, 'Alignment', dlgOpt);
```

---

## Progress / cancellation pattern

Every long loop in every alignment method follows this template:

```matlab
pwb = [];
if obj.BatchOpt.showWaitbar
    pwb = core.PoolWaitbar(numIter, 'Calculating shifts...', obj.view.gui, ...
        'Alignment', true);    % Cancelable = true
end
cleanupWb = onCleanup(@() safeDeleteWaitbar(pwb));   % leak-free teardown

for sliceIdx = 1:numIter
    if ~isempty(pwb)
        if pwb.getCancelState(); return; end       % cancel-check at top
        pwb.increment();
    end
    % ... per-slice work ...
end

% Before any irreversible write
if ~isempty(pwb) && pwb.getCancelState(); return; end
pwb.updateText('Applying shifts...');
% ... apply shifts via setData4D / utils.align.crossShiftStack ...
```

`utils.align.calcShifts` and `utils.align.crossShiftStack` accept `options.waitbar = pwb` and forward `getCancelState()` polling internally; they return `[]` on cancellation.

**Backup before any write**: every alignment method calls `obj.mibModel.backup('mibDataset', 1, struct('id', id))` before the apply phase so undo (Ctrl+Z) restores the full pre-alignment state.

---

## Conversion rules applied throughout (recap)

- `obj.View` → `obj.view`; `okBtn_Callback`/`cancelBtn_Callback` → `applyButton_Callback`/`closeButton_Callback`.
- Orientation `4` → `3` everywhere; `'model'` data type → `'labels'`.
- `setData4D` argument swap: dataset first in MIB3.
- `getData*` `[]` not `NaN` for current slice/orient.
- `BatchOpt.id` (when present) seeded with `obj.mibModel.getActiveId()` — never `obj.mibModel.id`.
- `obj.mibModel.I{id}.depth/width/height/pixSize` → `obj.mibModel.I{id}.image.depth/width/height/pixSize`.
- `obj.mibModel.I{id}.getBoundingBox()` → `obj.mibModel.I{id}.image.boundingBox`.
- `obj.mibModel.mibDoBackup` → `obj.mibModel.backup`.
- `clearMask` → `clearLayer('mask', '4D')`; `clearSelection` → `clearLayer('selection', '4D')`.
- `containers.Map` → `dictionary(keys, values)` (R2022b+).
- `'r'`/`'g'` color strings → RGB triplets.
- Spinner BatchOpt shape `{value, [min max], roundFlag}`; never `str2double` on spinner values.
- Event renames: `updateGuiWidgets` → `UpdateGuiWidgets`, `plotImage` → `ShowImage`, `updateId` → `UpdateGuiWidgets`, `updatedAnnotations` → `UpdateAnnotations`.
- `mibBatchSectionName` `'Menu -> ...'` → `'Ribbon -> Dataset'`.
- All docblocks RST per `development/docs_api_sphinx.md` — `% FUNCNAME - desc.`, `Syntax:` directive without blank line, `**bold**` params with `—` em-dash, `*(optional)*`, `.. code-block:: matlab`, struct fields in nested bullet list with leading blank `%` line.
- `getDatasetDimensions` arity differs by class:
  - `MibDataset.getDatasetDimensions(type, orient, options)` (used here)
  - `MibImage.getDatasetDimensions(orient, splitDims, blockModeSwitch)` — wrong receiver gives "Too many input arguments"
- **Image-data dim order is MIB3 5-D `[h, w, d, c, t]`** — *never* permute to MIB2's `[h, w, c, d]` internally. `cell2mat(getData4D(...))` already returns this layout; drop the time axis with `arr(:,:,:,:,1)` (preserves the color axis) instead of `squeeze` (which drops single-channel `c=1` along with `t=1`). All helpers in `+utils/+align/` consume / emit MIB3 layout, including 3-D service-layer stacks `[h, w, d]` (no leading-color dim).
- **`MibImage` has `maxInt` as a direct property, not a `meta` dictionary entry.** Use `obj.mibModel.I{id}.image.maxInt` for the white-fill background colour; do *not* write `obj.mibModel.I{id}.image.meta('MaxInt')` — `meta` lives on `MibDataset`, not on `MibImage`, and the `getMeta` / `setMeta` methods that build it are encapsulated.
- **Undo of `'mibDataset'` snapshots requires a `keepBackup` flag on the trailing `NewDataset` event** so `listener_newDataset` does not wipe the just-stored snapshot via `Backup.clearContents()`. Fire as `notify(obj.mibModel, 'NewDataset', core.ToggleEventData(struct('index', id, 'keepBackup', true)))` after any in-place dataset rewrite that called `backup('mibDataset', 1, ...)` first. `MibController.listener_newDataset` reads `Parameters.keepBackup` and skips the `clearContents()` step when set; fresh loads still clear history because they do *not* set the flag.
- **`fitgeotrans` returns legacy `affine2d` / `projective2d` types** whose `.T` property is writable, so cumulative composition `t2.T = t2.T * t1.T` continues to work in MATLAB R2024a+. Polynomial / piecewise-linear tform types have no `.T` matrix — skip the composition (or guard with `isprop(t, 'T')`) for those.

---

## Phase plan

### Phase 1 — Runnable controller + simplest 2 algorithms ✅ COMPLETE

1. ✅ Port `mibCalcShifts` → `utils.align.calcShifts`.
2. ✅ Port `mibCrossShiftStack` → `utils.align.crossShiftStack`.
3. ✅ Port `mibSubtractRunningAverage` → `utils.align.subtractRunningAverage`.
4. ✅ Write `Alignment.m` with full BatchOpt (excluding TwoStacks fields), constructor, `addCallbacks`, `updateWidgets`, `closeWindow`, `returnBatchOpt`, `updateBatchOptFromGUI`, `ViewListner_Callback2`, `findMatchingPairs`.
5. ✅ Write `gui_Callbacks.m` dispatcher routing every Tag.
6. ✅ Write `continueBtn_Callback.m` algorithm-dispatcher with stubs for unported algorithms.
7. ✅ Write `DriftCorrection_Alignment.m` (in-memory drift + template matching).
8. ✅ Write `SingleLandmark_Alignment.m` (Annotation + Selection paths).
9. ✅ Write small UI action methods (`algorithm_Callback`, `subwindowEdit_Callback`, `getSearchWindow_Callback`, `loadShiftsCheck_Callback`).
10. ✅ Wire `Tools/Alignment...` ribbon entry to `controllers.Alignment` (`@MibRibbon/datasetAlignment_Callback.m`).
11. ✅ Static analysis pass (`mcp__matlab__check_matlab_code` clean across all 14 new/modified `.m` files).

**Phase 1 verification — partial (needs `AlignmentGUI.mlapp` for the dropdown / spinner widgets):**

- ⬜ Open MIB3, load a Z-stack, click Dataset → Alignment → dialog appears with all widgets populated from `BatchOpt`.
- ✅ `Algorithm = Drift correction`, click Apply → runs end-to-end after the runtime + layout fixes below; canvas grows correctly, undo (Ctrl+Z) and toolbar arrow restore pre-alignment state.
- ⬜ `Algorithm = Single landmark point` end-to-end (Selection-centroid + Annotation paths) — code paths fixed alongside Drift correction; awaiting user verification with landmarks.
- ⬜ Headless batch round-trip: `controllers.Alignment(obj.mibModel, [], NaN)` → `SyncBatch` event delivers a `BatchOpt` whose shapes match the widget table.
- ✅ Batch-mode dispatch (`controllers.Alignment(obj.mibModel, [], BatchOpt)`) — runs without crashing on the missing view (was previously hitting `obj.view.handles` on a `[]` view).
- ✅ `SaveShiftsToFile` / `loadShiftsCheck` round-trip for Single landmark — `obj.shiftsX/Y` populated triggers the load path, post-run save writes a `.coefXY` for replay.

#### Phase 1 runtime fixes (2026-05-09)

After the GUI was first wired up, three categories of crash surfaced and were fixed:

1. **`backup('mibDataset', 1, ...)` crashed in `core.MibBackup.store`** — the `'mibDataset'` branch of `models.MibModel.backup` passed a `core.MibDataset` instance into `store`, but `store` only special-cased the legacy `'mibImage'` literal and otherwise indexed `data{roiId}`. Fixes:
   - Renamed `'mibImage'` → `'mibDataset'` in `core.MibBackup.store` (3 sites + docs) and in `replaceItem` docs; the `isa(obj.undoList(1).data, 'mibImage')` guard in `store` now tests `core.MibDataset`.
   - Renamed `models.MibModel.imageDeepCopy` → `models.MibModel.deepCopyDataset`. The new method accepts `toId = []` to return a free-standing deep copy without touching `obj.I` (used by `backup` and `undo` for snapshots), and still installs the result into `obj.I{toId}` when `toId` is non-empty (used by `CropDataset`, the buffer-copy context menu, etc.). Old call-sites in `@CropDataset/CropDataset.m` and `@MibActiveDataset/buffers_ContextMenu.m` updated.
   - `models.MibModel.backup` (mibDataset branch) and `models.MibModel.undo` (both `'mibDataset'` snapshot points) now call `obj.deepCopyDataset(id, [], struct('showWaitbar', false))` instead of the shallow `copy(obj.I{id})`. **Net effect: Ctrl+Z after an alignment now restores the full `MibDataset` (image + labels + mask + selection + ROI + annotations + lines3D + measurements).**

2. **`setData4D` size mismatch on the enlarged canvas** — alignment grows `height` / `width`, but `MibImage.setData` writes into the existing fixed-size `data{1}` and errored with `"Unable to perform assignment because the size of the left side is 887-by-813-by-171 and the size of the right side is 890-by-815-by-171"`. Fix: in both `DriftCorrection_Alignment.m` and `SingleLandmark_Alignment.m` adopt the canvas-replace pattern from `ResampleDataset` / `CropDataset`:
   - Replace `image.data{1}` directly with `reshape(imageStackOut, [newH, newW, depth, colors, time])`, then update `image.height` / `image.width` / `image.dim_yxzct`.
   - **Sync `MibDataset.dim_yxzct` and `slices` BEFORE any subsequent `setData4D`** for service layers — the layer setters validate against the dataset dims and would otherwise see the old size.
   - For each populated service layer (`labels` / `mask` / `selection`, or the packed `everything` for `core.MibLabels63`), pre-allocate `obj.<layer>.data{1}` at the new dims and update its `height` / `width` / `dim_yxzct` before calling `setData4D`.

3. **Batch-mode crash on `obj.view.handles`** — running the controller from `BatchProcessing` constructs it with no view (`obj.view` is `[]`), but `continueBtn_Callback`, `DriftCorrection_Alignment`, and `SingleLandmark_Alignment` referenced `obj.view.gui` and `obj.view.handles` unconditionally. Fix:
   - Removed the dead `if useBatchMode && isfield(obj.view.handles, 'loadShiftsCheck')` no-op block in `continueBtn_Callback`.
   - At the top of each algorithm method (and `continueBtn_Callback`), compute `parentFig = obj.view.gui` when the view is alive, else `obj.mibModel.mibGUI`. Every dialog (`showErrorDialog`, `inputQuestDlg`, `inputUniversalDlg`) and the `core.PoolWaitbar` constructor now consume `parentFig` instead of `obj.view.gui`.
   - Threaded `parentFig` into the local helpers `computeShifts(obj, parameters, pwb, parentFig)` and `saveShiftsToFile(obj, id, useBatchMode, parentFig)`. `saveShiftsToFile` also guards `obj.view.handles` access with an `isvalid(obj.view)` check.
   - The remaining `obj.view.handles` reads (in `gui_Callbacks`, `algorithm_Callback`, `subwindowEdit_Callback`, `getSearchWindow_Callback`, `loadShiftsCheck_Callback`) only fire from widget callbacks, so they only execute when the GUI is alive.

#### `inputQuestDlg` button auto-sizing (2026-05-09)

`mib/+utils/+dlgs/inputQuestDlg.m` previously hard-coded `btnW = 100 px`, which clipped long labels (e.g. *"Apply current values"*, *"Quit alignment"*) used by the alignment confirmation dialogs. Fixed:

- Each button is now sized as `max(100 px, label_chars × 0.65 × ButtonFontSize + 12 px padding)` so short labels keep the original look and long labels grow to fit.
- `btnsTotalW` is computed as the sum of the per-button widths plus inter-button gaps; `btnGrid.ColumnWidth = num2cell(btnWidths)` gives each button its own column.
- `WindowWidth` is grown (never shrunk) when the button row plus the icon column would otherwise crowd the question label: `neededWidth = btnsTotalW + iconW + 40`.

#### Phase 1.5 — multi-channel layout fix ✅ DONE (2026-05-10)

Initial port of `crossShiftStack` permuted the data to MIB2's `[h, w, c, d]` internally and then squeezed back, which mis-indexed colour channels as slices for multi-channel images and caused the eventual `setData4D` to reshape into the wrong dims (one user run produced a `18835×20724×1×171 (62 GB)` allocation when stale shifts from a previous landmark run leaked in and the dim order put them on the wrong axis). Fixes:

- `utils.align.crossShiftStack.m` rewritten to allocate `zeros([newH, newW, depth, colors, times], ...)` directly and place each slice via `imgOut(yOff:yOff+h-1, xOff:xOff+w-1, k, :, :) = imgIn(:, :, k, :, :)`. `size(imgIn, 1:5)` handles 3-D service layers and 4-D / 5-D image stacks uniformly — no `permute`, no `squeeze`.
- `utils.align.crossShiftStacks.m` rewritten the same way: input is `[h, w, d, c]` (or `[h, w, d]` with `modelSwitch=1`); the `permute(I, [1 2 4 3])` round-trip and the closing `squeeze` are gone.
- `ThreeLandmarks_Alignment.m` no longer permutes around the image warp. `cell2mat(getData4D(...))(:,:,:,:,1)` drops only the time axis (preserves `c=1` for grayscale). `warpStack4D` iterates over depth dim 3 and uses `reshape` only as a no-copy view into the `[h, w, 1, c]` slab handed to `imwarp`. Final write-back to `image.data{1}` is a plain `reshape` to 5-D.
- `LandmarkMultiPoint_Alignment.m` (extended mode) assembles the new canvas as `zeros(newH, newW, depth, nColors, ...)` directly (was `[h, w, c, d]`) and places each warped slice via `Iout(y1:y2, x1:x2, layer, :) = reshape(iMatrix{layer}, ..., 1, nColors)`. The canvas-replace step is just `reshape` — no permute.

Result: multi-channel image stacks now flow through alignment without any layout conversion; service layers still travel as 3-D `[h, w, d]` via `modelSwitch=1`.

#### `MibImage.maxInt` vs. `meta('MaxInt')` (2026-05-10)

Initial ports of `ThreeLandmarks_Alignment` and `LandmarkMultiPoint_Alignment` followed the MIB2 idiom `obj.mibModel.I{id}.meta('MaxInt')` for the white-fill background colour, but `MibImage` exposes `maxInt` as a direct property (`MibImage.m:68`) — there is no `meta` dictionary on `MibImage` (only on `MibDataset`, via `getMeta` / `setMeta`). Both algorithm methods now read `img5D.maxInt` directly. **Recap of the rule for future ports** in the "Conversion rules" section.

#### Undo / `keepBackup` pattern (2026-05-09 → 2026-05-10)

After backup + in-place rewrite, the trailing `notify('NewDataset')` was triggering `MibController.listener_newDataset` → `Backup.clearContents()` (the standard "fresh dataset loaded, drop undo history" hook), which wiped the snapshot just stored by `backup('mibDataset', 1, ...)`. Ctrl+Z and the toolbar redo arrow both went dead immediately after the alignment. Fix:

- `models.MibModel.undo` (the mibDataset branch) and every alignment method now fire `notify('NewDataset', core.ToggleEventData(struct('index', id, 'keepBackup', true)))` after the in-place rewrite.
- `MibController.listener_newDataset` reads `Parameters.keepBackup` and skips the `clearContents()` step when the flag is set; fresh loads (loaders / drag-drop) leave the flag absent, so they still clear history as before.
- Pattern documented in "Conversion rules" so it carries over to ResampleDataset / CropDataset / future canvas-rewriters.

### Phase 2 — Landmark-based methods ✅ DONE

- ✅ `utils.align.crossShiftStacks.m` — accepts `options.modelSwitch` for 3-D service layers and reuses an existing `core.PoolWaitbar` for cancel polling.
- ✅ `ThreeLandmarks_Alignment.m` — modernised to `fitgeotrans` + `imwarp`; finds the first slice pair with ≥3 Selection-layer connected components, fits a 2-D affine, warps the tail `[layer+1..Depth]` and concatenates it to the unchanged head via `crossShiftStacks`. Applies the same warp to labels / mask / selection (or the packed `everything` for `core.MibLabels63`). Uses the canvas-replace pattern + `dim_yxzct` / `slices` sync from Phase 1; calls `backup('mibDataset', 1, ...)` first so Ctrl+Z restores the full pre-alignment dataset.
- ✅ `LandmarkMultiPoint_Alignment.m` — fits a per-slice geometric transform (`fitgeotrans` with `nonreflectivesimilarity` / `similarity` / `affine` / `projective` / `pwl` / `polynomial`); minimum-landmark count derived from the transform type (2/3/4/6). Annotation source matched by label name; selection source matched via `controllers.Alignment.findMatchingPairs` after forward-projection through the previous slice's cumulative tform. Supports both `cropped` (in-place per-slice `setData2D`) and `extended` (canvas grows; canvas-replace pattern + service-layer container pre-resize). Service layers (`labels` / `mask` / `selection` or packed `everything`) warped with nearest-neighbour and re-assembled on the new canvas. Annotations relocated via `transformPointsForward` + canvas-offset shift. Tform matrices + spatial references persist to `obj.shiftsX / .shiftsY`; `SaveShiftsToFile` writes them to `.coefXY` for replay via `loadShiftsCheck`.
- ✅ `LandmarkMultiPointColor_Alignment.m` — within-slice colour-channel alignment (no propagation across slices). Each slice's annotations split by `labelValues`: `value == 1` = fixed channel, `value == 2` = channel to transform; pairs matched by annotation text label. Per-slice `fitgeotrans` on the paired `[x, y]` coordinates, then `imwarp` with `'OutputView', imref2d([H, W])` applied to the single transformed colour channel via `setData2D('image', warped, layer, [], parameters.colorCh, …)`. Only **cropped** mode supported (matches MIB2 — extended rejected up front). `backup('mibDataset', 1, ...)` + `keepBackup=true` on the trailing `NewDataset` notify; transforms persisted to `obj.shiftsX / .shiftsY` and optionally saved to `.coefXY` via `SaveShiftsToFile`.
- Verification: place 3+ pairs (value 1 + value 2 with matching text) on each slice, run colour-channel alignment, confirm only the selected channel is transformed and the alignment is replayable through `loadShiftsCheck`.

### Phase 3 — Feature-based + AMST + HDD ✅ ALGORITHMS COMPLETE (UI / `.mlapp` + verification pending)

- ✅ `utils.align.detectFeatures.m` — pure dispatcher over the `detect{SURF,SIFT,MSER,Harris,BRISK,FAST,MinEigen,ORB}Features` functions, parameters drawn from the active branch of `obj.automaticOptions`.
- ✅ `previewFeaturesBtn_Callback.m` — interactive matching preview: takes the current and next slice, applies the same downsampling ratio the alignment would use (`imgWidthForAnalysis / Width` for v1 or `1 / imgDownsamplingFactorForAnalysis` for v2), detects features, extracts descriptors (`'Upright'` flag honours `automaticOptions.rotationInvariance`, ORB skipped), matches, runs `estgeotform2d` for RANSAC inlier selection, and renders both *with-outliers* and *inliers-only* views in a tagged figure (`Tag='mib_FeaturePreview'`) so subsequent previews reuse the same window. No-op when active algorithm is AMST. Skips the `automaticOptions` settings dialog for now — runs with whatever defaults are already in `obj.automaticOptions`; the dialog will land with the `automaticOptions` Phase 3 item.
- ✅ `AutomaticFeatureBased_Alignment.m` (in-memory v1) — per-slice `utils.align.detectFeatures` → `extractFeatures` (`'Upright'` flag drives `rotationInvariance`, ORB skips the flag) → `matchFeatures` → `estgeotform2d` RANSAC. Per-slice transforms wrapped to legacy `affine2d` / `projective2d` form via a local `makeLegacyTform` helper (handles `rigidtform2d` / `simtform2d` / `affinetform2d` / `projtform2d` from `estgeotform2d` by transposing `.A` into `.T`), so the cumulative composition `t.T = t.T * prev.T` keeps working. Cropped + extended apply modes inlined from the `LandmarkMultiPoint_Alignment` pattern (canvas-replace, service-layer pre-resize, annotation relocation). Running-average smoothing in GUI mode runs the full interactive flow (`interactiveSmoothingV1`: figure 125 scaling+shear plot, three-way dialog Yes/Subtract/Quit, spinner-settings loop, re-plot, second dialog); in batch mode runs from `BatchOpt.SubtractRunningAverage*` fields. Standard frame: `backup('mibDataset', 1, …)` + `keepBackup=true` notify, cancelable `core.PoolWaitbar`, `parentFig` helper. The `updateAutomaticOptions` settings dialog is skipped — runs from the defaults already in `obj.automaticOptions`.
- ✅ `AutomaticFeatureBasedV2_Alignment.m` — modern (R2022b+) feature-based registration. Uses `estgeotform2d` with native `affinetform2d` / `rigidtform2d` / `simtform2d` return types, wrapped uniformly into `affinetform2d` via its `.A` property. Stores **pairwise** transforms separately from **cumulative** ones and decomposes each pairwise matrix into translation `[tx, ty]`, rotation `θ`, scale `s` (and full 2×2 block for affine). Cumulative parameters built with `cumsum`/`cumprod`; running-average smoothing acts on those parameter arrays (translation / rotation / scale) independently, then the cumulative tforms are rebuilt from the smoothed parameters. For `translation` mode the cumulative `[1,3]` / `[2,3]` entries are rounded to integer pixels so the warped stack is resampling-blur-free. Extended canvas computed by **corner projection** (transforming the four image corners through every cumulative tform and unioning the bounding box — a tighter canvas than the per-slice `imref2d` limits used by v1). Apply phase inlined (uses `imwarp(..., 'OutputView', refImgSize)` for image + service layers in both modes — different enough from v1's canvas-tile pattern that it wasn't worth forcing through the shared helpers). Allowed types `translation` / `rigid` / `similarity` / `affine`; ratio = `1 / imgDownsamplingFactorForAnalysis`. Persists state as a struct (`pairwiseTforms` / `cumulativeTforms` / decomposition arrays) in `obj.shiftsX` so it can replay; `SaveShiftsToFile` writes the same struct to `.coefXY` via `save('-struct', ...)`.
- ✅ `AutomaticFeatureBasedHDD_Alignment.m` — streaming v1 feature-based. Builds the same `imageDatastore` + `io.loadImagesWrapper` chain as HDD drift. Phase 1: `parfor` over every file detects features with `utils.align.detectFeatures` and extracts descriptors via `extractFeatures` — only the descriptors + valid-point locations + dimensions are kept in memory, never the images. Phase 2: sequential pair-match (`matchFeatures`) + RANSAC fit (`estgeotform2d`, seeded by `rng(0,'twister')` for reproducibility) + cumulative legacy-`.T` composition via local `makeLegacyTform`. Running-average smoothing in GUI mode runs `interactiveSmoothingHDD` (same figure-125 plot+dialog pattern as v1, extraction `2:vec_length` skipping slice-1 identity to avoid biasing the running average — matches v1's convention so the smoothed curves agree); batch mode uses `smoothFeatureChain` when `SubtractRunningAverage` is set. Phase 3 (apply): cropped uses slice-1 dimensions for `imref2d`; extended uses per-slice `affineOutputView(..., 'BoundsStyle', 'FollowOutput')` (minimum bounding box — same world coords as `imwarp` without `OutputView`), computes union canvas (`nWidth = max(xmax) - dx`, no extra `abs(dx)` term), warps without `OutputView`, then tiles each patch at pixel offset `(xmin-dx+1, ymin-dy+1)` into a blank `[nHeight, nWidth]` canvas filled with `bgImage`. Apply loops run under `parfor` when `UseParallelComputing` is set. Each warped canvas is wrapped in `core.MibImage` and saved to `<InputDir>/HDD_OutputSubfolderName` via `core.MibImage.save`. Bug history: original port used `affineOutputView`'s default `BoundsStyle` (which keeps the input image's coordinate frame instead of the warped bounding box) + `nWidth = max(xmax) - dx + abs(dx)` (double-counted negative dx) + an ad-hoc world-limit anchor formula — all three replaced with the bounding-box-matching pattern (empirically verified `affineOutputView(..., 'FollowOutput')` produces identical `XWorldLimits` / `YWorldLimits` / `ImageSize` to `imwarp` without `OutputView`). The `.T` element-by-element write-back (`tformMatrix{k}.T(1,1) = …`) was also replaced with full-matrix assignment because `affine2d`'s setter rejects intermediate partial states. No in-memory dataset is modified — no backup, no `NewDataset` notify.
- ✅ `AutomaticFeatureBasedHDDV2_Alignment.m` — streaming v2 feature-based. Mirrors the HDD v1 streaming structure but uses v2's machinery: native `affinetform2d` throughout (`.A` premultiply), pairwise transforms stored separately from cumulative, per-pair decomposition into translation `[tx, ty]` / rotation `θ` / scale `s` (and full 2×2 block for affine), cumulative via `cumsum` / `cumprod`. Running-average smoothing acts on the decomposed parameter arrays independently (translation / rotation / scale) and the cumulative tforms are rebuilt from the smoothed parameters; for `translation` mode the cumulative `[1,3]` / `[2,3]` entries are rounded to integer pixels. Extended canvas computed by **corner projection** (per-file corners through that file's cumulative tform, unioned bounding box) and built as an explicit `imref2d([H, W], [minX, maxX], [minY, maxY])`. Apply uses `imwarp(..., 'OutputView', refImgSize, ...)` directly — the v2 canvas already encodes positioning, so no manual tiling is needed. `rng(0, 'twister')` before the matching loop matches the in-memory v2 for direct comparison. Apply loop runs under `parfor` when `UseParallelComputing` is set. Persists state as a struct (`pairwiseTforms` / `cumulativeTforms` / decomposition arrays / per-file `heightVec` / `widthVec`) in `obj.shiftsX` so it can replay; `SaveShiftsToFile` writes the same struct to `.coefXY` via `save('-struct', ...)`.
- ✅ `AlignMedianSmoothTemplate_Alignment.m` (AMST) — intensity-based registration. Pulls the full 3-D image as `movingImg`, optionally downsamples by `imgWidthForAnalysis / Width`, builds the **template** via `medfilt3(movingImg, [1, 1, MedianSize], 'replicate')` (Z-axis median that compensates for local deformations), then registers each slice to its templated counterpart via `imregtform` (`'monomodal'` mode, optimizer parameters from `obj.automaticOptions.amst.{MaximumIterations, GradientMagnitudeTolerance, MinimumStepLength, MaximumStepLength, RelaxationFactor}`, `PyramidLevels` from `automaticOptions.amst.PyramidLevels`). Translation components scaled back to full resolution after the downsampled fit. **Cropped-only** (matches MIB2; extended raises an error). Allowed types `translation / rigid / similarity / affine` — `projective` and `nonreflectivesimilarity` are rejected / mapped (imregtform limitation). Pre-alignment expectation confirmed via `inputQuestDlg` ("AMST expects a pre-aligned stack — continue?"). Optional parfor (gated by `BatchOpt.UseParallelComputing`, limit from `obj.mibModel.cpuParallelLimitMax`). Running-average smoothing in GUI mode runs `interactiveSmoothingAmst` (figure 125 stretch+shear plot, three-way dialog Apply current values / Fix drifts / Quit, settings loop with re-plot, full-matrix `.T` write-back); batch mode runs `smoothAmstChain` from `BatchOpt.SubtractRunningAverage*` (uses `runningAverageSmoothPoints` with exclude-peaks). Applies via shared `applyCroppedMode` + `relocateAnnotations` + `saveTformsToFile` private helpers. Standard `backup('mibDataset', 1, …)` + `keepBackup=true` frame.
- ✅ `alignDriftCorrectionHDD_Alignment.m` — streaming drift correction. Builds an `imageDatastore` over `HDD_InputDir` filtered by `HDD_InputFilenameExtension`, using `io.loadImagesWrapper` (MIB3 5-D layout `[H, W, Z=1, C, T=1]`) as the `ReadFcn` — works for all formats including AmiraMesh and BioFormats (`HDD_BioformatsReader` / `HDD_BioformatsIndex` honoured). Phase 1 walks the datastore pair by pair: FFT cross-correlation, periodic-boundary ambiguity guard, optional Sobel intensity-gradient prefilter, manual ROI (`Subarea = 'Manually specified'`) cropping. Pairwise shifts integrated by `refFrame`: `cumsum` for *Previous slice*, slice-1 FFT kept as reference for *First slice*, windowed-step accumulation + `windv` smoothing for *Relative to N*. Running-average smoothing in GUI mode runs `interactiveDriftSmoothing` (figure 155 shift plot, three-way dialog Apply/Fix/Quit, then delegates to the interactive `utils.align.subtractRunningAverage` loop when "Fix drifts" is chosen); batch mode calls `subtractRunningAverage` directly when `SubtractRunningAverage` is set. Phase 2 re-reads each image, places it onto a padded canvas (size = original + abs(min) + max), wraps into `core.MibImage`, and saves to `<InputDir>/HDD_OutputSubfolderName` in the chosen format via `core.MibImage.save` (format short codes mapped to MIB descriptors). No in-memory dataset is modified, so no `backup` is taken and no `NewDataset` notify is fired — only the output directory is written. Cancelable progress + `parentFig` helper for batch-mode safety.
- ⬜ dedicated `HDD_BioformatsReader_Callback.m` (currently inlined in `gui_Callbacks`).
- ✅ `updateAutomaticOptions.m` — interactive settings dialog (port of MIB2's `updateAutomaticOptions`). Branches on the active `Algorithm`:
  - **AMST** — one dialog with image-downsampling + 6 `imregconfig` optimizer parameters (`PyramidLevels`, `MaximumIterations`, `GradientMagnitudeTolerance`, `MinimumStepLength`, `MaximumStepLength`, `RelaxationFactor`). Includes `HelpUrl` link to the `regularstepgradientdescent` docs.
  - **Feature-based (v1 + v2)** — one dialog per detector: image-downsampling + rotation-invariance flag (skipped for ORB which has no orientation) + 2-4 detector-specific parameters + 3 RANSAC parameters (`MaxNumTrials`, `Confidence`, `MaxDistance`). All 8 `detect*Features` detectors handled (SURF / SIFT / MSER / Harris / BRISK / FAST / MinEigen / ORB). MSER's `RegionAreaRange` accepted as a string and parsed via `str2num`.
  - Native MIB3 widget types: numeric edits for numerics (no `num2str` round-trip), checkbox for rotationInvariance, returns native types via `inputUniversalDlg`.
  - Returns `status` (1 = OK, 0 = cancel); writes back to `obj.automaticOptions` in place.
- ✅ **Dialog wired into all four callers**: `previewFeaturesBtn_Callback`, `AutomaticFeatureBased_Alignment`, `AutomaticFeatureBasedV2_Alignment`, `AlignMedianSmoothTemplate_Alignment`. Algorithm files call it gated on `~useBatchMode && ~shiftsLoaded` so headless / replay paths still skip it. Each algorithm refreshes its downsampling parameter from the dialog before proceeding.
- ✅ **Shared apply-mode helpers extracted to `@Alignment/private/`**: `applyCroppedMode.m`, `applyExtendedMode.m`, `assembleServiceCanvas.m`, `relocateAnnotations.m`, `saveTformsToFile.m`. Visible only to class methods (MATLAB class-folder private subdirectory rule), called without a package prefix. `saveTformsToFile` takes an optional `label` argument so each algorithm can identify itself in the progress message. `LandmarkMultiPoint_Alignment.m` and `AutomaticFeatureBased_Alignment.m` both now delegate to these helpers — ready for the v2 / HDD ports to reuse without further duplication.
- Verification: feature-based v1 alignment of a microscopy stack with each detector type, cropped + extended; AMST on a noisy stack; HDD-mode drift correction on a directory of TIFFs.

---

## Critical files

**Reuse (do not modify):**

- `mib/+utils/+dlgs/inputQuestDlg.m` — for every former `questdlg` call
- `mib/+utils/+dlgs/inputUniversalDlg.m` — for warndlg/msgbox replacements (`MsgBoxOnly` mode)
- `mib/+utils/+dlgs/showErrorDialog.m` — for every former `errordlg` and every `try/catch` block
- `mib/+utils/+dlgs/mibUiGetFile.m`
- `mib/+core/@PoolWaitbar/PoolWaitbar.m`
- `mib/+core/@ChildView/ChildView.m`
- `mib/+utils/fontSizeUpdate.m`, `moveWindowOutside.m`, `updateBatchOptCombineFields_Shared.m`, `updateBatchOptFromGUI_Shared.m`, `updateGUIFromBatchOpt_Shared.m`

**Reference templates** (read for shape, do not modify):

- `mib/+controllers/@ResampleDataset/ResampleDataset.m` — closest analog (PoolWaitbar, multi-mode dispatch, `getData3D/4D` patterns, `setData4D` pre-allocation)
- `mib/+controllers/@CropDataset/CropDataset.m` — split-panel-safe constructor
- `mib/+controllers/@MeasureTool/gui_Callbacks.m` — single-dispatcher pattern reference
- `MIB2_RENAMED_FOR_MIB3/Classes/@mibAlignmentController/*.m` — partially renamed source (starting point for each method file; every conversion rule still needs to be applied)

---

## Verification (end-to-end)

1. **Static analysis**: `mcp__matlab__check_matlab_code` on every modified/created `.m` file → expect zero issues. **Phase 1: ✅ PASSED on all 14 files.**
2. **Build check**: `cd C:\Matlab\MIB3 && buildtool check` runs clean.
3. **Smoke test**: `cd C:\Matlab\MIB3\mib && mib3`, load a stack, open Alignment, exercise the algorithms ported in the current phase.
4. **Cancel test**: start a long alignment, click Cancel mid-run → dialog disappears, no partial write to `mibModel`, undo unaffected.
5. **Batch round-trip**: `controllers.Alignment(obj.mibModel, [], NaN)` → verify `SyncBatch` event delivers a `BatchOpt` whose shapes match the widget table.
6. **Headless run**: build a `BatchOpt` programmatically, call `controllers.Alignment(obj.mibModel, [], BatchOpt)` with a small stack → result identical to GUI.
7. **Visual check**: aligned stack displays correctly in the canvas; `mibModel.I{id}.image.boundingBox` updated; mask/selection layers (if present) shifted consistently.

---

## Current state summary

**Last updated: 2026-05-17**

### Algorithms ported (10 of 10 — all algorithms complete)

| # | Algorithm | In-memory | HDD-mode |
|---|---|---|---|
| 1 | Drift correction / Template matching | ✅ `DriftCorrection_Alignment` | ✅ `alignDriftCorrectionHDD_Alignment` |
| 2 | Single landmark point | ✅ `SingleLandmark_Alignment` | (n/a) |
| 3 | Three landmark points | ✅ `ThreeLandmarks_Alignment` | (n/a) |
| 4 | Landmarks, multi points | ✅ `LandmarkMultiPoint_Alignment` | (n/a) |
| 5 | Color channels, multi points | ✅ `LandmarkMultiPointColor_Alignment` | (n/a) |
| 6 | Automatic feature-based | ✅ `AutomaticFeatureBased_Alignment` | ✅ `AutomaticFeatureBasedHDD_Alignment` |
| 7 | Automatic feature-based v2 | ✅ `AutomaticFeatureBasedV2_Alignment` | ✅ `AutomaticFeatureBasedHDDV2_Alignment` |
| 8 | AMST: median-smoothed template | ✅ `AlignMedianSmoothTemplate_Alignment` | (n/a) |

### Supporting infrastructure (all ✅)

- **Controller skeleton** — three-signature constructor, batch-mode dispatch, listeners, `gui_Callbacks` dispatcher, `continueBtn_Callback` algorithm dispatcher.
- **Backend helpers** in `mib/+utils/+align/` — `windv`, `runningAverageSmoothPoints`, `calcShifts`, `crossShiftStack`, `crossShiftStacks`, `subtractRunningAverage`, `detectFeatures`. All MIB3 5-D layout-native; cancel-aware via `core.PoolWaitbar`.
- **Shared private helpers** in `@Alignment/private/` — `applyCroppedMode`, `applyExtendedMode`, `assembleServiceCanvas`, `relocateAnnotations`, `saveTformsToFile`. Used by Multi-point landmark, feature-based v1, AMST.
- **Interactive settings dialog** — `updateAutomaticOptions.m` ports MIB2's branching dialog; covers AMST + all 8 detectors + RANSAC. Wired into preview + v1 + v2 + AMST (gated on `~useBatchMode && ~shiftsLoaded`).
- **Feature preview** — `previewFeaturesBtn_Callback` renders matched + inlier views in a tagged figure.
- **Undo system** — `core.MibBackup` accepts `'mibDataset'` snapshots; `models.MibModel.deepCopyDataset` returns free-standing deep copy when `toId = []`; `keepBackup=true` flag on `NewDataset` event prevents `listener_newDataset` from wiping the redo snapshot. Ctrl+Z + toolbar redo round-trip the full dataset.
- **`SaveShiftsToFile` / `loadShiftsCheck`** — `.coefXY` round-trip wired for every algorithm that produces persistable transforms (numeric shifts for drift/single, tform+rbMatrix for landmark/feature-based v1/AMST, struct for v2).
- **TwoStacks mode** removed entirely (BatchOpt fields, view widgets, dispatcher branch).
- **Dialog modernisation** — `questdlg` → `inputQuestDlg` (auto-widths long button labels); `errordlg` + every `try/catch` → `showErrorDialog`; `warndlg` / `msgbox` → `inputUniversalDlg(MsgBoxOnly)`.
- **Ribbon button** `Dataset → Alignment` wired.
- **RANSAC reproducibility** — `rng(0, 'twister')` seeded immediately before the per-slice matching loop in `AutomaticFeatureBased_Alignment`, `AutomaticFeatureBasedV2_Alignment`, `AutomaticFeatureBasedHDD_Alignment`, and `AutomaticFeatureBasedHDDV2_Alignment`. Eliminates run-to-run variance from `estgeotform2d`'s MSAC sampling and makes in-memory and HDD variants produce identical tform chains for direct comparison.
- **`notYetPorted` helper removed** — all algorithms are ported; `continueBtn_Callback` no longer has a fallback stub branch.
- **Static analysis**: every new / modified `.m` file clean under `mcp__matlab__check_matlab_code` (the only remaining notes are info-level `readFcn` broadcast warnings on `AutomaticFeatureBasedHDD_Alignment` and `AutomaticFeatureBasedHDDV2_Alignment` — inherent to `parfor` + `imageDatastore`).

### Consistent patterns across every algorithm method

- `backup('mibDataset', 1, ...)` before any in-memory write (HDD variants skip — they write only to the output directory).
- `parentFig` helper (view alive ? `obj.view.gui` : `obj.mibModel.mibGUI`) for batch-mode-safe dialogs.
- Cancelable `core.PoolWaitbar` with `getCancelState()` polled at each phase boundary.
- MIB3 5-D `[h, w, d, c, t]` layout natively — no internal permutes.
- Canvas-replace pattern with `dim_yxzct` / `slices` sync + pre-resized service-layer containers for extended-mode writes.
- `keepBackup=true` flag on the trailing `NewDataset` notify so undo history survives.

### Remaining work

All algorithm methods are now ported. Remaining items are UI polish, defensive hardening, and end-to-end verification:

| Item | Priority | Notes |
|---|---|---|
| ⬜ `mib/+views/AlignmentGUI.mlapp` | **blocker** | User-authored against the widget Tag contract above. The only blocker for end-to-end GUI verification of every algorithm. |
| ⬜ End-to-end GUI verification | **blocker** | All 10 ported algorithms (5 in-memory landmark/drift/AMST + v1/v2 in-memory + v1/v2 HDD + HDD drift) need a run-through once the `.mlapp` lands. Drift correction, single landmark, three landmarks, multi-landmark, color-channel, feature-based v1, feature-based v2, AMST, HDD drift, HDD feature-based v1, and HDD feature-based v2 are individually fixed and verified by static analysis; cross-algorithm regressions can only surface in interactive GUI use. |
| ⬜ Dedicated `HDD_BioformatsReader_Callback.m` | cosmetic | Currently inlined in `gui_Callbacks` (toggles `HDD_BioformatsIndex.Enable`); promote to a method file for symmetry with the other dedicated callbacks. |
| ⬜ Spurious huge-shift defence in `DriftCorrection_Alignment` | defensive | Add a sanity cap (clamp per-slice shifts to `max(W, H) / 2`) and/or auto-clear `obj.shiftsX/Y` at the top of the method so a stale cell-array tform from a previous landmark / feature-based run cannot bleed into the numeric drift path. |

### What's NOT remaining (recently closed)

- ✅ **Interactive smoothing for AMST** — `AlignMedianSmoothTemplate_Alignment` now runs `interactiveSmoothingAmst` in GUI mode (figure 125 stretch + shear plot, three-way dialog Apply current values / Fix drifts / Quit, settings loop with re-plot, full-matrix `.T` write-back). Batch mode still uses `smoothAmstChain`, refactored to use `runningAverageSmoothPoints` with exclude-peaks (was raw `windv` without peak handling) and full-matrix `.T` assignment to match v1's fixed pattern. `safeT` helper handles slices where `imregtform` failed (`tform` empty) by returning identity-element defaults so the plot doesn't crash. (2026-05-17)
- ✅ **HDD v2** — `AutomaticFeatureBasedHDDV2_Alignment.m` written; wired into `continueBtn_Callback` for `Algorithm = 'Automatic feature-based v2'` + `HDD_Mode = true`; method signature registered in `Alignment.m`. (2026-05-17)
- ✅ **HDD v1 extended-mode displacement bug** — `affineOutputView` default `BoundsStyle` does **not** match `imwarp`'s default behaviour (empirically confirmed via `mcp__matlab__evaluate_matlab_code`: default gives centered/input-sized rbMatrix; only `'FollowOutput'` matches `imwarp`'s minimum-bounding-box output). Fixed by passing `'BoundsStyle', 'FollowOutput'` to `affineOutputView`, replacing the wrong `nWidth = max(xmax) - dx + abs(dx)` canvas formula with `nWidth = max(xmax) - dx`, and replacing the ad-hoc world-limit anchor with the in-memory pixel-offset tile pattern. Saved HDD v1 stacks now align identically to the in-memory result. (2026-05-17)
- ✅ **RANSAC noise between in-memory and HDD curves** — was caused by un-seeded `estgeotform2d` MSAC sampling. Fixed by `rng(0, 'twister')` before the per-slice matching loop in all four feature-based methods. (2026-05-16)
- ✅ **`arrayfun` type mismatch on HDD v1 smoothing** — `affine2d.T` elements come back as `single` when the underlying image is `single`; mixed-type cells broke `arrayfun`'s default uniform-output. Fixed by `double()` cast inside all `arrayfun` extractions in `interactiveSmoothingHDD` and `smoothFeatureChain`. (2026-05-16)
- ✅ **Element-by-element `.T` assignment rejected by `affine2d` setter** — `tformMatrix{k}.T(1,1) = value` triggers the property setter on each statement with an intermediate matrix state, and newer MATLAB versions reject intermediates. Fixed by extracting the full `T` to a local variable, modifying all four elements, then assigning the whole matrix back. Applied to both `interactiveSmoothingV1` / `smoothTformChain` (v1 in-memory) and `interactiveSmoothingHDD` / `smoothFeatureChain` (v1 HDD). (2026-05-16)
- ✅ **HDD v1 smoothing curve diverged from in-memory** — extraction range was `1:vec_length` (included the identity slice 1 in the running-average window, biasing early-slice smoothing) while in-memory used `2:vec_length`. Realigned both extract and write-back to `2:vec_length` + `k-1` offset, matching the in-memory convention; verified with side-by-side run of v1 and HDD producing identical curves under fixed RNG seed. (2026-05-16)
