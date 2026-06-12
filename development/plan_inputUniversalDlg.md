# inputUniversalDlg Audit & Refactor — Plan and State Log

**Status: COMPLETE** (June 2026). All steps implemented, live-verified against the
running MIB session, full `buildtool test` suite green (0 failed; 4 pre-existing
assumption-filtered parameterizations unrelated to dialogs).

## Context

`utils.dlgs.inputUniversalDlg` is MIB3's workhorse dialog (200+ call sites). It
caches its `uifigure` shell for re-render speed, but an audit found dead code,
~150 lines duplicated across the three sibling dialogs (`inputUniversalDlg`,
`inputSingleDlg`, `inputQuestDlg`), several bugs, hard-coded pixel metrics that
ignore font size/DPI, and one per-render hotspot (a nested wrapper
`uigridlayout` per widget row).

Decisions taken (user-approved):
1. Font-aware row heights + auto-calculated dialog height as the default.
2. Shared private helpers extracted for all three dialogs.
3. Per-widget wrapper grids eliminated, with live visual verification.

**Hard constraint honored:** public signatures, option names, and return
conventions unchanged — all 200+ call sites work as before.

## Files changed

- `mib/+utils/+dlgs/inputUniversalDlg.m` — main rework
- `mib/+utils/+dlgs/inputSingleDlg.m` — helper adoption + fixes
- `mib/+utils/+dlgs/inputQuestDlg.m` — helper adoption + fixes
- `mib/+utils/+dlgs/private/` — **new** shared helpers (not public API; RST docblocks):

| Helper | Owns (persistent state) |
|--------|------------------------|
| `dlgResolveMibDir(mibPath)` | cached MIB installation folder (`isdeployed`/`which('mib3')` detection) |
| `dlgResolveParent(ParentFigure, optParent)` | cached main-GUI handle; priority param > options > cache |
| `dlgLoadIcon(iconName, requestedWidth, bgColor, mibDir)` | icon filename table + alpha compositing + dictionary cache (invalidated on theme/bg change) |
| `dlgIconDefaultWidth(iconName)` | — (48 for `*_48px`, 220 for celebrate/call4help, 96 otherwise) |
| `dlgCenterOnParent(parent, w, h)` | — (AppContainer `WindowBounds` vs figure `Position` math; returns `[x y]` or `[]`) |
| `dlgAcquireFigure(tag, dlgTitle, mibDir)` | dictionary tag→figure shell; returns `isCached` flag |
| `dlgRowHeight(fig)` | cached font-derived row height: `max(22, round(fontSize*22/12))` via hidden probe uilabel; = 22 at factory 12px font |

## Bugs fixed

| # | Bug | Fix |
|---|-----|-----|
| B1 | `randi(6)` fallback but 7 `puffin_quest` icons exist | `randi(7)` in `dlgLoadIcon` |
| B2 | `puffin_measure` missing from 96px IconWidth list → 48px column | `dlgIconDefaultWidth` |
| B3 | Both `KeyPressFcn` + `WindowKeyPressFcn` bound → Enter/Esc fired twice | `WindowKeyPressFcn` only |
| B4 | Centering used requested, not realized, window size | `dlgCenterOnParent` takes final w/h |
| B5 | **Figure-shell leak**: nested same-type dialog overwrote the cache, orphaning the old shell forever | `dlgAcquireFigure` returns `isCached`; temp shells are `delete`d on close, cache untouched. Verified: 1 surviving shell vs 2 before |
| B6 | MsgBox auto-wrap check didn't `strtrim` (renderer did) → double-wrap on leading whitespace | aligned |
| B7 | `mibPath` missing from `knownOptionFields` case-normalizer | added |
| B8 | `inputSingleDlg` icon: raw file path, no alpha compositing/resize | uses `dlgLoadIcon` |
| B9 | Doc mismatches (WindowWidth 560 vs 450; height default; `waitfor` vs `uiwait`) | docstrings corrected |
| B10 | `inputQuestDlg` width-grow for long buttons computed AFTER `fig.Position` was set — never applied | grow first, then single Position write |

Dead code removed: early `answer`/`selectedIndices` init (overwritten before
`uiwait`), build-time `selectedIndices(i)` write, `clear` statement, second
`eval(H)` in `onHelp`, unused `chkH`, `helpBtn = []`.

## Performance changes

