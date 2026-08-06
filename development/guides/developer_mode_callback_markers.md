# DeveloperMode callback markers

A tiny trace line at the top of every user-triggered callback, so that with
**Preferences → DeveloperMode ON** the command window prints the exact
controller method that fired — the developer reads the name, selects the handle,
and opens the callback.

## The marker

```matlab
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.<Controller>.<callbackName>: triggered\n');
end
```

- `<Controller>` = class/folder name without the `@` (e.g. `Stitching`).
- `<callbackName>` = the method / function name exactly as defined.
- Use the object's real handle name for the first token (almost always `obj`;
  it is the first input argument of the method).

## Placement rule

Put the marker as the **first executable line**, i.e. immediately **after** the
docstring, and **after** an `arguments … end` block if the method has one
(an `arguments` block must stay the first statement):

```matlab
function fooBtn_Callback(obj)
% FOOBTN_CALLBACK - ...docstring...

arguments (Input)          % only if present
    obj controllers.Xxx
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Xxx.fooBtn_Callback: triggered\n');
end
... first real code ...
```

Match the surrounding indentation: column 0 for separate function-file
callbacks, method-body indent (`function` indent + 4) for inline `classdef`
methods.

## What to mark

Mark every method **wired directly to a widget event** — the ones you'd find in
`addCallbacks` (or the constructor) on the right-hand side of
`ButtonPushedFcn`, `ValueChangedFcn`, `CellSelectionCallback`,
`CellEditCallback`, `MenuSelectedFcn`, `CloseRequestFcn`, `KeyPressFcn`,
`ButtonDownFcn`, `WindowScrollWheelFcn`, context-menu items, etc. This includes
the generic `updateBatchOptFromGUI` (it is the sync callback) and `closeWindow`.

**Callbacks shared by multiple widgets — include `hObject.Tag`** so the trace
identifies which widget fired. This applies to `updateBatchOptFromGUI` and any
other orchestrating callback wired to more than one widget (e.g. `binMagButtons_Callback`):

```matlab
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Xxx.updateBatchOptFromGUI(%s): triggered\n', hObject.Tag);
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Xxx.binMagButtons_Callback(%s): triggered\n', hObject.Tag);
end
```

**When the discriminator is an argument, not a handle.** Many shared callbacks are wired
as `@(~,~) obj.foo_Callback('add')` — the widget handle never reaches the method, and the
char argument *is* what tells the widgets apart. Print that argument instead of `hObject.Tag`:

```matlab
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.BatchProcessing.protocolActions_Callback(%s): triggered\n', options);
end
```

Only ever print a discriminator that is guaranteed `char`/`string` at that point. If the
argument has a `nargin` default, put the marker **after** the default assignment (it is
the same exemption `arguments … end` gets) so the value is always defined:

```matlab
function backupProtocolRestore(obj, mode)
% ...docstring...

if nargin < 2; mode = 'undo'; end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.BatchProcessing.backupProtocolRestore(%s): triggered\n', mode);
end
```

To enumerate them for a controller, read its `addCallbacks`; or grep the wiring:

```
Fcn\s*=\s*@   /   ContextMenu\s*=   /   @\([^)]*\)\s*obj\.(\w+)
```

For AppDesigner controllers that wire callbacks inside the `.mlapp` view
(e.g. `Preferences`, `VolRenApp`), the wiring is not in the `.m`; identify the
callbacks by name convention (`*_Callback`, `*Callbacks`, `*CellSelection`,
`*CellEdit`) and by methods that take an `event`/`indices`/`value` argument.

## `gui_Callbacks.m` switch dispatchers — one global marker

Controllers that route every widget through a single `gui_Callbacks(obj, source, event)`
dispatcher get **one** marker before the `switch`, printing the routed tag
dynamically (do **not** add a marker per `case`):

```matlab
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Xxx.gui_Callbacks/%s: triggered\n', source.Tag);
end
switch source.Tag
    ...
```

## Do NOT mark

- **One-time wiring / helpers:** `addCallbacks`, `setupCallbacks`, `updateWidgets`,
  `returnBatchOpt`, render/compute helpers — not user-triggered.
- **Event listeners:** `*Listner_Callback`, `ViewListner_Callback2`, camera/data
  listeners — fired by the model, not a widget.
- **Continuous mouse-move / drag hover handlers** wired to `WindowButtonMotionFcn`
  (e.g. an inspector's `pairViewMotion`): they fire on every pixel and would flood
  the console.
- **Inline lambdas with no method body** (`... = @(~,~) web('http://...')`): nothing
  to mark.

## After editing

Static-check every touched file — `checkcode(file,'-struct')` (or the MATLAB
Code Analyzer) — and grep for the collapsed-marker mistake `DeveloperMode.*fprintf`
on a single line (must return nothing). If scripting bulk inserts in PowerShell,
build each marker line with pure `"${var}..."` interpolation — `"a" + "b", "c"`
collapses because `,` binds tighter than `+`.
