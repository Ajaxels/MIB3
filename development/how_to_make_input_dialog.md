# How to Make Input Dialogs in MIB3

## Summary of Findings (March 2026)

The original `inputSingleDlg.m` and `inputUniversalDlg.m` dialogs used `java.awt.Robot` and timer-based deferred focus to force keyboard focus on input widgets. This approach was fragile — it simulated mouse clicks and keyboard events at the OS level, which could misfire depending on window manager state and timing.

Testing with `focusExample.m` proved that calling `focus(widget)` directly on a uifigure that is **created visible** gives immediate, reliable keyboard focus without any Java dependency.

Both dialogs were refactored to use this simpler pattern. The key insight is that `focus()` works when the figure is already visible at the time of the call. When a figure is created with `Visible='off'` and made visible later, the OS window activation race means `focus()` may fire before the window is ready — hence the original `java.awt.Robot` workaround.

### What changed

| Aspect | Old pattern | New pattern |
|--------|------------|-------------|
| Figure creation | `uifigure('Visible', 'off')` | `uifigure()` (visible by default) |
| Rendering | `drawnow; fig.Visible = 'on';` | Not needed — already visible |
| Focus mechanism | Timer + `java.awt.Robot` click + `focus()` | Direct `focus(widget)` call |
| Blocking | `uiwait(fig)` / `uiresume(fig)` | `waitfor(fig)` |
| Closing | `uiresume(fig); delete(fig)` | `delete(fig)` |
| Enter key commit | Timer-based `deferredClose` | `focus(okBtn); pause(0.1); onOK()` |

### Why each change matters

- **`Visible='on'` (default)**: The OS activates the window immediately on creation, so `focus()` has a valid target. With `Visible='off'` + later show, there is a race condition.
- **`waitfor(fig)` vs `uiwait(fig)`**: `waitfor` blocks until the figure is deleted — no need for `uiresume`. Simpler control flow with fewer failure modes. When the user closes the dialog via the X button, `waitfor` unblocks automatically; `uiwait` requires explicit `uiresume` or a `CloseRequestFcn`.
- **`pause(0.1)` on Enter**: When the user presses Enter, `WindowKeyPressFcn` fires *before* the widget commits its edited value. Moving focus to the OK button (`focus(okBtn)`) triggers the widget's commit, and `pause(0.1)` gives MATLAB one event-loop cycle to process it. This replaces the old one-shot timer approach which had the same purpose but more complexity.

---

## Template: Creating a New Input Dialog

Use this pattern for any new dialog in MIB3.

### Minimal single-input dialog

```matlab
function answer = myDialog(ParentFigure, prompt, defAns, dlgTitle)
    arguments
        ParentFigure = []
        prompt char = 'Enter value:'
        defAns = ''
        dlgTitle char = 'Input'
    end

    answer = [];

    % 1. Create figure VISIBLE (default) — required for focus() to work
    fig = uifigure('Name', dlgTitle);
    fig.Position(3:4) = [400 112];
    fig.Tag = 'myDialog';

    % 2. Build layout
    g = uigridlayout(fig, [3 1], ...
        'RowHeight', {'1x', 22, 22}, ...
        'Padding', [10 10 10 10], 'RowSpacing', 10);

    uilabel(g, 'Text', prompt, 'WordWrap', 'on', 'FontWeight', 'bold');

    ef = uieditfield(g, 'text', 'Value', char(defAns));
    ef.Layout.Row = 2;

    btnGrid = uigridlayout(g, [1 3], ...
        'ColumnWidth', {'1x', 80, 80}, 'Padding', [0 0 0 0]);
    btnGrid.Layout.Row = 3;

    uilabel(btnGrid, 'Text', '');  % spacer
    okBtn = uibutton(btnGrid, 'Text', 'OK', ...
        'ButtonPushedFcn', @(~,~) onOK());
    okBtn.Layout.Column = 2;
    uibutton(btnGrid, 'Text', 'Cancel', ...
        'ButtonPushedFcn', @(~,~) onCancel());

    % 3. Key handling
    fig.WindowKeyPressFcn = @(~, evt) onKey(evt);

    % 4. Center on parent (optional)
    centerOnParent(fig, ParentFigure);

    % 5. Focus input widget DIRECTLY — no timer, no java.awt.Robot
    focus(ef);

    % 6. Block with waitfor (not uiwait)
    waitfor(fig);

    % --- Nested callbacks ---
    function onOK()
        answer = char(ef.Value);
        delete(fig);   % just delete, no uiresume needed
    end

    function onCancel()
        answer = [];
        delete(fig);
    end

    function onKey(evt)
        if isequal(evt.Key, 'escape')
            onCancel();
        elseif isequal(evt.Key, 'return')
            focus(okBtn);   % commit widget value
            pause(0.1);     % let event loop process the commit
            onOK();
        end
    end
end
```

### Rules to follow

1. **Never use `Visible='off'`** then flip to `'on'`. Create the figure visible from the start.

2. **Call `focus(widget)` directly** after building the layout. No timers, no `java.awt.Robot`, no `drawnow` before focus.

3. **Use `waitfor(fig)` to block**, not `uiwait(fig)`. This means callbacks close the dialog with `delete(fig)` only — no `uiresume` call.

4. **Enter key handling**: Always `focus(okBtn); pause(0.1);` before calling `onOK()`. The `pause(0.1)` is essential — without it, the widget's pending edit (typed text not yet committed) will be lost because `WindowKeyPressFcn` fires before the widget's internal commit.

5. **Escape key**: Call `onCancel()` directly (no pause needed — there is nothing to commit on cancel).

6. **Initialize `answer = []` before `waitfor`**. If the user closes the window via the X button, `waitfor` returns and `answer` remains `[]`, which callers interpret as cancelled.

7. **Parent figure centering**: Use the same `AppContainer` / `uifigure` detection pattern from `inputSingleDlg.m` (check `isa(parent, 'matlab.ui.container.internal.AppContainer')` for `WindowBounds` with Y-axis conversion, or `isa(parent, 'matlab.ui.Figure')` for direct `Position`).

8. **Persistent caching**: Cache `parentFigureHandle` and `mibDir` as `persistent` variables so subsequent calls with `ParentFigure=[]` reuse the last valid parent, and icon paths are resolved only once.

### Anti-patterns to avoid

| Do NOT do this | Do this instead |
|---------------|-----------------|
| `java.awt.Robot()` for focus | `focus(widget)` |
| `timer` + callback for deferred focus | Direct `focus()` call |
| `uifigure('Visible', 'off')` then `fig.Visible = 'on'` | `uifigure()` (visible by default) |
| `uiwait(fig)` / `uiresume(fig)` | `waitfor(fig)` / `delete(fig)` |
| `drawnow` before showing | Not needed when figure starts visible |
| `timer` for Enter key commit | `focus(okBtn); pause(0.1);` |

### Reference implementations

- **`+utils/+dlgs/inputSingleDlg.m`** — Single editfield or spinner input with icon. Use as template for simple one-value dialogs.
- **`+utils/+dlgs/inputUniversalDlg.m`** — Multi-widget dialog supporting editfields, spinners, dropdowns, checkboxes, HTML, and message-box mode. Use as template for complex dialogs.
- **`development/focusExample.m`** — Minimal proof-of-concept that `focus(ef)` works directly.
