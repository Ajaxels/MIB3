# Plan: MibModel.setDefaultColorPalette + utils.defaults.generateDefaultPalette

## Context

Port two MIB2 color-palette functions to MIB3:
1. `MIB2/Classes/@mibModel/setDefaultSegmentationColorPalette.m` → `MibModel.setDefaultColorPalette` method
2. `MIB2/Tools/mibGenerateDefaultSegmentationPalette.m` → `utils.defaults.generateDefaultPalette`

`utils.defaults.generateDefaultSegmentationPalette.m` **already exists** in MIB3 and is already fully ported (uses `inputSingleDlg`). So `generateDefaultPalette.m` will be a thin wrapper around it, giving a shorter canonical name. The old file stays to avoid breaking the Preferences controller that calls it.

`setDefaultColorPalette.m` does not exist in MIB3 yet and must be created.

---

## Files to Create / Modify

| Action | File |
|--------|------|
| **Create** | `mib/+utils/+defaults/generateDefaultPalette.m` |
| **Create** | `mib/+models/@MibModel/setDefaultColorPalette.m` |
| **Edit** | `mib/+models/@MibModel/MibModel.m` — add method declaration |

---

## Step 1: Create `generateDefaultPalette.m`

**Path:** `mib/+utils/+defaults/generateDefaultPalette.m`

Thin wrapper that delegates to the already-ported `generateDefaultSegmentationPalette`:

```matlab
function palette = generateDefaultPalette(paletteName, colorsNo)
% function palette = generateDefaultPalette(paletteName, colorsNo)
% generate color palette; thin wrapper around generateDefaultSegmentationPalette
%
% Parameters:
% paletteName: string with the name of the palette, see generateDefaultSegmentationPalette for options
% colorsNo: [@em optional] numeric, number of required colors; default 6
%
% Return values:
% palette: matrix [colorId][R G B] in range 0-1

%|
% @b Examples:
% @code palette = utils.defaults.generateDefaultPalette('Default, 6 colors', 3); @endcode

if nargin < 2; colorsNo = 6; end
if nargin < 1; paletteName = 'Default, 6 colors'; end

palette = utils.defaults.generateDefaultSegmentationPalette(paletteName, colorsNo);
end
```

---

## Step 2: Create `setDefaultColorPalette.m`

**Path:** `mib/+models/@MibModel/setDefaultColorPalette.m`

Full conversion table applied from MIB2 source:

| MIB2 | MIB3 |
|------|------|
| `global mibPath;` | remove — not needed |
| `obj.I{obj.Id}` | `obj.I{id}` where `id = obj.getActiveId()` |
| `obj.I{obj.Id}.modelType` | `obj.I{id}.labels.maxMaterials` |
| `obj.I{obj.Id}.modelMaterialNames` | `obj.I{id}.labels.materialNames` |
| `obj.I{obj.Id}.modelMaterialColors` | `obj.I{id}.labels.materialColors` |
| `mibInputDlg({mibPath}, msg, title, def)` | `utils.dlgs.inputSingleDlg(obj.mibGUI, msg, struct(...spinner...), title, dlgOpt)` |
| `str2double(answer{1})` | `answer` directly (inputSingleDlg spinner returns double) |
| `mibGenerateDefaultSegmentationPalette(...)` | `utils.defaults.generateDefaultPalette(...)` |
| `errordlg(msg, title)` | `utils.dlgs.showErrorDialog(obj.mibGUI, msg, title)` |
| `ToggleEventData(x)` | `core.ToggleEventData(x)` |
| `notify(obj, 'modelNotify', eventdata)` | `notify(obj, 'UpdateGuiWidgets', eventdata)` |
| `notify(obj, 'plotImage')` | `notify(obj, 'ShowImage')` |

Key details for the method body:
- Get `id = obj.getActiveId();` at top
- Matlab colormap prompt: use `inputSingleDlg` with `Type='spinner'`, struct `Value=colorsNo, Limits=[1 obj.I{id}.labels.maxMaterials], Step=1, Round=true`
- Event data for `UpdateGuiWidgets`: `core.ToggleEventData({'ribbonModel', 'checkboxes'})` (matches `materialsActions.m` pattern)
- `current2default`: `obj.preferences.Colors.ModelMaterialColors = obj.I{id}.labels.materialColors; return;`
- `default2current`: `palette = obj.preferences.Colors.ModelMaterialColors;`
- Bottom: assign `obj.I{id}.labels.materialColors = palette;`

---

## Step 3: Add Method Declaration to MibModel.m

**Path:** `mib/+models/@MibModel/MibModel.m`

Insert in the `methods` block (alphabetically near `setData*`, before `setMagFactor`):

```matlab
setDefaultColorPalette(obj, paletteName, colorsNo)        % set default color palette for materials of the model
```

---

## Verification

1. Run MIB3: `cd C:\Matlab\MIB3\mib; mib3`
2. Load or create a dataset with a segmentation model
3. From the Segmentation panel context menu (or programmatically): call `obj.mibModel.setDefaultColorPalette('Default, 6 colors')`
4. Verify material colors update in the segmentation table and image view
5. Test `current2default` and `default2current` cases
6. Test a Matlab colormap (e.g., `'Matlab Jet'`) — verify the spinner dialog appears for color count
7. Test `'Random Colors'` — verify seed dialog appears (handled inside `generateDefaultPalette`)
8. Run `buildtool check` to confirm no MATLAB Code Analyzer warnings
