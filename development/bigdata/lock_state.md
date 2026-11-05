# Plan: locked state for BigData image and labels

## Status (2026-11-05)

Implemented, not committed. Tests pass (`tests/core/MibBigDataLockedStateTest.m`,
`tests/models/SetLockedStateStandardTest.m`, full Unit suite). Still open: replace `viewSettings` with the
`labelsLock` State Button in `Segmentation.mlapp` (a fallback in `addSegmentationPanel.m` creates it until
then), and the manual GUI checks of §9. How it works now is in
[`bigdata_logic.md`](bigdata_logic.md) §8 "Locked image and labels".

Changes made after the plan was approved:
- **Buffer buttons:** the padlock icon was not visible next to the number, so a locked buffer shows the
  padlock *instead of* the number. The buffer index is read from the button `Tag` (`buffer1`..`buffer10`),
  not from its `Text`. The icon is `assets/icons/lock_closed_16px.png`.
- **Standard datasets now have a labels lock:** it is the disabled selection (`enableSelection = false`).
  `getLockedState('labels')` is `'locked'` while the selection is disabled, and `'none'` for the empty
  placeholder buffer. Locking from the buffer menu asks for confirmation, then deletes the labels, mask
  and selection and clears the undo history. Unlocking allocates the labels layer. The "Selection disabled"
  notice is shown from the mouse press, a/s/r, f/z/x, `moveLayers` and the material guards. This replaces
  the "Standard / Virtual: not enforced" row of §1.
- **The Segmentation-panel lock button shows for BigData only.** The Standard lock is reached from the
  buffer menu **Lock labels** only.

## Context

A BigData model is written to disk live (`MibBigDataLabels.setData63` -> `writePackedLevel`), so
a stray brush stroke, `a/s/r` or Ctrl+Z on a finished model changes the store right away, with no
Save step to back out of. The goal is a locked state: a locked layer cannot be changed by mistake,
the state is shown in the GUI and changed from there, and a refused change is explained in a dialog.

Decisions made with the user:
- The lock protects **material bits + the material list**. Selection and mask stay editable.
- **Session only.** *Load model* asks, with Locked as the default; *New model* starts unlocked.
- **The image lock and the labels lock are independent.**
- **Colour wheel button:** click opens a 3-option dialog, Ctrl+click is unchanged (shuffle), right-click is unchanged (palettes).
- **A refused change shows a dialog with "Do not show again".** That choice is kept in `mibModel.sessionSettings`.

## 1. Feasibility

| Lock | Verdict | Why |
|------|---------|-----|
| Labels (BigData) | **Feasible, cheap** | Every pixel write ends in `MibBigDataLabels.writePackedLevel` (`+core/@MibBigDataLabels/MibBigDataLabels.m:562`), reached through `setData63`, `moveSelection`, `eraseEverywhere` and `clearSelectionTiles`. `MibBigDataLabelsZarr2` and `MibBigDataLabelsIndex` already block writes, so the pattern exists. `setData63` already reads `before`, so "block material bits, allow selection/mask" is one bit test. |
| Image (BigData) | **Feasible, limited protection** | Image pixels are never written. The only writes into the source store are the voxel-size and bounding-box patches (`+controllers/@MibRibbon/updateVoxelSizes.m:142`, `+controllers/@BoundingBox/BoundingBox.m:590`), and both already ask. The lock makes the state visible and puts those writes behind the lock dialog. |
| Standard / Virtual | **Not enforced** | Standard edits stay in memory (undo; you can just not save); enforcing a lock there would need guards in the `setData*` fast paths and about 11 direct `labels.data` writes. Virtual is browse-only. |

Not covered by the lock, on purpose:
- Level-map materialisation on read. It is a cache and does not change the content.
- Side-file writes on close.
- Material colours.

## 2. Terms and where the state lives

**Terms: `'image'` and `'labels'`, not "dataset" and "model".** These are the layer names `getData`/`setData`
already use. "Model" is avoided on purpose, because in the wider sense it covers labels + mask + selection,
and two of those three stay editable under this lock. "Dataset" covers every layer, but the image lock protects
only the image. User-facing text follows the same terms: **Lock image**, **Lock labels**.

- **`lockedState (1,1) logical = false`**, a `Transient` property on **`core.MibImage`**, the base class of every
  layer object (`MibImage`, `MibLabels`, `MibLabels63`, `MibBigDataImage`, `MibBigDataLabels`, the two read-only
  overlays). One definition gives uniform access as `ds.image.lockedState` and `ds.labels.lockedState`.
  - It lives on the layer object because the store object does the internal writes itself (`moveSelection` ->
    `writePackedLevel`) and has no back-reference to `MibDataset`.
  - The docblock states that it is honoured only for BigData today.
  - The read-only overlays set it to `true` in their constructors, and the setter refuses to clear it for them.
