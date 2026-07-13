# ResampleDataset Port Log

Port of `mibResampleController` + `mibResampleGUI` (MIB2) → `controllers.ResampleDataset` (MIB3).

---

## Files

| File | Status |
|------|--------|
| `mib/+controllers/@ResampleDataset/ResampleDataset.m` | **DONE** — single-file controller |
| `mib/+views/ResampleDatasetGUI.mlapp` | **DONE** — startupFcn reverted to original (no patch needed; `core.ChildView` handles wiring) |
| `mib/+utils/resizeImage3d.m` | **DONE** — updated to accept `[h,w,d,c]` natively |
| `mib/+controllers/@MibRibbon/datasetTools_Callback.m` | **DONE** — `'Resize'` case added |

---

## Completed Work

### Task 1 — resizeImage3d: accept [h,w,d,c] layout (MIB3 native)

Changed from conditional (3D-only) permute to unconditional permute at entry/exit:

- **Line 54** (was `if strcmp(options.imgType,'3D'); img = permute(...); end`):
  ```matlab
  img = permute(img, [1 2 4 3]);  % 3D:[h,w,d]→[h,w,1,d]; 4D new:[h,w,d,c]→[h,w,c,d]
  ```
- **Lines 207–209** (was `if strcmp... imgOut = permute(...); end`):
  ```matlab
  imgOut = permute(imgOut, [1 2 4 3]);  % internal [h,w,c,d] → new layout [h,w,d,c]
  ```
- Doc comment: `4D (y,x,c,z)` → `4D (y,x,z,c)`

Backward-compatible: 3D callers (e.g. `saveBigDataViewerFormat.m`) unaffected — `permute([h,w,d],[1 2 4 3])` produces `[h,w,1,d]`, same as before.

### Task 3 — ResampleDatasetGUI.mlapp

No patch needed. The original `startupFcn(app)` works fine — `core.ChildView` sets `obj.view` and does not call `startupFcn` with a controller argument. **Revert was applied** to restore the original mlapp after an earlier (incorrect) patch.

### Task 4–7 — ResampleDataset.m (complete)

Single-file controller at `mib/+controllers/@ResampleDataset/ResampleDataset.m`.

**Architecture:**
- Follows `CropDataset` pattern (no `mibController` reference needed)
- Properties: `mibModel`, `view`, `listener`, `height`, `width`, `color`, `depth`, `BatchOpt`
- Event: `CloseEvent`

**Key methods:**
| Method | Notes |
|--------|-------|
| `ResampleDataset(mibModel, varargin)` | Constructor; GUI path or batch path |
| `ViewListner_Callback2` (Static) | Validity guard; calls `updateWidgets()` |
| `closeWindow` | Deletes GUI + listeners, fires `CloseEvent` |
| `addCallbacks` | Wires all AppDesigner callbacks incl. `SelectionChangedFcn` on ButtonGroup |
| `updateWidgets` | Sets Labels `.Text`, NumericEditField `.Value`, populates DropDown `.Items` then `.Value`, calls `updateEditboxStates` |
| `updateEditboxStates(mode)` | Enables DimensionX/Y/Z for `'Dimensions'`, VoxelX/Y/Z for `'Voxels'`, Percentage for percentage modes |
| `radio_Callback(hObject)` | Updates BatchOpt, calls `updateEditboxStates`, triggers editbox recalc for percentage modes |
| `editbox_Callback(hObject)` | Cross-field updates; uses `.Value` (numeric); syncs BatchOpt string fields with `num2str` |
| `resampleBtn_Callback(batchModeSwitch)` | Main processing; see below |
| `helpBtn_Callback` | Opens help URL |
| `returnBatchOpt` | Fires `SyncBatch` event |
| `updateBatchOptFromGUI` | Delegates to `utils.updateBatchOptFromGUI_Shared` |

