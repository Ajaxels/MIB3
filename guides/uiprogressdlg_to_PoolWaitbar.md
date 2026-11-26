# Converting `uiprogressdlg` to `core.PoolWaitbar`

## When to Convert

Use `core.PoolWaitbar` instead of a plain `uiprogressdlg` when:
- The loop needs a **Cancel button**.
- The loop is or may become a **`parfor`** loop (DataQueue makes UI updates thread-safe).
- You want a uniform progress API across sequential and parallel loops.

Keep a plain `uiprogressdlg` for simple, non-cancelable sequential tasks where PoolWaitbar is overkill.

---

## Constructor Mapping

```matlab
% BEFORE — plain dialog
wb = uiprogressdlg(obj.view.gui, ...
    'Title',   'Window Title', ...
    'Message', 'Preparing...', ...
    'Value',   0);

% AFTER — PoolWaitbar (cancelable)
pwb = core.PoolWaitbar(N, 'Preparing...', obj.view.gui, 'Window Title', true);
%                      ^N must be known at this point (total loop iterations)
%                                                                          ^false = no Cancel button
```

**Critical:** `N` (total iterations) must be known before construction.
If `N` is computed after the old `wb` was created, **move the constructor to after `N` is known**.

---

## API Mapping

| `uiprogressdlg` (old) | `core.PoolWaitbar` (new) |
|-----------------------|--------------------------|
| `wb = uiprogressdlg(gui, 'Title', t, 'Message', m, 'Value', 0)` | `pwb = core.PoolWaitbar(N, m, gui, t, cancelable)` |
| `wb.Value = k / N` | `pwb.increment()` — call once per iteration |
| `wb.Message = 'text'` | `pwb.updateText('text')` |
| `wb.CancelRequested` | `pwb.getCancelState()` |
| `wb.Value = 1; delete(wb)` | `pwb.deletePoolWaitbar()` |
| `delete(wb)` (keep dialog open) | `pwb.deletePoolWaitbar(true)` |

---

## Loop Patterns

### Sequential `for` loop with Cancel

```matlab
pwb = core.PoolWaitbar(nPts, 'Preparing...', obj.view.gui, 'Task Title', true);

for k = 1:nPts
    if pwb.getCancelState(); break; end          % check cancel FIRST
    pwb.updateText(sprintf('Step %d / %d', k, nPts));

    % ... body ...

    pwb.increment();                              % advance bar LAST
end

pwb.deletePoolWaitbar();
```

### Parallel `parfor` loop (no cancel polling inside parfor)

```matlab
pwb = core.PoolWaitbar(n, 'Processing...', obj.view.gui, 'Task Title');

parfor k = 1:n
    % ... body ...
    pwb.increment();   % only safe PoolWaitbar call inside parfor
end

pwb.deletePoolWaitbar();
```

For cancelable `parfor`, poll between batches on the main thread:

```matlab
pwb = core.PoolWaitbar(n, 'Processing...', obj.view.gui, 'Task Title', true);
pwb.setIncrement(batchSize);

for batchStart = 1:batchSize:n
    if pwb.getCancelState(); break; end
    batchEnd = min(batchStart + batchSize - 1, n);
    parfor k = batchStart:batchEnd
        pwb.increment();
    end
end

pwb.deletePoolWaitbar();
```

---

## Step-by-Step Conversion Checklist

1. **Find `N`** — identify the total iteration count; note where in the code it becomes available.
2. **Move/remove old `wb` creation** — delete the `uiprogressdlg(...)` call.
3. **Insert PoolWaitbar constructor** immediately after `N` is known:
   ```matlab
   pwb = core.PoolWaitbar(N, 'Initial message', obj.view.gui, 'Title', true);
   ```
4. **Replace `wb.Value` + `wb.Message` lines** at the top of the loop body:
   - `wb.Value = ...` → `pwb.increment()` moved to the **bottom** of the loop body
   - `wb.Message = sprintf(...)` → `pwb.updateText(sprintf(...))` kept at the **top**
5. **Add cancel check** as the first line inside the loop:
   ```matlab
   if pwb.getCancelState(); break; end
   ```
6. **Add `pwb.increment()`** as the last statement before the loop `end`.
7. **Replace cleanup**:
   - `wb.Value = 1; delete(wb)` → `pwb.deletePoolWaitbar()`
   - If keeping the dialog open for a next phase: `pwb.deletePoolWaitbar(true)`

---

## Common Pitfalls

- **`N` not yet known at old `wb` position** — the old dialog was often created early to show "Preparing..." before heavy setup. Move the PoolWaitbar constructor to after setup, or use an indeterminate dialog for the prep phase if it is long.
- **`wb.Value = 1` at the end** — drop this; `deletePoolWaitbar()` closes the dialog without needing a final value set.
- **Calling `getCancelState()` inside `parfor`** — unsafe; only `increment()` is parfor-safe. Poll cancel between batches on the main thread.
- **`updateText()` inside `parfor`** — unsafe for the same reason; update text between batches only.
- **`setIncrement(k)`** — use when you want to call `increment()` less frequently (e.g. every `k` iterations) to reduce DataQueue overhead in large loops.