- **`MibDataset.getLockedState(layer)`**, `layer` = `'image'` | `'labels'`. Returns `'none'` (not BigData, or no
  model), `'unlocked'`, `'locked'` or `'readOnly'` (overlay classes). It has two GUI callers: the buffer menu and
  the segmentation panel.
- **`MibModel.setLockedState(id, layer, state)`** sets the flag and fires `UpdateGuiWidgets`. Batch-compatible
  through `buffers_ContextMenu`.

Classdef property additions cannot be hot-reloaded while MIB holds instances. Implement with MIB closed, and
restart MATLAB before testing.

## 3. The lock dialog (refused change)

**`MibModel.showLockedNotice(id, layer)`** is the single place the dialog is built:
- It uses `utils.dlgs.inputQuestDlg` with `DoNotShowAgain = true`, `Icon = 'puffin_warning'` and a `HelpUrl` to
  the dataset-types page.
- Text: *"The labels of this dataset are locked; the change was not made."* (or *"The image ..."*).
- Buttons: **Unlock** / **Keep locked** (default). *Unlock* calls `setLockedState(id, layer, false)`; the user
  then repeats the action. For the image lock the voxel-size and bounding-box paths can carry on to their existing
  "Update zarr3 file?" question in the same call.
- The *Do not show again* choice goes into `obj.sessionSettings.LockedState.hideNotice.(layer)`, so it is per layer
  and lost on exit. After that, a refused change is refused silently, and the lock button and padlock icon stay
  the visible signal.
- In batch mode there is no dialog: the error goes through `ShowErrorDialog` and then `notify(obj, 'StopProtocol')`.

**How refusals reach the dialog:**
1. **Early guards in `MibModel`** (below) call `showLockedNotice` directly, before any long work or undo copy.
2. **The last-line guard in `setData63`** has no access to `MibModel`, and 48 call sites in models and controllers
   call `I{id}.setData2D/3D/4D` directly, so a check in the `MibModel` wrappers alone would leak. The flow is:
   - `setData63` refuses, sets `labels.lastWriteRefused = true` (Transient) and returns false.
   - `MibDataset.setData2D/3D/4D` (the BigData slow path, after the `labels.setData` call) sees the flag, clears it
     and fires a new `MibDataset` event, `LockedWriteRefused`, with the layer in the event data.
   - `MibController.listener_newDataset` attaches a listener to that event for `I{id}`, unless
     `event.hasListener` says one exists. The listener calls `mibModel.showLockedNotice`.
   - A stroke fires `setData63` on every mouse-move, so the dialog shows at most once per tool action: it is
     throttled by a Transient `noticeShownForAction` flag that `gui_WindowButtonUpFcn` resets.
   - This keeps dialogs out of the core classes.

## 4. Labels lock - enforcement

**Last line - `+core/@MibBigDataLabels/setData63.m`:**
- `'labels'` -> refused.
- `'everything'` -> refused only when the material bits (`bitand(x, obj.materialMask)`) differ between `before` and
  the incoming block, so selection/mask-only undo entries pass.
- `'selection'` / `'mask'` -> allowed.

**Early guards** (`if labelsLocked, showLockedNotice, return`). Each one refuses before any work starts:
- `+models/@MibModel/moveLayers.m` - destination `labels`: `a/s/r`, Shift+R, both branches of Shift+R.
- `+models/@MibModel/undo.m` - a `'labels'` entry, or an `'everything'` entry. The history is kept.
- Material list: `addMaterial`, `removeMaterial`, `insertMaterial`, `reorderMaterials`, `swapMaterials` and the
  rename in the materials table (`+controllers/@MibSegmentation`). Colours stay editable.
- `+models/@MibModel/editInstanceObjects.m` - every action except pick/highlight. Compact included.
- `+models/@MibModel/createModel.m`, DeepMIB `writeModelStore` - refuse a new store at the locked store's path
  (creating it would delete the store). Any other path is fine.

**Allowed while locked:** close model, convert 63 -> 16383 (it writes a new store, which starts unlocked),
export, and *Save model* (side-file only).

## 5. Image lock - enforcement

- In `updateVoxelSizes.m` and `BoundingBox.m`, when `ds.image.lockedState`, the session values still apply, but
  the file write goes through `showLockedNotice(id, 'image')`. *Unlock* continues to the existing
  "Update zarr3 file?" question.
- Default on open: **locked, with no dialog.** Nothing about browsing or segmenting changes, so there is nothing to
  confirm. Set where `MibDataset.initialize` builds a `'BigData'` image.
- While implementing, check whether an image export can target the source path; if so, refuse it while locked.

## 6. Load / new model

- `+models/@MibModel/loadModel.m`, BigData branch: after `openStore` succeeds and only for the editable class, ask
  `inputQuestDlg` *"Open the labels locked? They are protected from changes until you unlock them."* with
  **Locked** (default) / **Unlocked** and a Help button.
