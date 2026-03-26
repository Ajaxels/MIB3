# moveLayers Port: MIB2 → MIB3

**Status: DONE** (2026-03-22)

---

## Files Created

| MIB3 File | MIB2 Source |
|-----------|-------------|
| `+models/@MibModel/moveLayers.m` | `@mibModel/moveLayers.m` |
| `+core/@MibDataset/moveMaskToSelectionDataset.m` | `@mibImage/moveMaskToSelectionDataset.m` |
| `+core/@MibDataset/moveMaskToModelDataset.m` | `@mibImage/moveMaskToModelDataset.m` |
| `+core/@MibDataset/moveModelToSelectionDataset.m` | `@mibImage/moveModelToSelectionDataset.m` |
| `+core/@MibDataset/moveModelToMaskDataset.m` | `@mibImage/moveModelToMaskDataset.m` |
| `+core/@MibDataset/moveSelectionToMaskDataset.m` | `@mibImage/moveSelectionToMaskDataset.m` |
| `+core/@MibDataset/moveSelectionToModelDataset.m` | `@mibImage/moveSelectionToModelDataset.m` |

## Key Property Mapping

| MIB2 | MIB3 |
|------|------|
| `obj.model{level}` | `obj.labels.data{level}` |
| `obj.selection{level}` | `obj.selection.data{level}` |
| `obj.maskImg{level}` | `obj.mask.data{level}` |
| `obj.modelType == 63` | `isa(obj.labels, 'core.MibLabels63')` |
| `obj.getData('labels', 4, idx)` | `uint8(obj.labels.data{1} == idx)` |
| `obj.setData4D(type, data, orient, col, opt)` | `obj.I{id}.setData4D(data, type, orient, col, opt)` — **data before type** |
| `doNotTranspose = 4` (no block mode) | `orient = 3` (YX, non-transposed) |
| `doNotTranspose = 0` (block mode) | `orient = []` (current orientation) |

## Architecture

- **Fast path**: Full-dataset operations (no ROI/block mode) dispatch directly to the 6 `MibDataset` helper methods which manipulate packed data arrays
- **Slow path**: 2D/3D operations with ROI/block mode use `getData2D`/`getData4D` + modify + `setData2D`/`setData4D`
- `mibDoBackup` calls are commented out (not yet implemented in MIB3, consistent with `MibModel.clearLayer`)

## Performance Notes

- Use local variable for data arrays: read once into `D`, perform all bit operations, write back once
- Strip `x/y/z/t` options once in `moveLayers` before calling helpers
- `bitand(D, 63)` + `bitor(D, M)` clears selection and mask in one pass