**resampleBtn_Callback key decisions:**
- Backup via `obj.mibModel.backup('image', 1)` (GUI path only)
- Resolve dimensions from mode before resize
- `getData3D('image', t, 3, NaN, opts)` → `[h,w,d,c]`; `NaN` = all channels (MIB3 convention)
- Resize via `utils.resizeImage3d(img, [], resizeOpts)` — no permute needed (resizeImage3d updated)
- **Write image back by directly replacing `image.data{1}`** — `setData4D` is not used here because it writes into a fixed-size container and errors when dimensions change
- After replacing `data{1}`, update `height/width/depth/dim_yxzct` on the `MibImage` handle
- Call `obj.mibModel.I{id}.updateBoundingBox(oldBB)` to preserve physical extent and recompute voxel sizes — this propagates new `pixSize` to all layers via `setPixSize`
- Sync `MibDataset.dim_yxzct`, `current_yxz`, and `slices` (same pattern as `cropDataset.m`)
- Labels: `getData4D(modelDataType, 3, NaN, labelsOpts)` returns `[h,w,d,t]` (no colour dim); index as `model4D(:,:,:,t)`
- Labels write via `setData4D(imgOutModel, modelDataType, 3, NaN, labelsOpts)` — labels container matches new size because it's cleared/re-created
- Annotations: shift positions by `newZ/depth`, `newW/width`, `newH/height` ratios
- ROIs: `hROI.resample(resampledRatio)` with `[newW/width, newH/height, newZ/depth]`
- Fires `NewDataset` + `ShowImage`

### Task 8 — Ribbon wiring

`datasetTools_Callback.m`: added `case 'Resize'` → `startController('controllers.ResampleDataset')`.

---

## Bugs Fixed During Implementation

| # | Error | Root Cause | Fix |
|---|-------|-----------|-----|
| 1 | `'Value' must be an element defined in the 'Items' property` (updateWidgets line 243) | AppDesigner DropDown requires `Items` to be populated before setting `Value` | Set `.Items` before `.Value` for all three dropdowns in `updateWidgets` |
| 2 | `Index in position 4 is invalid` in `core.MibImage/getData` | `getData3D(..., 0, ...)` — MIB2 used `0` for "all channels", MIB3 requires `NaN` | Changed `0` → `NaN` in `getData3D` and `setData4D` calls |
| 3 | `left side is 887×813×171, right side is 443×406×171` (setData4D) | `setData4D` writes into existing fixed-size container; cannot resize | Replaced with direct `image.data{1} = imgOut` + dimension/boundingBox update pattern from `cropDataset.m` |

---

## MIB3 Conversion Notes Confirmed During This Port

| Topic | MIB2 | MIB3 |
|-------|------|------|
| All colour channels | `0` | `NaN` |
| Data layout | `getData3D` → `[h,w,c,d]` | `getData3D` → `[h,w,d,c]` |
| Labels getData4D shape | `[h,w,c,d,t]` | `[h,w,d,t]` (no colour dim for labels) |
| Resize write-back | `setData4D` (same-size write) | Direct `data{1} = newArray` + dim update |
| BoundingBox/pixSize update | direct field assignment | `MibDataset.updateBoundingBox(oldBB)` → reads new h/w/d from MibImage → recalculates pixSize → calls `setPixSize` to propagate |
| `MibDataset.dim_yxzct` | — | Must be synced manually after image resize: `ds.dim_yxzct = img5D.dim_yxzct` |
| `slices` reset | — | Reset all four slices to new extents after resize |
| DropDown init | set `.String` | Set `.Items` first, then `.Value` |
| Button group value read | `get(h, 'Value')` | `h.ResamplingMode.SelectedObject.Tag` (or via `event.NewValue` in `SelectionChangedFcn`) |

---

## Remaining / To Verify

- [ ] End-to-end test: resize image-only dataset (Dimensions / Voxels / PercentageXYZ / PercentageXY modes)
- [ ] End-to-end test: resize dataset with MibLabels63 model + mask
- [ ] End-to-end test: resize dataset with annotations and ROIs
- [ ] Virtual dataset → Standard conversion path
- [ ] Batch mode (pass BatchOpt struct as 2nd arg to constructor)
- [ ] `setData4D` for labels (`imgOutModel`) — confirm it works when labels container already matches new size (labels container must be reset to new size before `setData4D`, or confirm getData4D+setData4D is same-size for labels)
- [ ] `clearLayer('mask')` / `clearLayer('selection')` after non-`everything` resample — confirm both handle no-data gracefully

---

## Known Edge Cases

| Situation | Expected |
|-----------|----------|
| `MibDataset.clearLayer` when no mask/selection exist | Should be no-op; verify `clearLayer` handles `NaN` data gracefully |
| `interpn` non-nearest labels resize (per-material loop) | Each material resampled separately; result may leave gaps at material boundaries |
| `newZ == obj.depth` in PercentageXY mode | DimensionZ stays unchanged; `resampledRatio(3) == 1` |
| `hROI.resample` with no ROIs | Should be no-op |
