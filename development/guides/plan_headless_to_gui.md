# Converting a MIB2 Headless Model Method to a MIB3 GUI Controller

**Pattern:** MIB2 function on `mibModel` that calls `mibInputMultiDlg` internally → MIB3 standalone child controller with `.mlapp` view, batch mode, and live preview.

**Worked example:** `@mibModel/contrastCLAHE.m` → `controllers.ContrastClahe` + `views.ContrastClaheGUI`

---

## Source vs Output

| | MIB2 | MIB3 |
|-|------|------|
| Logic lives in | `@mibModel/contrastCLAHE.m` (method on model) | `@ContrastClahe/applyFilter.m` (method on controller) |
| Parameters collected by | `mibInputMultiDlg` (modal, blocks execution) | `.mlapp` panel with spinners / dropdowns (non-modal, live) |
| Batch support | `nargin == 3` path in same file | same `nargin == 3` path in constructor |
| Ribbon wiring | `mibController` menu callback | `image_Callbacks.m` switch-case |

---

## Files Created / Modified

### New
```
mib/+controllers/@ContrastClahe/
    ContrastClahe.m     ← class: constructor, callbacks, preview, close
    applyFilter.m       ← processing: preview-mode + full-dataset mode
mib/+views/
    ContrastClaheGUI.mlapp   ← created by user in AppDesigner
```

### Modified
```
mib/+controllers/@MibRibbon/image_Callbacks.m
    case 'Contrast-limited adaptive histogram equalization'
        obj.mibController.startController('controllers.ContrastClahe');
```

### Unchanged (already correct)
```
mib/+utils/+defaults/generateSessionSettings.m
    sessionSettings.CLAHE.NumTiles     = [8 8];
    sessionSettings.CLAHE.ClipLimit    = 0.01;
    sessionSettings.CLAHE.NBins        = 256;
    sessionSettings.CLAHE.Distribution = 'uniform';
    sessionSettings.CLAHE.Alpha        = 0.4;
```

---

## BatchOpt Design: Numeric Cells, Not Text

MIB2 stored numeric params as strings (`num2str`) and parsed them back with `str2double` / `str2num`. MIB3 uses numeric cell format so widgets (spinners) bind directly:

```matlab
% MIB2 — text (do not use)
BatchOpt.ClipLimit = '0.01';          % stored as char
val = str2double(BatchOpt.ClipLimit); % parsed back

% MIB3 — numeric cell
BatchOpt.ClipLimit = {0.01, [0, 1], 'off'};  % {value, [min max], rounding}
val = BatchOpt.ClipLimit{1};                  % direct access, no parse
```

Cell format rules:
- `{1}` — scalar value
- `{2}` — `[min max]` limits for spinner bounds
- `{3}` — `'on'` for integer rounding, `'off'` for float

**NumTiles split:** MIB2 stored `NumTiles` as a 2-element vector `[8 8]` and parsed it from a text field with `str2num`. MIB3 splits into two independent spinners:

```matlab
BatchOpt.NumTilesY = {numTiles(1), [1, 256], 'on'};
BatchOpt.NumTilesX = {numTiles(2), [1, 256], 'on'};
```

Recombined when needed: `[obj.BatchOpt.NumTilesY{1}, obj.BatchOpt.NumTilesX{1}]`

---

## Full BatchOpt Structure

```matlab
obj.BatchOpt.DatasetType    = {'Current stack (3D)'};
obj.BatchOpt.DatasetType{2} = {'Shown slice (2D)', 'Current stack (3D)', 'Complete volume (4D)'};
obj.BatchOpt.ColorChannel    = {'All'};
obj.BatchOpt.ColorChannel{2} = [{'All'}, {'Displayed'}, PossibleColChannels];  % 'ColCh 1', ...
obj.BatchOpt.NumTilesY    = {numTiles(1), [1, 256],   'on'};
obj.BatchOpt.NumTilesX    = {numTiles(2), [1, 256],   'on'};
obj.BatchOpt.ClipLimit    = {clipLimit,   [0, 1],     'off'};
obj.BatchOpt.NBins        = {nBins,       [2, 65536], 'on'};
obj.BatchOpt.Distribution    = {distribution};
obj.BatchOpt.Distribution{2} = {'uniform', 'rayleigh', 'exponential'};
obj.BatchOpt.Alpha        = {alpha, [0, 1], 'off'};
obj.BatchOpt.showWaitbar  = true;
obj.BatchOpt.id           = obj.mibModel.getActiveId();
obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Image';
obj.BatchOpt.mibBatchActionName  = 'Contrast-limited adaptive histogram equalization';
```