- New BatchOpt checkbox `LockLabels`. A batch call without the field opens the labels **unlocked**, so existing
  protocols that load and then edit keep working.
- New model, alignment/crop outputs and DeepMIB-created stores start unlocked (the property default).

## 7. GUI

### Buffer buttons (Datasets panel)
- **Use an icon, not a background colour.** `paintBufferButton` already uses the background for four states, and
  `'selected'` overrides the others, so a lock colour would disappear on the buffer you are looking at.
  - Instead, set `Icon` to a padlock (`assets/icons/lock_12px.png`, new, mid-grey so it reads in both themes) in
    `update_fromModel.m`, next to the `paintBufferButton` calls.
  - The icon shows when either layer is locked. The tooltip's first line says which:
    `LOCKED: image` / `LOCKED: labels` / `LOCKED: image, labels`.
  - Fallback if the buttons are too narrow: `FontWeight = 'bold'` plus the tooltip. The font colour stays on auto.

### Buffer context menu
- Add two checkable items, created with `uimenu` in the `MibActiveDataset` constructor so `ActiveDataset.mlapp`
  is not edited, after a separator: **Lock image** and **Lock labels**.
- A new `ContextMenuOpeningFcn` sets `Checked`/`Enable` from `getLockedState` of the clicked buffer, following the
  pattern of `MibSelection.showModel_ContextMenuOpening`. `'none'` -> disabled; `'readOnly'` -> checked + disabled.
- Both go through `buffers_ContextMenu` as `'lockImage'` / `'lockLabels'` -> `setLockedState`.

### Segmentation panel
- **Colour wheel** (`+controllers/@MibSegmentation/gui_Callbacks.m`, `'colorWheel'` case):
  - Plain click opens one `inputUniversalDlg` with three options:
    1. Show labels as contours (checkbox)
    2. Show mask as contours (checkbox)
    3. Random colours, seed (edit; empty = keep the current colours). A value is passed to
       `setDefaultColorPalette('Random Colors', [], seed)`, which skips its own seed dialog.
  - Ctrl+click stays `'shuffle'`. Right-click stays `colorWheel_ContextMenu`.
  - Delete the `'viewSettings'` case and its wiring (`MibSegmentation.m:210`). Update the tooltip.
- **Labels lock button** in the freed slot: a state button `labelsLock`. You replace the `viewSettings` widget in
  `Segmentation.mlapp` in App Designer; spec: State Button, same grid cell, no text, 16 px icon. I wire it in
  `MibSegmentation`.
  - Locked: closed-padlock icon, background from a new `utils.themeColors` field `lockedBackground` (amber,
    theme-aware).
  - Unlocked: open-padlock icon, background on auto.
  - `'none'`: `Enable off`. `'readOnly'`: locked + `Enable off`, with a tooltip saying the store is read-only.
  - Refreshed next to the existing `modelExist` handling in the panel update.
  - Tooltip: *"Labels lock: when locked, materials cannot change; selection and mask stay editable."*

## 8. Documentation

- `docs/docs/user-interface/panels/datasets/index.md` - two rows in the context-menu table and one line on the padlock icon.
- `docs/docs/user-interface/panels/segm/index.md` - the colour wheel's click / Ctrl+click / right-click, and the lock button.
- `docs/docs/getting-started/dataset-types/index.md` - a short BigData paragraph: loaded labels open locked; how to unlock.
- `development/bigdata/bigdata_logic.md` - a new section on lock semantics (what is refused where, the
  `LockedWriteRefused` path, what is not covered and why), and an entry in the §12 invariants: *a new labels write
  path must respect `labels.lockedState`*.
- Docblocks for every new or changed method.
- No em/en dashes (run the CLAUDE.md grep before finishing).

## 9. Verification

- New `tests/core/MibBigDataLockedStateTest.m` on a temporary store:
  - a locked `'labels'` write returns false, the bytes are unchanged and `lastWriteRefused` is set
  - a `'selection'` write passes
  - an `'everything'` write that changes only selection bits passes; one that changes material bits is refused
  - `moveSelection` to labels while locked leaves the store unchanged
  - `getLockedState` returns the right value for Standard, editable BigData, a Zarr2 overlay and an Index overlay
  - `MibDataset.setData2D` fires `LockedWriteRefused` once for a refused write
- Run the single test class in a **fresh** `matlab -batch`, not the full suite in the live session.
- Manual check in restarted MIB:
  1. Load labels; the dialog defaults to Locked.
  2. Brush into the selection works; `a` shows the lock dialog once.
  3. *Do not show again* silences it for the rest of the session only.
  4. *Unlock* from the dialog, the button and the buffer menu; the icon and the check marks follow.
  5. Ctrl+Z of a labels stroke is refused and the history is kept.
  6. Voxel-size change on a locked image shows the lock dialog; *Unlock* leads to the file question.
  7. Colour wheel: click, Ctrl+click and right-click each do the right thing.
- `buildtool check`.
