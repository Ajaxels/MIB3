# MIB2 → MIB3 Conversion Reference

Detailed lookup tables for porting. See root `CLAUDE.md` for the most common patterns (dialogs, events, data accessors, `getActiveId`).

---

## Parallel Progress: core.PoolWaitbar

**Always use `core.PoolWaitbar` for progress dialogs inside `parfor` / `spmd` / `parfeval`.**
Lives at `mib/+core/@PoolWaitbar/PoolWaitbar.m` — wraps `uiprogressdlg` with `parallel.pool.DataQueue`.

| Pattern | Code |
|---------|------|
| Create (new dialog) | `pwb = core.PoolWaitbar(n, 'Message...', obj.mibGUI, 'Title');` |
| Create (cancelable) | `pwb = core.PoolWaitbar(n, 'Message...', obj.mibGUI, 'Title', true);` |
| Reuse existing dialog | `pwb = core.PoolWaitbar(n, 'Message...', existingWb);` |
| Signal one step (worker-safe) | `pwb.increment();` — the **only** method safe inside `parfor` |
| Set step size | `pwb.setIncrement(10);` — call before parfor to reduce IPC overhead |
| Update message (main thread only) | `pwb.updateText('Phase 2...');` |
| Check Cancel (main thread only) | `if pwb.getCancelState(); break; end` |
| Delete (dialog + queue) | `pwb.deletePoolWaitbar();` |
| Delete (keep dialog open) | `pwb.deletePoolWaitbar(true); wb = pwb.getWaitbarHandle();` |

```matlab
% Typical parfor pattern
pwb = core.PoolWaitbar(max_size, sprintf('Eroding %s...', layerName), obj.mibGUI, 'Eroding...');
pwb.setIncrement(10);
parfor (layer_id = 1:max_size, parforArg)
    % ... heavy work ...
    if mod(layer_id, 10) == 0; pwb.increment(); end
end
pwb.deletePoolWaitbar();
```

Do **not** update `uiprogressdlg.Value` directly inside `parfor` — not thread-safe.
For sequential loops use plain `uiprogressdlg` with `wb.Value = k/n`.

---

## Backup (Undo)

| MIB2 | MIB3 |
|------|------|
| `obj.mibDoBackup('selection', 0, options)` | `obj.mibModel.backup('selection', 0, options)` |
| `obj.mibDoBackup('selection', 1, options)` | `obj.mibModel.backup('selection', 1, options)` |

`backup(type, switch3d, getDataOptions)` — `switch3d=0` for 2D (current slice), `1` for 3D/4D stack.
`getDataOptions.blockModeSwitch = true` to back up only the visible portion.

---

## Clearing Layers

`MibDataset.clearLayer` is the correct entry point — accepts string mode shortcuts:

```matlab
obj.mibModel.I{id}.clearLayer('selection');             % full dataset (default)
obj.mibModel.I{id}.clearLayer('selection', '2D');       % current slice only
obj.mibModel.I{id}.clearLayer('selection', '3D');       % current z-stack, current t
obj.mibModel.I{id}.clearLayer('selection', '4D');       % all z and t
obj.mibModel.I{id}.clearLayer('mask');
obj.mibModel.I{id}.clearLayer('everything');            % sel+mask+labels (MibLabels63 only)
obj.mibModel.I{id}.clearLayer('selection', '2D', [], [], [], true);  % block mode
```

String modes `'2D'/'3D'/'4D'` are resolved by `MibDataset.clearLayer` using `obj.slices` and `obj.orientation`. Do **not** call `MibImage.clearLayer` directly with string modes — it only accepts numeric coordinate ranges.

Batch-aware wrapper: `obj.mibModel.clearSelection('2D, Slice' | '3D, Stack' | '4D, Dataset')`

Panel-level (`MibSelection`) uses `obj.mibController.currentModifier` to map:
Alt+Shift → `'4D, Dataset'`; Shift or Alt alone → `'3D, Stack'`; none → `'2D, Slice'`

Always check `obj.mibModel.I{id}.enableSelection == 0` and return early if disabled.

---

## Data Structures