Tooltips (one per field, required for batch help):
```matlab
obj.BatchOpt.mibBatchTooltip.DatasetType  = 'Specify part of the dataset for CLAHE';
obj.BatchOpt.mibBatchTooltip.ColorChannel = 'Specify color channels for CLAHE';
obj.BatchOpt.mibBatchTooltip.NumTilesY    = 'Number of tiles in the Y direction (rows)';
obj.BatchOpt.mibBatchTooltip.NumTilesX    = 'Number of tiles in the X direction (columns)';
obj.BatchOpt.mibBatchTooltip.ClipLimit    = 'Contrast enhancement limit [0 1]';
obj.BatchOpt.mibBatchTooltip.NBins        = 'Number of histogram bins for the contrast transformation';
obj.BatchOpt.mibBatchTooltip.Distribution = 'Desired histogram shape: uniform, rayleigh, or exponential';
obj.BatchOpt.mibBatchTooltip.Alpha        = 'Distribution parameter for rayleigh/exponential; ignored for uniform';
obj.BatchOpt.mibBatchTooltip.showWaitbar  = 'Show or not the progress bar during execution';
```

---

## View Widget Tags (ContrastClaheGUI.mlapp)

Widget tags must match `BatchOpt` field names exactly for `updateGUIFromBatchOpt_Shared` / `updateBatchOptFromGUI_Shared` to bind automatically. Use short camelCase names without type suffix.

| Tag | Widget type | BatchOpt field |
|-----|-------------|----------------|
| `DatasetType` | uidropdown | `BatchOpt.DatasetType` |
| `ColorChannel` | uidropdown | `BatchOpt.ColorChannel` |
| `NumTilesY` | uispinner | `BatchOpt.NumTilesY` |
| `NumTilesX` | uispinner | `BatchOpt.NumTilesX` |
| `ClipLimit` | uispinner | `BatchOpt.ClipLimit` |
| `NBins` | uispinner | `BatchOpt.NBins` |
| `Distribution` | uidropdown | `BatchOpt.Distribution` |
| `Alpha` | uispinner | `BatchOpt.Alpha` |
| `showWaitbar` | uicheckbox | `BatchOpt.showWaitbar` |
| `autoPreview` | uicheckbox | — (checked manually in callbacks) |
| `previewButton` | uibutton | — |
| `applyButton` | uibutton | — |
| `helpButton` | uibutton | — |
| `closeButton` | uibutton | — |

**Note:** `autoPreview` is not in BatchOpt — it is a purely local UI toggle checked in `updateBatchOptFromGUI` and `distributionChanged` to decide whether to trigger a preview after each parameter change.

---

## Session Settings Persistence

On **open** (constructor): read from `sessionSettings.CLAHE` into `BatchOpt`.

```matlab
numTiles = obj.mibModel.sessionSettings.CLAHE.NumTiles;  % [8 8]
obj.BatchOpt.NumTilesY{1} = numTiles(1);
obj.BatchOpt.NumTilesX{1} = numTiles(2);
obj.BatchOpt.ClipLimit{1} = obj.mibModel.sessionSettings.CLAHE.ClipLimit;
% ... etc
```

On **close** (`closeWindow`) and after **successful apply** (`applyFilter`): write back.

```matlab
obj.mibModel.sessionSettings.CLAHE.NumTiles     = [obj.BatchOpt.NumTilesY{1}, obj.BatchOpt.NumTilesX{1}];
obj.mibModel.sessionSettings.CLAHE.ClipLimit    = obj.BatchOpt.ClipLimit{1};
obj.mibModel.sessionSettings.CLAHE.NBins        = obj.BatchOpt.NBins{1};
obj.mibModel.sessionSettings.CLAHE.Distribution = obj.BatchOpt.Distribution{1};
obj.mibModel.sessionSettings.CLAHE.Alpha        = obj.BatchOpt.Alpha{1};
```

---

## Constructor Flow

```
ContrastClahe(mibModel)
  ├─ build BatchOpt (from sessionSettings + active dataset)
  ├─ nargin == 3 → batch path:
  │     updateBatchOptCombineFields_Shared → applyFilter() → CloseEvent → return
  └─ GUI path:
        core.ChildView(obj, 'views.ContrastClaheGUI')
        moveWindowOutside → fontSizeUpdate
        updateWidgets → updateGUIFromBatchOpt_Shared → updateAlphaState
        addCallbacks
        gui.Visible = 'on'
        addlistener(UpdateGuiWidgets)
        [SliceChanged listener disabled — no auto-preview on navigation]
```

---

## applyFilter — Dual-Mode Design

The same method handles both preview and full-dataset processing, selected by whether `imgIn` is supplied:

```matlab
function imgOut = applyFilter(obj, imgIn)
    imgOut = [];
    if nargin > 1 && ~isempty(imgIn)
        imgOut = applyAdapthisteq(imgIn, obj.BatchOpt);  % preview: return result
        return;
    end
    % full mode: read model → process → write back → log → notify
end
```

