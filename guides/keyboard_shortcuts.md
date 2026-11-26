# Keyboard shortcuts

How the MIB3 shortcut system works, how to add a shortcut, what has been measured, and the plan for
the remaining work. User-facing text is in `docs/docs/user-interface/ribbon/home/home-preferences.md`
(the panel) and `docs/docs/user-interface/key-and-mouse-shortcuts.md` (the default keys).

## Status

| Step | Content | State (2026-11-09) |
|------|---------|--------------------|
| 1 | Defect fixes, saved shortcuts merged by action name, zoom keys implemented, Ctrl+A / Alt+A as bindable actions | Done, tests pass |
| 2 | Preferences panel in the Fine-tuning style: read-only table, filter, Record / Clear / Reset | Done, GUI checked by the author |
| 3 | `utils.findKeyShortcut`, display labels, "Select material N" and "Select segmentation tool: X" actions | Done, tests pass, **GUI check pending** |
| 4 | Ribbon commands bindable to keys | **Not started**, see [Plan for step 4](#plan-for-step-4-ribbon-commands) |

## How it works

### Data

`utils.defaults.generateKeyShortcuts` returns three outputs, all sorted by `Action`:

| Output | Saved? | Meaning |
|--------|--------|---------|
| `KeyShortcuts` | yes, `mib3.mat` and the override JSON | Struct of parallel vectors: `Action`, `Key`, `shift`, `control`, `alt`, `overrideShift`, `overrideAlt` |
| `categories` | no | Category column of the panel |
| `labels` | no | Name shown to the user, equal to `Action` unless a row sets another one |

`Action` is an **identifier**, not display text. It is used in three ways:

- as the `case` strings of the key press handlers, and some handlers read the text itself
  (`Action{ActionId}(8)` takes the preset number, `contains(..., 'Next')` the direction);
- as the key for restoring saved shortcuts, see below;
- to find the special Alt+Shift+A case in `utils.findKeyShortcut`.

**Never rename an `Action`.** A renamed action does not match its saved entry, so a user who moved it
to another key silently returns to the default. To improve a name, set its `labels` entry. This is why
the row with the misspelled identifier `Increse active material index...` is shown as "Increase".

### Saved shortcuts

`MibModel.initializePreferences` always takes the list of actions from the running version and
restores only `Key`, `shift`, `control` and `alt` from the saved file, matched by `Action`
(local function `mergeKeyShortcuts`). A saved action that no longer exists is dropped. A new action
keeps its default key unless a saved row already uses that combination, then it gets no key. Saved
arrays of unequal length leave the defaults in place.

### Matching a key press

`utils.findKeyShortcut(KeyShortcuts, key, modifier)` is the only implementation of the rules. It is
called by `MibController.gui_WindowKeyPressFcn`, `utils.childWindowKeyPressFcn` and
`MibImageDocument.gui_WindowKeyPressFcn_BrushSuperpixel`. Each caller keeps its own `switch`, so child
windows still handle only their whitelisted actions.

The rules, for the rows bound to the pressed key:

- If any of them has `overrideShift`, Shift is ignored. These actions take Shift as an argument, for
  example Shift+A works on the whole stack.
- If any of them has `overrideAlt`, Alt is ignored.
- Alt is also ignored in Alt+Shift+A on the key of `Add to selection to material`.
- Two rows with one combination return the first. The panel prevents this, a hand-edited override
  file may not.

A consequence: a row that needs Shift on a key used by an `overrideShift` action can never fire.
`Preferences.assignKeyShortcut` refuses such combinations.

### Preferences panel

Implemented in `controllers.Preferences` after the Fine-tuning pattern: callbacks are wired from the
controller and dispatched on `event.Source.Tag` in `KeyboardShortcutsPanelCallbacks`, edits go to the
working copy `obj.preferences` and reach MIB on Apply or OK. `obj.keyShortcutRows` maps table rows to
actions. Writing `Data` clears a column sort, so the table returns to the category order after each
change.

Widgets in `views.PreferencesGUI`: `shortcutsTable`, `KeyShortcutsFilter`, `KeyShortcutsFilterLabel`,
`KeyShortcutsActionLabel`, `KeyShortcutsHint`, `KeyShortcutsRecordButton`, `KeyShortcutsClearButton`,
`KeyShortcutsResetRowButton`, `ResetKeyShortcutsButton`, `PressedKeyValue`.

## Adding a shortcut

1. In `generateKeyShortcuts.m`, raise the row count and add the row with `Key`, `Action` and modifiers.
   A new action with no default key cannot clash with a user's layout, so prefer `Key = ''`.
2. Add the row to a category in the `categories(...)` lines. Rows not listed are `General`.
3. Set `overrideShift` / `overrideAlt` only if the action reads the modifier as an argument.
4. Add a `case` with the exact `Action` text in `gui_WindowKeyPressFcn`, or a prefix test in its
   `otherwise` branch for actions generated from a list.
5. In the handler, check `enableSelection` for anything that edits a layer, and call
   `obj.gui_WindowKeyReleaseFcn([], [])` or clear `obj.currentModifier` before anything that opens a
   dialog or a progress bar. The key release otherwise goes missing, see [ctrl_stale.md](ctrl_stale.md).
6. Add default keys to `docs/docs/user-interface/key-and-mouse-shortcuts.md`.

The segmentation tool names in `generateKeyShortcuts.m` repeat the `Items` of the `segmTool` dropdown.
`tests/utils/KeyShortcutsTest.m` reads the `.mlapp` and fails if the two lists drift apart, because
the handler silently does nothing for an unknown tool.

## Measurements

R2026a, separate `matlab -batch` process, 2026-11-09. Each time is the mean of 20000 calls after 2000
warm-up calls. Extra rows are actions without a key, as future ones would be.

Lookup, including the most expensive case (Alt+Shift+A) as "hit", and a key without an action as "miss":

| Actions | Old hit | New hit | Old miss | New miss |
|---------|---------|---------|----------|----------|
| 68 (current) | 11.3 µs | 11.0 µs | 4.8 µs | 2.6 µs |
| 200 | 12.1 µs | 10.9 µs | 5.1 µs | 2.9 µs |
| 1000 | 19.9 µs | 13.6 µs | 9.4 µs | 5.9 µs |
| 5000 | 86.5 µs | 26.6 µs | 45.0 µs | 17.6 µs |

`switch` on the action name, last case matched:

| Cases | Time |
|-------|------|
| 68 | 3.5 µs |
| 200 | 7.8 µs |
| 1000 | 36.1 µs |
| 5000 | 379.4 µs |

Other costs that grow with the list:

| Actions | Shortcut texts, per filter keystroke | Search, per filter keystroke | Merge at startup, half of the rows new |
|---------|-----|-----|-----|
| 200 | 1.7 ms | 0.6 ms | 1.2 ms |
| 1000 | 5.2 ms | 2.9 ms | 5.8 ms |
| 5000 | 23.0 ms | 13.7 ms | 167 ms |

Not measured: redrawing `shortcutsTable` with a long list, which needs the real dialog.

The new matching was compared with the previous code on 48,240 key and modifier combinations, over
the default table and 200 random layouts, with no differences. In the 837 combinations with duplicate
rows, where the previous code failed in `switch`, the first row is returned.

## Decisions

- **One `strcmp` over `Key`, then the rules on the rows of that key.** The previous code repeated full
  table scans for each override rule.
- **No lookup cache (`dictionary` of keys to rows).** It would have to be invalidated on every change
  of the preferences, and the plain scan takes 14 µs at 1000 actions.
- **No function-handle dispatch for performance.** The `switch` costs 36 µs at 1000 cases, far below
  the cost of any action. Step 4 may still use a table to keep the list maintainable.
- **Labels instead of renaming with an alias table.** Labels need no migration of saved files and
  keep identifiers stable.
- **Direct tool selection has no banner.** The favourite-tool keys show the tool name over the image
  for 0.3 s, needed for the loop key where the next tool is not obvious. A key bound to one tool does
  not need it.
- **"Select material N" does nothing on models with more than 255 materials.** Their table lists only
  the two materials being edited, so row N is not material N.

## Plan for step 4: ribbon commands

Not started. Needs from the author: the list of ribbon commands to put on keys, 10-20 frequently used
tools are enough for a first pass. Binding every button is not the goal, many only make sense with a
dialog or a specific dataset type.

1. **Registry.** One table of action name, ribbon tab and widget name, for example in
   `generateKeyShortcuts.m` or a helper next to it. Rows have `Key = ''` and a category per ribbon tab.
   Action names are permanent from the first release, see [Data](#data).
2. **Dispatch.** Widgets and callbacks already exist as
   `obj.cRibbon.handles.ribbonHome.saveFileAs.ButtonPushedFcn = @obj.home_Callbacks`, with one handles
   struct per tab. A key press finds the widget in the registry and calls its `ButtonPushedFcn`. Check
   per callback what it reads from its source and event arguments before relying on this.
3. **Respect the ribbon state.** `MibController.updateGuiWidgets` sets `.Enabled` per widget and
   dataset type, a callback called directly bypasses it. Return when `widget.Enabled` is false, so a
   key cannot start a tool that is disabled for the current dataset, for example BigData.
4. **Modifiers.** Most ribbon commands open a dialog or a progress bar: release the modifiers first,
   as the `Invert image` and `Save image as...` cases do.
5. **Tests.** Every registry entry names an existing widget, and action names are unique. The first
   can read the handles from a `RequiresGUI` test or parse the `addRibbon*.m` files.
6. **Measure the panel.** With a few hundred rows, check the `shortcutsTable` redraw per filter
   keystroke in the real dialog. If slow, update `ValueChangedFcn` only and drop `ValueChangingFcn`.

## Open items

- GUI check of step 3: a key bound to "Select material N", a key bound to "Select segmentation tool",
  superpixel Undo.
- `docs/docs/user-interface/ribbon/home/images/file-preferences-shortcuts.png` shows the old panel.
- Further labels can be improved on one line each, for example `Add to selection to material`.