- **P1**: per-widget wrapper `uigridlayout`s eliminated — widgets parent directly
  into the column grid; vertical layout uses a fixed-height widget row
  (`rowHeight * PromptLines(i)`), horizontal keeps `'fit'` rows for single-line
  items (grow when label wraps) and fixed rows for `PromptLines > 1`.
- **P2**: `fig.Position` written once (collected from `dlgCenterOnParent`)
  instead of 4 indexed assignments.
- **P3**: Enter-key `pause(0.1)` → `drawnow` (value-commit verified: typed
  spinner value returned correctly). Applied to `inputSingleDlg` too.
- **P4**: second `drawnow` after the WindowStyle re-apply removed; modal-on-reuse
  verified working in the desktop engine. **Pending: one manual check in a
  deployed build** (the re-apply itself is kept — that part is the documented
  deployed-engine fix).
- Warm re-render unchanged (~40–100 ms); win is fewer UI objects + lower input latency.

## Auto-height (the new default)

`options.WindowHeight` omitted → `[]` → estimate from content; explicit values
behave exactly as before.

- **Normal mode**: per-item `rowHeight*(1+PromptLines(i))` (vertical; label 'fit'
  row + spacings ≈ one rowHeight) or `rowHeight*PromptLines(i)+6` (horizontal),
  summed per column with the builder's own distribution, take tallest column;
  overhead `54 = 20 padding + 10 row spacing + 24 button row`; `+ HeaderLines*rowHeight + 10`
  when a header exists; clamp `[110, 800]`.
- **MsgBoxOnly**: `(HeaderLines + bodyLines)*rowHeight + 110`, clamp `[150, 800]`;
  `bodyLines` from tag-stripped text length (~7 px/char) + `<br>`/`<li>` counts
  + block-margin allowance for `<p>/<ul>/<ol>`.

Calibration (verified by screenshot):
- `segmentationAnnotation` add-annotation dialog (2 prompts, vertical): **142 px**
  (was force-floored to 200 by the inherited `max(200,..)` clamp; old fixed
  default was 150). This was the user-reported "1–2 lines too tall" issue — fixed.
- 4-widget + header vertical example: 262 px.
- One-line warning msgbox: 176 px (old fixed default 150).

## Verification & tooling

- `temp\dlgTestHarness.m` (untracked) drives the blocking dialogs:
  polling timer (StartDelay 1 s, fixedSpacing 0.5 s — one-shot timers race cold
  uifigure creation) finds the dialog by Tag, screenshots via `exportapp` to
  `temp\dlg_<case>_<suffix>.png`, ticks DoNotShowAgain, presses OK
  (`btn.ButtonPushedFcn(btn,[])`) or sends synthetic Enter
  (`fig.WindowKeyPressFcn(fig, struct('Key','return'))`).
  Cases: example1 (2-col horizontal, all widget types), vertical, autoheight,
  annotation, msgbox_plain/html, headeronly, modal, spinner_enter, orphan
  (nested-dialog leak), single_edit/spinner, quest2/quest3, bench.
  First `exportapp` call costs ~20 s warm-up — bench case skips it.
- Before/after screenshots pixel-equivalent for all layouts; answers,
  `selectedIndices`, `dontShowAgain` round-trips asserted.
- Known pre-existing quirks (identical in baseline, NOT regressions):
  msgbox body text clipping at narrow widths; `uihtml` list items missing from
  `exportapp` captures (async paint); `inputSingleDlg` icon crop at 112 px height.
- `mcp__matlab__check_matlab_code` clean on all changed files;
  `buildtool test` (needs `addpath('tests')`): 0 failed.
- RST API docs: `docs_api/source/api/utils/dlgs/*.rst` use `autofunction`,
  so updated docstrings flow through automatically; private helpers need no entries.

## Behavior changes callers might notice

1. Dialogs that omit `WindowHeight` are now content-sized (was fixed 150).
2. `inputQuestDlg`: user-supplied `IconWidth` for puffin icons is respected
   (was force-overridden to 96); celebrate/call4help render at 220 px (was
   shrunk to 48); window icon (mib logo) now set.
3. Unknown icon ids default to a 96 px column (was 48 then overridden anyway).
4. In horizontal layout with `PromptLines > 1`, single-line widgets stretch to
   the row height (they already did inside the old wrappers).

## Open items

- [ ] Verify modal-on-reuse once in a **deployed build** (P4 single-drawnow change).
- [ ] graphify pipeline not refreshed: `graphify` Python module not installed in
  the Miniforge env (`development/graphify/install.md` → `pip install graphifyy`);
  run `python development/graphify/run_all.py` after installing.