`applyAdapthisteq` is a **file-local function** (not a method) at the bottom of `applyFilter.m`. It loops over channels so it handles both grayscale (H×W) and multi-channel (H×W×C) inputs.

---

## Preview Implementation

`previewButtonPushed` pattern (image layer only — CLAHE never touches labels/mask/selection):

```matlab
% 1. Get the current block slice (at screen resolution, not full dataset)
getDataOptions.blockModeSwitch = 1;
img = cell2mat(obj.mibModel.getData2D('image', [], [], ColCh, getDataOptions));

% 2. Apply filter in preview mode (returns filtered image, no model write)
filteredImg = obj.applyFilter(img);

% 3. Convert to uint8 if 16-bit (apply viewport gamma/min/max first)
if ~isa(filteredImg, 'uint8') && ~obj.mibModel.onFlyImageStretch
    % imadjust per channel then scale
    filteredImg = uint8(filteredImg / 256);
end

% 4. Push to display as overlay (resizeToMagnification handles zoom)
showSettings.resizeToMagnification = true;
showSettings.sImgIn = filteredImg;
notify(obj.mibModel, 'ShowImage', core.ToggleEventData(showSettings));
```

`autoPreview` checkbox: `updateBatchOptFromGUI` and `distributionChanged` call `previewButtonPushed` when `autoPreview.Value` is true, giving live parameter feedback.

---

## Cancelable Progress Bar

```matlab
if obj.BatchOpt.showWaitbar
    waitbarHandle = uiprogressdlg(obj.mibGUI, 'Value', 0, ...
        'Message', sprintf('Applying CLAHE\nPlease wait...'), 'Title', 'CLAHE', ...
        'Cancelable', 'on');
    progressStep = floor(nSteps / 20);   % update UI at most 20 times total
end
```

Cancel check inside the loop (throttled to avoid UI overhead):
```matlab
if obj.BatchOpt.showWaitbar && mod(stepIndex, progressStep) == 0
    waitbarHandle.Value = stepIndex / nSteps;
    waitbarHandle.Message = sprintf('Applying CLAHE (slice %d of %d)\nPlease wait...', stepIndex, nSteps);
    if waitbarHandle.CancelRequested
        cancelRequested = true;
        break;
    end
end
```

Outer loops guard against the flag:
```matlab
for colCh = colorChannel
    if cancelRequested; break; end
    for t = tRange(1):tRange(2)
        if cancelRequested; break; end
        for z = zRange(1):zRange(2)
            ...
        end
    end
end
if obj.BatchOpt.showWaitbar; delete(waitbarHandle); end
if cancelRequested; notify(obj.mibModel, 'ShowImage'); return; end  % show partial result, skip log
```

---

## Key MIB2 → MIB3 API Conversions Applied

| MIB2 | MIB3 |
|------|------|
| `obj.Id` | `obj.mibModel.getActiveId()` |
| `obj.I{id}.colors` | `obj.mibModel.I{id}.image.colors` |
| `obj.I{id}.Virtual.virtual == 1` | `strcmp(obj.mibModel.I{id}.datasetType, 'Virtual')` |
| `obj.I{id}.meta('ColorType')` | `obj.mibModel.I{id}.image.colorType` |
| `obj.I{id}.depth` / `.time` | `obj.mibModel.I{id}.image.depth` / `.time` |
| `obj.getData2D('image', z, NaN, ch, opts)` | `obj.mibModel.getData2D('image', z, [], ch, opts)` |
| `obj.setData2D('image', img, z, NaN, ch, opts)` | `obj.mibModel.setData2D(img, 'image', z, [], ch, opts)` ← data first! |
| `obj.mibDoBackup('image', 1, opts)` | `obj.mibModel.backup('image', 1, opts)` |
| `obj.I{id}.updateImgInfo(text)` | `obj.mibModel.I{id}.image.updateActionLog(text)` |
| `notify(obj, 'plotImage')` | `notify(obj.mibModel, 'ShowImage')` |
| `notify(obj, 'syncBatch', evd)` | `notify(obj.mibModel, 'SyncBatch', evd)` |
| `notify(obj, 'stopProtocol')` | — (error dialog + return is sufficient in controller) |
| `ToggleEventData(x)` | `core.ToggleEventData(x)` |
| `waitbar(v, wb)` | `wb.Value = v` (uiprogressdlg) |
| `BatchOpt.mibBatchSectionName = 'Menu -> …'` | `'Ribbon -> …'` |
| `str2num(BatchOpt.NumTiles)` | `[BatchOpt.NumTilesY{1}, BatchOpt.NumTilesX{1}]` |
| `str2double(BatchOpt.ClipLimit)` | `BatchOpt.ClipLimit{1}` |