| MIB2 (`mibImage`) | MIB3 (`MibDataset`) |
|-------------------|---------------------|
| `obj.model{1}` | `obj.labels.data{1}` (`core.MibLabels63` or `core.MibLabels`) |
| `obj.selection{1}` | `obj.selection.data{1}` (`core.MibLabels`) |
| `obj.maskImg{1}` | `obj.mask.data{1}` (`core.MibLabels`) |
| `obj.modelType` | `isa(obj.labels,'core.MibLabels63')` → 63; else `obj.labels.maxMaterials` |
| `obj.modelExist` | `obj.modelExist` (same) |
| `obj.maskExist` | `obj.maskExist` (same) |
| `obj.modelMaterialNames` | `obj.labels.materialNames` |
| `obj.modelMaterialColors` | `obj.labels.materialColors` |
| *(none)* | `obj.labels.materialsCount` — avoids full-dataset scan in `addMaterial` |
| `obj.modelVariable` | `obj.labels.labelsVariable` |
| `obj.modelFilename` | `obj.labels.filename` |
| `obj.hLabels.clearContents()` | `obj.annotations.clearContents()` |
| `size(obj.img{1},1/2/4/5)` → h/w/d/t | `obj.image.height/width/depth/time` |
| `[h,w,d,t]` dims | `[obj.image.height, obj.image.width, obj.image.depth, 1, obj.image.time]` (5D) |

### `getDatasetDimensions`: the signature AND the output order changed

```matlab
% MIB2
[height, width, COLOR, DEPTH, time] = mibImage.getDatasetDimensions(type, orient, color, options)
% MIB3
[height, width, DEPTH, COLORS, time] = dataset.getDatasetDimensions(type, orient, options)
```

**Outputs 3 and 4 are swapped, and the `color` INPUT is gone.** Porting a call verbatim both
passes one argument too many (*"Too many input arguments"*, loud) and reads the depth out of the
colours slot (silent — `colors` is 1 for `selection`/`mask` and for any grayscale image, so it
looks like a plausible depth). This shipped in `segmentationSpot`, where it made every 3D spot one
slice thick.

`core.MibImage` has its own overload with yet another signature:

```matlab
dataset.getDatasetDimensions(type, orient, options)   % core.MibDataset
image.getDatasetDimensions(orient, splitDims, blockModeSwitch)  % core.MibImage
```

**Call it on the dataset unless you specifically want raw image dims.** The two traps, each of
which has already shipped:

- **Block mode belongs to the DATASET.** The shown block is `dataset.slices`, which
  `core.MibImage` does not have — `image.getDatasetDimensions([], [], true)` can only raise
  *"Unrecognized method, property, or field 'slices'"*. It now refuses with an actionable error
  instead. Use `dataset.getDatasetDimensions('image', [], struct('blockModeSwitch', true))`.
- **`orient = []` means different things.** On the dataset it resolves to
  `dataset.orientation` (the displayed plane); on the image it forces `3` (YX) regardless.
  Anything that afterwards applies an orientation-dependent correction wants the dataset's answer.

`orient = NaN` is a MIB2 leftover; both classes now accept it as "default", but write `[]`.

---

## Model Type 63 Bit Packing (MibLabels63)

Bits within each `uint8` element of `obj.labels.data{1}`:
- Bits 1–6 (`0x3F = 63`) → model material index
- Bit 7 (`0x40 = 64`) → mask layer
- Bit 8 (`0x80 = 128`) → selection layer

```matlab
modelData = bitand(data, uint8(63));          % bits 1-6
maskData  = bitand(data, uint8(64))  / 64;   % bit 7
selData   = bitand(data, uint8(128)) / 128;  % bit 8

data(selData==1) = bitset(data(selData==1), 8, 1);  % write selection
data = bitand(data, uint8(192));   % 192 = 0xC0 — clear model bits, keep mask+sel
```

---

## Creating New Label Metadata

```matlab
meta = core.MibImage.initializeImgInfo( ...
    'pixSize', obj.image.pixSize, 'Height', obj.image.height, ...
    'Width', obj.image.width, 'Depth', obj.image.depth, ...
    'Time', obj.image.time, 'Colors', 1);
dims = [obj.image.height, obj.image.width, obj.image.depth, 1, obj.image.time];
```

---

## Path / Misc

| MIB2 | MIB3 |
|------|------|
| `global mibPath` | `obj.mibPath` (property of `MibModel`) or pass `options.mibPath` to dialogs |
| `errordlg(sprintf('...'))` | `ErrorDlgOpt.*` + `notify(obj,'ShowErrorDialog', core.ToggleEventData(ErrorDlgOpt))` |
| `BatchOpt.mibBatchSectionName = 'Menu -> ...'` | `'Ribbon -> ...'` |
| `obj.mibModel.I{id}.enableSelection == 0` | same — always check before selection operations |
