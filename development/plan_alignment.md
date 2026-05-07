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
| `ThreeLandmarks_Alignment.m` | 3-point affine (MIB2 lines 868–959) | 2 | ⬜ pending |
| `LandmarkMultiPoint_Alignment.m` | Multi-point landmark alignment | 2 | ⬜ pending |
| `LandmarkMultiPointColor_Alignment.m` | Color-channel landmark alignment | 2 | ⬜ pending |
| `AutomaticFeatureBased_Alignment.m` (+ V2) | In-memory feature-based registration | 3 | ⬜ pending |
| `AutomaticFeatureBasedHDD_Alignment.m` (+ V2) | HDD-mode feature-based registration | 3 | ⬜ pending |
| `AlignMedianSmoothTemplate_Alignment.m` | AMST | 3 | ⬜ pending |
| `alignDriftCorrectionHDD_Alignment.m` | HDD-mode drift correction | 3 | ⬜ pending |
| `previewFeaturesBtn_Callback.m` | Feature detector preview window | 3 | ⬜ pending |
| `HDD_BioformatsReader_Callback.m` | Enable/disable HDD bioformats index | 3 | ⬜ pending (currently inlined in `gui_Callbacks`) |

### Backend helpers — `mib/+utils/+align/`

| File | Source | Phase | State |
|---|---|---|---|
| `windv.m` | `MIB2\Tools\windv.m` | 1 | ✅ done |
| `runningAverageSmoothPoints.m` | `MIB2\Tools\mibRunningAverageSmoothPoints.m` | 1 | ✅ done |
| `calcShifts.m` | `MIB2\Tools\mibCalcShifts.m` | 1 | ✅ done — takes optional `core.PoolWaitbar` via `options.waitbar` |
| `crossShiftStack.m` | `MIB2\Tools\mibCrossShiftStack.m` | 1 | ✅ done |
| `subtractRunningAverage.m` | `MIB2\Tools\mibSubtractRunningAverage.m` | 1 | ✅ done — uses `inputUniversalDlg` + `inputQuestDlg`; takes parent figure as 1st arg |
| `crossShiftStacks.m` | `MIB2\Tools\mibCrossShiftStacks.m` | 2 | ⬜ pending |
| `detectFeatures.m` | `MIB2\Tools\mibAlignmentDetectFeatures.m` | 3 | ⬜ pending |

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

**Phase 1 verification (pending — needs `AlignmentGUI.mlapp`):**

- Open MIB3, load a Z-stack, click Dataset → Alignment → dialog appears with all widgets populated from `BatchOpt`.
- `Algorithm = Drift correction`, click Apply → progress dialog appears, Cancel works mid-run, alignment completes, `image.boundingBox` updated, `image.height` / `image.width` reflect padded canvas.
- `Algorithm = Single landmark point` after placing a 1-px Selection landmark on each slice → centroid-shift alignment runs end-to-end.
- Repeat with Annotation landmarks (one per slice) → annotation-driven alignment runs end-to-end.
- Headless batch round-trip: `controllers.Alignment(obj.mibModel, [], NaN)` → `SyncBatch` event delivers a `BatchOpt` whose shapes match the widget table.
- `Ctrl+Z` after an alignment restores the pre-alignment state.

### Phase 2 — Landmark-based methods ⬜ PENDING

- `ThreeLandmarks_Alignment.m` (MIB2 lines 868–959 — port via `fitgeotrans` / `imwarp` rather than the deprecated `imtransform`).
- `LandmarkMultiPoint_Alignment.m` (port of MIB2 `LandmarkMultiPointAlignment`).
- `LandmarkMultiPointColor_Alignment.m` (port of MIB2 `LandmarkMultiPointColorAlignment`).
- `utils.align.crossShiftStacks.m` — needed by ThreeLandmarks (apply combined transform + shift).
- Verification: place 3+ landmarks on each of 2 slices, run each algorithm, confirm aligned canvas + service-layer alignment.

### Phase 3 — Feature-based + AMST + HDD ⬜ PENDING

- All `Automatic*FeatureBased*_Alignment.m` files (in-memory + HDD, v1 + v2).
- `AlignMedianSmoothTemplate_Alignment.m` (AMST).
- `alignDriftCorrectionHDD_Alignment.m` (HDD-mode drift correction).
- `previewFeaturesBtn_Callback.m`, dedicated `HDD_BioformatsReader_Callback.m` (currently inlined in `gui_Callbacks`).
- `utils.align.detectFeatures.m` (port of `mibAlignmentDetectFeatures`).
- `automaticOptions` parameter dialog (was MIB2 `updateAutomaticOptions`; will use `inputUniversalDlg` + a settings dialog).
- Verification: feature-based alignment of a microscopy stack with each detector type; AMST on a noisy stack; HDD-mode drift correction on a directory of TIFFs.

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

## Current state summary (Phase 1)

- **14 files created / modified, all green under `mcp__matlab__check_matlab_code`.**
- Backend helpers (`+utils/+align/`) ported with `core.PoolWaitbar` integration and RST docblocks.
- Controller skeleton complete with three-signature constructor, batch-mode dispatch, listeners, `gui_Callbacks` dispatcher, `continueBtn_Callback` algorithm dispatcher.
- Drift correction + Single landmark fully ported with cancelable progress and `try/catch` → `showErrorDialog`.
- TwoStacks mode and all `BatchOpt.TwoStacks*` / `SecondDataset*` fields removed per requirement.
- All `questdlg` → `inputQuestDlg`; `errordlg` / `try-catch` → `showErrorDialog`; `warndlg` / `msgbox` → `inputUniversalDlg(MsgBoxOnly)`.
- Ribbon button (`Dataset → Alignment`) wired.
- **Blocking next step**: user authors `mib/+views/AlignmentGUI.mlapp` against the widget Tag contract above; only then can end-to-end verification proceed.
