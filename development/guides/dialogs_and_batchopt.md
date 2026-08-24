# Dialogs, Progress Bars and BatchOpt

Everything needed to put a dialog, a progress bar or a batch-capable parameter into MIB3. Read this
before adding either. The root [`CLAUDE.md`](../../CLAUDE.md) keeps only the three rules that cause
silent bugs; the detail is here.

Related: [how_to_make_input_dialog.md](how_to_make_input_dialog.md) (building a dialog from scratch,
focus handling), [uiprogressdlg_to_PoolWaitbar.md](uiprogressdlg_to_PoolWaitbar.md) (converting to
`core.PoolWaitbar`), [conversion_reference.md](conversion_reference.md) (the PoolWaitbar API table).

---

## Dialogs: MIB2 → MIB3

| MIB2 | MIB3 |
|------|------|
| `warndlg(msg, title)` | `dlgOpt.MsgBoxOnly=true; dlgOpt.Icon='puffin_warning'; dlgOpt.HeaderLines=N;` + `utils.dlgs.inputUniversalDlg(obj.mibGUI, msg, {}, {}, title, dlgOpt)` |
| `warndlg` with body text | same, but pass the body in prompts/defAns: `utils.dlgs.inputUniversalDlg(obj.mibGUI, '!!! Warning !!!', {''}, {'body text'}, title, dlgOpt)` |
| `errordlg(msg, title)` | `utils.dlgs.showErrorDialog(obj.mibGUI, msg, title)` |
| `questdlg(msg,title,b1,b2,def)` | `utils.dlgs.inputQuestDlg(obj.mibGUI, msg, title, b1, b2, def)` |
| `waitbar` | `wb = uiprogressdlg(obj.mibGUI,'Value',v,'Message',msg,'Title',title,'Cancelable','on')` |
| `inputdlg` / `mibInputMultiDlg` | `utils.dlgs.inputUniversalDlg(obj.mibGUI, header, prompts, defAns, title, options)` |

## `inputUniversalDlg`

**Signature:** `(ParentFigure, header, prompts, defAns, dlgTitle, options)`. `header` is a bold label
shown above the content - pass `''` when not needed. Icons: `'puffin_question'` (default),
`'puffin_warning'`, `'puffin_error'`, `'puffin_info'`.

- **Dropdown `defAns`:** `{'item1', 'item2', 'item3', 2}` - the items followed by a **numeric default
  index** as the last element. `answer{i}` returns the selected item string.
- **Spinner (numeric) `defAns`:** pass
  `struct('Spinner', true, 'Value', 5, 'Limits', [1 100], 'Step', 1, 'Round', true)`. `answer{i}`
  returns the numeric value directly - no `str2double`, assign as `BatchOpt.MyParam{1} = answer{i}`.

A dialog shown from more than one entry point belongs in `utils.dlgs` as a single function returning
a ready options struct, not copied into each caller: hand-synchronised prompt lists drift, and
nothing catches a mismatched `answer{n}` index. Worked example and rationale:
[`../deepmib/stitchInstances2Dto3D.md`](../deepmib/stitchInstances2Dto3D.md#where-the-settings-dialog-lives).

---

## Progress dialogs are always cancelable

Any `uiprogressdlg` must be created with `'Cancelable', 'on'`, and any `core.PoolWaitbar` with its
5th argument `Cancelable = true` (it defaults to **false**).

**Creating it is not enough - honour it.** Check `wb.CancelRequested` / `pwb.getCancelState()` at the
top of every loop iteration and before every irreversible operation, then clean up and return. A
progress bar the user cannot stop is a bug: if an operation is long enough to deserve a progress
dialog, it is long enough to deserve an exit.

```matlab
wb = uiprogressdlg(obj.view.gui, 'Message', 'Working...', 'Title', 'Task', 'Cancelable', 'on');
for k = 1:n
    if wb.CancelRequested; break; end     % also pass wb into helpers that loop
    wb.Value = k/n;
    ...
end
cancelled = wb.CancelRequested;   % read before deleting the handle
delete(wb);
```

```matlab
% parfor: the 5th argument is Cancelable and defaults to FALSE - always pass true
pwb = core.PoolWaitbar(n, 'Processing...', obj.mibGUI, 'Title', true);
parfor (i=1:n, parforArg)
    if pwb.getCancelState(); continue; end   % parfor cannot break, so skip the remainder
    pwb.increment();
end
pwb.deletePoolWaitbar();
```

`core.PoolWaitbar` rejects an empty parent - it needs a UIFigure or an existing `uiprogressdlg`
handle. A pure utility function with no figure of its own should therefore **take a `uiprogressdlg`
handle as an argument** rather than trying to build its own bar.

### What a long function owes the caller

- **Poll per unit of real work**, not per percent: one slice is enough work to be worth
  interrupting, and a Cancel button that only answers once a percent cannot be relied on.
- **Throttle the message, not the poll.** A uifigure property write forces a redraw, which on a
  thousand-slice stack costs more than the work it reports on. Refresh the text every `n/100`
  iterations and poll Cancel every iteration.
- **Return nothing on cancel.** A half-finished result looks like a valid one and gets written over
  the user's data. Return an empty result plus a `cancelled` flag and let the caller decide.
- **Say what was and was not done.** When work is abandoned part-way, report it rather than
  reporting success - especially when earlier iterations already wrote files.

---

## BatchOpt

### Numeric fields

Store as a 3-element cell: `BatchOpt.MyParam = {value, [minLim maxLim], 'on'}` - `{2}` is the spinner
limits, `{3}` `'on'` means integer rounding (`'off'` or omitted = float). Read with
`BatchOpt.MyParam{1}`, **not** `str2double`.

After `utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn)`, refresh the limits from the
actual dataset dims:

```matlab
maxSlice = obj.I{BatchOpt.id}.dim_yxzct(dimOrient);
BatchOpt.MyParam{2} = [1, maxSlice];
```

### Widget handle naming (silent-failure trap)

Every `.mlapp` widget that maps to a BatchOpt parameter must be **named exactly as its BatchOpt
field**, so the handle is `obj.view.handles.TileOrder`, `obj.view.handles.GridRows`, etc. (PascalCase;
exception: `showWaitbar` stays lowercase).

`core.ChildView` copies the component name into `Tag`, and `utils.updateBatchOptFromGUI_Shared`
writes `BatchOpt.(hObject.Tag)` - so a mismatched handle name silently dumps the value into a junk
field and the tool runs with defaults, with no error anywhere.

Non-BatchOpt widgets (buttons, axes, labels) use descriptive lowerCamel handles (`selectInputBtn`,
`previewAxes`).

### Session memory

A dialog that is worth re-opening on its last-used values stores them in
`MibModel.sessionSettings.<toolName>` - RAM only, not written to preferences, so restarting MIB
returns to the defaults. Do **not** preseed the key in `utils.defaults.generateSessionSettings`: the
defaults then live in two places and drift. The tool owns the key, writing it after a run and reading
it back on open.

Two entry points onto the same tool share **one** key, so a value entered at one is offered at the
other. When they cannot share a particular field (the same question asked in two different forms),
give that field a name per entry point and have each caller write **field by field** into the stored
struct rather than replacing it - otherwise a run from one side silently resets the other. Worked
example: [`../deepmib/stitchInstances2Dto3D.md`](../deepmib/stitchInstances2Dto3D.md).
