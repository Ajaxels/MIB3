# Dark/light color scheme adaptation

**Status (2026-09-24, not committed at time of writing):** implemented for the Datasets panel,
the standard buttons of 48 dialogs, StitchingInspector, message/error dialogs, BatchProcessing,
VolRenApp, Preferences, the Segmentation panel materials table, DeepMIB and its augmentation
settings, all plugins (2026-09-26); theme choice from Home ribbon -> Theme (2026-09-27), see
[Choosing the theme from MIB](#choosing-the-theme-from-mib-implemented-2026-09-27).
Remaining: one-off colors in other dialogs. Start with the rules and the recipe at the end.

## Problem
Widgets with hard-coded pastel `BackgroundColor` and `FontColor` left on auto become unreadable under
MATLAB's Dark theme: the auto text turns near-white (`[0.851 0.851 0.851]`) on a light pastel.
Measured WCAG contrast of the old buffer buttons in the dark theme: in-memory 1.0, file-backed 1.2,
selected 1.0 (target is 4.5:1).

## Theme detection (R2025a+, verified on R2026a)
- Per figure: `fig.Theme.BaseColorStyle` -> `'light'|'dark'` (`matlab.graphics.theme.GraphicsTheme`).
  For an AppContainer panel use its figure, e.g. `obj.view.handles.panels.datasetsPanel.Figure`.
  Guard with `isprop(fig, 'Theme')`; fall back to light on older releases.
- Desktop setting: `settings().matlab.appearance.MATLABTheme.ActiveValue` (`'Light'|'Dark'`).
  For testing, switch with `.TemporaryValue = 'Light'` and undo with `.clearTemporaryValue`.
- AppContainer panel figures are **not** returned by `findall(groot, 'Type', 'figure')`.

## Behaviour of colors on a theme switch (measured)
- A color in `...ColorMode = 'auto'` follows the theme (button: dark `[0.129 0.129 0.129]`,
  light `[0.961 0.961 0.961]`).
- An explicitly assigned color is **not** remapped. Repaint it from `fig.ThemeChangedFcn`.
- Borrowing a "default" color from another widget works only at the moment it is read. Use
  `BackgroundColorMode = 'auto'` for a default state instead.

## Options compared (prototype in two uifigures, one per theme)
| state | light, current | A: pastels + black text | B: dark backgrounds + theme text |
|-|-|-|-|
| empty | 19.2 | 18.4 (had to be painted light grey) | 11.4 (theme default) |
| in-memory `[1 0.85 0.6]` | 15.6 | 15.6 | 5.5 `[0.42 0.30 0.08]` |
| file-backed `[0.7 1 0.7]` | 17.9 | 17.9 | 6.2 `[0.20 0.32 0.20]` |
| selected `[0 1 0]` | 15.3 | 15.3 | 4.8 `[0 0.42 0]` |

- **A rejected:** black text on the theme's dark grey empty button is unreadable, so empty buttons
  must also be painted light, giving bright islands in a dark UI.
- **B chosen.** The first B attempt for selected (`[0.10 0.55 0.10]`) measured 3.1:1 and was darkened
  to `[0 0.42 0]`. File-backed was made greyer (`[0.20 0.32 0.20]`) to stay distinct from selected.

## Implementation (Datasets panel)
- `mib/+controllers/@MibActiveDataset/paintBufferButton.m` - `obj.paintBufferButton(buttonHandle, state)`,
  state `'empty'|'inMemory'|'fileBacked'|'selected'`. The palette is picked from
  `obj.UIFigure.Theme.BaseColorStyle`; `'empty'` sets `BackgroundColorMode = 'auto'`. The font color is
  never set.
- Callers: `update_fromModel.m`, `buffers_Callback.m`, `buffers_ContextMenu.m` (duplicate, close,
  closeSet), `@MibController/updateGuiWidgets.m` (guarded with `isa(obj.cActiveDataset, ...)` because it
  can run before the Datasets controller exists at startup).
- Constructor `MibActiveDataset.m`: `obj.UIFigure.ThemeChangedFcn = @(src, evnt) obj.update_fromModel()`.
  This is heavier than a pure repaint (it re-runs `buffers_Callback` -> `ShowImage`), which is accepted
  because theme switches are rare.
- Side fix: file-backed green was `[0.6 1 0.6]` in `update_fromModel` and `[0.7 1 0.7]` elsewhere; now
  `[0.7 1 0.7]` everywhere.

## Shared palette and dialogs (2026-09-24)
- `mib/+utils/themeColors.m` - the single palette: `utils.themeColors('light'|'dark'|hFig)`. Started
  with `.bufferInMemory .bufferFileBacked .bufferSelected .dialogAction .dialogClose`; the entries
  added later are described in the sections below, the docblock of `themeColors.m` lists them all.
  `paintBufferButton` reads it.
- Dialog buttons: a survey of the 61 `.mlapp` files found two standard colors -
  action green `[0.149 0.902 0.1804]` (55 widgets in 44 files) and close orange `[1 0.5294 0.102]`
  (49 widgets in 46 files). Dark mapping: action -> `[0 0.42 0]` (= bufferSelected),
  close -> `[0.42 0.30 0.08]` (= bufferInMemory). Light keeps the `.mlapp` colors.
- `mib/+utils/applyThemeColors.m` - `utils.applyThemeColors(obj.view.gui)` after
  `core.ChildView(...)`. It matches buttons by color, not by name (either theme's value, 1e-3 tolerance),
  so no per-dialog button list is needed and the same call is the `ThemeChangedFcn` handler.
- Rollout decision: one line per dialog constructor (not in `core.ChildView`), so each dialog is opted in
  explicitly. Done for all 47 `+views` dialogs that use the standard colors: 43 controllers after
  `obj.view = core.ChildView(...)`, plus 4 dialogs in `+utils/+dlgs` built directly
  (`AmiraImportDlg`, `selectModelTypeDlg` pass `obj.view.Figure`; `SelectHDFSeries`,
  `SelectLociSeriesDlg` pass `obj.view.gui`).
- Deliberately not done: `MibDeep` (pinned to light at the time; adapted on 2026-09-26, see below), dialogs without the
  standard colors (DisplayAdjust, VolRenApp, VolRenAppViewer, MibDeepActivations,
  MibDeepAugmentSettings), and plugins (their `.mlapp` files live under `plugins/`, not surveyed yet).
- Still open: one-off colors in single dialogs (light blues, creams, the `[0 1 0]` in 3 files) are not
  covered by `applyThemeColors` and need per-dialog decisions.
- Gotcha when testing: a class edited while an instance exists keeps running the old definition; close
  the dialog and `clear('controllers.<Name>')` before reopening.

## Second approach: keep pale colors, pin the text black (StitchingInspector, 2026-09-24)
Used where the colors carry meaning and a dark version would blur it (traffic-light score coding):
- `seamTable` row styles: `uistyle('BackgroundColor', <pale score color>, 'FontColor', [0 0 0])`
  (`updateWidgets.m`). The same pale colors are used for the minimap tiles, so they stay identical in
  both themes.
- Minimap tile numbers: `text(..., 'Color', [0 0 0])` (`renderMiniMap.m`); they sit on the pale
  tiles. The axes title stays on auto because it sits on the axes background.
- `excludeBtn`: pink `[1 0.72 0.72]` + black text when excluded; when included, both
  `BackgroundColorMode` and `FontColorMode` go back to `'auto'`. This replaced the
  `excludeBtnDefaultColor` property, which captured the theme color at open time and so restored the
  wrong color after a theme switch.

## Message and error dialogs (2026-09-24)
- `uihtml` renders a web page that ignores the MATLAB theme (white page, black text). In
  `inputUniversalDlg` (`MsgBoxOnly` mode) a `<style>` is inserted first into the page in the dark theme:
  background = `fig.Color`, text = `themeColors.text` (named `htmlText` at first), links = `themeColors.htmlLink`. Caller styles
  come later and still win. `exportapp` does not capture `uihtml` content, so check it by eye.
- `ImageFilters` `InfoHTML` (filter description): same `<style>` in `setInfoHtml`, background =
  the parent panel color. The page is written to a temp file per filter change, so the window's
  `ThemeChangedFcn` (local `imageFiltersThemeChanged`: `applyThemeColors` + rewrite the page for the
  current `FilterName`) keeps it in sync. The snippet became the shared `utils.themeHtmlStyle` when
  a third `uihtml` needed it (ImageConverter, below).
- `showErrorDialog`: the error text area lost its fixed white background and is fully on auto
  (dark `[0.071]` field with `[0.851]` text, 13.3:1). The suffix label uses `themeColors.dimmedText`
  (light `[0.4 0.4 0.4]` 5.3:1, dark `[0.65 0.65 0.65]` 6.6:1).

## BatchProcessing (2026-09-24)
- New palette entries, also matched by `applyThemeColors`: `dialogSecondary` (light
  `[0.6314 0.9412 0.6471]` -> dark `[0.20 0.32 0.20]`, 6.2:1; the Update button, kept weaker than Run)
  and `dialogStop` (light `[1 0 0]` -> dark `[0.6 0.1 0.1]`, 5.9:1; "Stop protocol").
- Runtime repaints of `runProtocol` (Run/Stop toggle in `BatchProcessing.m`, `doBatchStep.m`,
  `runProtocol_Callback.m`) read `utils.themeColors(obj.view.gui)` instead of literals; a literal
  would repaint the light color in the dark theme.
- `protocolComments` text area: `BackgroundColorMode = 'auto'` in the constructor. Correction
  (measured later): the light auto background of a `uitextarea` is `[1 1 1]`, not the mlapp's
  `[0.96 0.96 0.96]`, so in the light theme the area turns from light grey to white.
- Pattern to grep for in other dialogs: `BackgroundColor = [` in controller code, i.e. colors set at
  runtime, which `applyThemeColors` at construction does not see.

## VolRenApp (2026-09-24)
- `applyThemeColors` now also handles containers: `uitab`/`uipanel` backgrounds painted
  `tabHighlight` (light `[0.8 0.8 0.8]` -> dark `[0.25 0.25 0.25]`), and `uitab` titles whose
  `ForegroundColor` was set explicitly to the `text` color of either theme. App Designer writes the
  light default `[0.129 0.129 0.129]` once the title color is touched, which is invisible in dark.
- Gotcha: setting `ForegroundColorMode = 'auto'` on a tab whose color was manual does **not** recompute
  the color until the next theme change (verified: still `[0.129]` in dark after the call). Assign the
  palette color explicitly instead and let the `ThemeChangedFcn` keep it in sync.
- Palette `htmlText` renamed to `text` (normal text color, used for `uihtml` CSS and tab titles).
- Preview button: runtime `'r'` / `[0 1 0]` replaced by `dialogStop` / `dialogAction`.
- `modelTable` and `surfaceTable`: column 1 shows the material/surface colors through the table's
  row `BackgroundColor` (kept); columns 2-4/2-5 were a white `uistyle` with auto text. Now
  `tableCell` + `FontColor = text` (`updateModelTable`, `updateSurfaceTable`). The window's
  `ThemeChangedFcn` is the local `volRenAppThemeChanged` (`applyThemeColors` + both table updates;
  the surface table only when surfaces exist, because `updateSurfaceTable` also makes the first viewer
  child current).
- Not done yet: `spinTestButton` is repainted at runtime with literal `[1 0 0]` / `[0 1 0]`.

## Preferences (2026-09-24)
- `ModelsColorsTable`, `LUTColorsTable`: value columns 1-3 are painted with a `uistyle` (the rows
  carry the material colors, shown in column 4). First try, black text on white cells, was rejected
  by the author: light cells stand out in the dark UI. Now the style takes `themeColors.tableCell`
  (light `[1 1 1]`, dark `[0.0706]` = the dark field background) and `FontColor = themeColors.text`
  (light `[0.129]`, dark `[0.851]`; see the gotchas below for why it is not left on auto). The window's
  `ThemeChangedFcn` is a local `preferencesThemeChanged` that calls `applyThemeColors` and redraws both
  tables. Exception kept on purpose: the StitchingInspector seam table, where the cell color *is* the
  information (seam quality).
- Gotcha: a `uitable`'s own `ForegroundColor` is ignored in the dark theme (`[0 0 0]` still renders
  light grey); only `uistyle('FontColor', ...)` changes the cell text color.
- Gotcha: with only the style background set, the author saw **black** text on the dark cells on
  screen, while `exportapp` showed light text - `exportapp` is not a reliable check for table text.
  The style therefore sets `FontColor = themeColors.text` explicitly as well.
- Color-picker buttons (Selection, Mask, Annotations x2) show a user-chosen color, so the text is chosen
  from that color, not from the theme: black when its relative luminance > 0.179 (the point where black
  and white have equal WCAG contrast), else white. Local function `setColorButton` at the end of
  `Preferences.m` (8 call sites, all in that file). Defaults green/magenta/yellow -> black.
  Candidate for reuse wherever a widget shows a material or layer color.

## Segmentation panel materials table (2026-09-24)
- The author's direction: **all tables are dark with light text in the dark theme**; the only
  exceptions are cells whose color is the information (material swatches, seam quality).
- Columns 2-3 (names, Add To checkbox) and the Exterior swatch were painted white with black or grey
  text by `uistyle` in `updateMaterialsTable.m` and `materialsTable_CellSelectionCallback.m`. Now
  `tableCell` + `text`; the Mask and material swatches in column 1 keep their colors.
- New palette entries: `tableHighlight` (the selected material / Add To cell, light `[0.2 0.6 1]`
  -> dark `[0.10 0.33 0.62]`, 5.3:1 with `text`) and `disabledText` (names greyed out while the
  selection is restricted to a material, light `[0.78]` 1.7:1 on white -> dark `[0.40]` 3.3:1 on
  `tableCell`; deliberately below 4.5:1 so it reads as inactive, while normal text is 13.3:1).
- Highlighted cells: light text changed from black `[0 0 0]` to `text` `[0.129]` (7.1:1 -> 5.5:1),
  so the same style serves both themes.
- `MibSegmentation.m`: `obj.UIFigure.ThemeChangedFcn = @(src, evnt) obj.updateMaterialsTable([])`.
  The Datasets panel handler (`update_fromModel` -> `updateGuiWidgets`) also redraws the table, so a
  switch repaints it twice; kept, because that path depends on the order in which the two panel
  figures receive the theme change.
- `materialsTable_applyRowStyle.m` has no callers; its white default was changed to `tableCell` so
  it does not bring the white back if it is used later.

## Graphcut (2026-09-24)
- `backgroundMaterialPopup`, `signalMaterialPopup`: `updateMaterialsBtn_Callback` painted them white
  `[1 1 1]` when a model exists and red `[1 0 0]` without one (auto text on it 2.8:1 in dark). Now
  `BackgroundColorMode = 'auto'` and the new palette entry `fieldError` (= `dialogStop`, dark
  `[0.6 0.1 0.1]` 5.9:1). The pink `[1 0.76 0.76]` in the `.mlapp` is replaced by that callback in
  the constructor and never shows.
- `applyThemeColors` now also matches `uidropdown`, `uieditfield` and `uinumericeditfield` painted
  `fieldError` (verified both ways on an invisible `uifigure`), so any dialog with a red input field
  is remapped by the constructor line and on a theme switch.
- `superpixelsBtn`: runtime action green read from `themeColors.dialogAction`; reset with
  `BackgroundColorMode = 'auto'` instead of borrowing `resetDimsBtn.BackgroundColor` (same for
  `preprocessBtn`). `subAreaFromSelectionBtn`: busy red = `dialogStop`, restored with `'auto'` instead
  of a remembered color.

## Text areas with a fixed light grey (2026-09-24)
- A survey of all `.mlapp` files for `uitextarea` with a fixed color found three, all
  `BackgroundColor = [0.9608 0.9608 0.9608]`: BatchProcessing `protocolComments` (done earlier),
  WoundHealing `AboutTextArea` (also `FontColor = [0.149 0.149 0.149]`) and About `descriptionText`.
  Constructors set `BackgroundColorMode` (and `FontColorMode` where fixed) to `'auto'`.
- Unlike tab titles, a `uitextarea` switched to auto takes the theme colors at once (verified on an
  invisible `uifigure`: dark `[0.0706]` / `[0.851]`, light `[1 1 1]` / `[0.129]`), so no
  `ThemeChangedFcn` is needed.

## DeepMIB (2026-09-26)
- Was pinned to light with `theme(obj.view.gui, 'light')` in the `MibDeep` constructor; replaced by
  `utils.applyThemeColors(obj.view.gui)`.
- The `.mlapp` color-codes the workflow tabs, two shades per hue: tab/panel background (the stronger
  tint) and the buttons/fields on it (paler). Surveyed from `matlab/document.xml` inside the `.mlapp`:

  | hue | where | light panel | light widgets | dark panel | dark widgets |
  |-|-|-|-|-|-|
  | yellow | Directories and Preprocessing | `[1 0.9804 0.7686]` | `[1 0.9882 0.9098]` | `[0.28 0.245 0.14]` 7.5:1 | `[0.17 0.153 0.102]` 10.6:1 |
  | blue | Train | `[0.7686 0.902 0.9882]` | `[0.8784 0.9608 1]` | `[0.144 0.238 0.3]` 8.1:1 | `[0.11 0.158 0.19]` 10.6:1 |
  | green | Predict | `[0.8588 0.9294 0.7804]` | `[0.9098 0.9608 0.9098]` | `[0.199 0.27 0.149]` 7.4:1 | `[0.12 0.17 0.111]` 10.4:1 |

  Palette entries `panelYellow/Blue/Green` and `widgetYellow/Blue/Green`; `applyThemeColors` matches
  panel tints on `uitab`, `uipanel`, `uilabel` (two labels carry the Predict tint) and buttons (the
  active action button carries its tab color), widget tints on buttons and input fields. No other
  `.mlapp` uses these six colors.
- Choice of the dark tints, prototyped side by side in a dark `uifigure` (dark defaults measured:
  containers and buttons `[0.1294]`, edit fields `[0.0706]`):
  - hue kept from the light color, HSV value 0.27-0.30 for panels, just above the theme background so
    the tint is visible without glowing;
  - widgets **darker** than the panel (V 0.17), rejected alternative: lighter (V 0.36-0.40, 5.2-5.5:1).
    Darker follows the dark theme's own convention (fields darker than their background), mirroring
    light mode where the widgets are paler than the panel, and keeps the higher contrast;
  - yellow moved from hue 52 to 45 (amber-brown): at hue 52 the dark tint read as muddy olive.
- The `.mlapp` callback `ModeSelectionChanged` disables the inactive action buttons with
  `btn.BackgroundColor = app.NetworkPanel.BackgroundColor`, a copied theme default that stays stale
  after a theme switch. Not fixed in the `.mlapp`; instead `applyThemeColors` puts any button whose
  manual background equals `themeColors.background` (either theme) back on `'auto'`. Only three other
  `.mlapp` files hold `[0.9608]`, all on text areas, so the rule touches only DeepMIB today.
- Runtime repaints of `TrainButton` (`start.m`, `startTraining.m`, `startTrainingInstances.m`): idle
  `panelBlue`, running `dialogAction` (was `'g'`), stopping `dialogClose` (was `[1 .5 0]`). All three
  are matched by `applyThemeColors`, so a theme switch during training also repaints the button.
- Not done: the custom training progress window (`deepmib.customTrainingProgressDisplay*`, a separate
  figure) still repaints `StopTrainingButton` with literals (`[0 1 0]`, the Train blue, grey
  `[0.85]`); the `MibDeepActivations` sub-dialog was not surveyed.
- Verified live on R2026a: open in dark, the three tabs by `exportapp`, Dark -> Light -> Dark switch with the
  window open, both directions (tints and the borrowed-default buttons follow).

## DeepMIB augmentation settings (2026-09-26)
- `MibDeepAugmentSettingsGUI.mlapp`: probability spinners yellow `[0.9804 0.9765 0.8235]` (19),
  Min/Max spinners blue `[0.8314 0.9333 1]` (24); the info text of the dialog refers to "yellow boxes"
  and "blue boxes", so the hues must stay recognizable. OK `[0 1 0]`, Close `[1 0 0]` (= `dialogStop`).
- Palette `fieldYellow` / `fieldBlue`; `applyThemeColors` now also collects `uispinner` into the field
  group. Dark tints tried on the live dialog:
  - darker than the background (V 0.13-0.15, like the theme's own fields): 11.8-12.4:1, but the hue is
    gone, yellow and blue both read as near-black - rejected;
  - lighter than the background (V 0.30-0.34): `[0.3 0.278 0.135]` 6.7:1, `[0.17 0.249 0.34]` 7.6:1 -
    chosen. Unlike the DeepMIB tabs, these fields sit on the plain background, not on a tinted panel.
- Two `.mlapp` colors off the palette are normalized in the constructor before `applyThemeColors`:
  `RandScale_Probability` (`[0.9804 0.9804 0.8196]`, a stray variant of the yellow) -> `fieldYellow`,
  `OK` (`[0 1 0]`) -> `dialogAction` (light `[0.149 0.902 0.1804]`, visually the same). Fixing both in
  App Designer would make these two lines unnecessary.
- Verified live: dark at open, enabled/disabled spinners, Dark -> Light -> Dark with the dialog open.
- Testing gotcha: DeepMIB without a CUDA GPU shows a modal Warning (`inputUniversalDlg`) from the
  constructor, which blocks a scripted start. Press its OK from a timer
  (`feval(findobj(fig, 'Type', 'uibutton', 'Text', 'OK').ButtonPushedFcn, [], [])`); deleting the
  figure breaks the cached dialog, and interrupting the constructor with Ctrl+C leaves a
  `'controllers.MibDeep'` reservation in `mib.childControllersIds` that makes every later start return
  silently until it is removed.

## ImageConverter and MultiRenameTool plugins, shared uihtml style (2026-09-26)
- First plugin adapted (`plugins/FileProcessing/ImageConverter`). Convert/Close carry the standard
  `dialogAction`/`dialogClose`, handled by `applyThemeColors`.
- `infoText` is a third `uihtml`, so the `<style>` snippet became `utils.themeHtmlStyle(hFig,
  backgroundColor)` (`''` in light); `inputUniversalDlg` and `ImageFilters.setInfoHtml` now call it,
  output verified identical. The plugin prepends it to its `HTMLSource` fragment (a `<style>` element
  at the start of a fragment is applied), background = `infoText.Parent.BackgroundColor`.
- `ThemeChangedFcn` = local `imageConverterThemeChanged` (`applyThemeColors` + rewrite `HTMLSource`),
  set before the first call so `applyThemeColors` does not install itself.
- MultiRenameTool plugin, same recipe: Rename/Close standard colors; `infoHTML1` (on
  `FilenameTemplatePanel`) is written in `updateWidgets`, which now prepends `themeHtmlStyle`, so the
  local `multiRenameToolThemeChanged` is `applyThemeColors` + `obj.updateWidgets()`.
- Survey of all 13 plugins (2026-09-26): 11 `.mlapp` files use the standard action/close colors.
  `utils.applyThemeColors(obj.view.gui)` added after `core.ChildView` in the other 9
  (TripleAreaIntensity, GolgiOrientation, Granularity, MCcalc, SurfaceArea3d, ThreshAnalysisForObjects,
  DemoPlugin, GuiTutorial, GuiTutorialBatch) and to the constructor template in
  `plugins_instructions.md`, which also got a short paragraph on runtime colors and `uihtml`.
  SurfaceMeasurements has no fixed colors, PluginWithoutGUI no window.
- Granularity runtime colors, same fix as Graphcut: invalid subarea field and the material dropdown
  without a model -> `fieldError`, valid -> `BackgroundColorMode = 'auto'` (was `[1 1 1]`);
  `subAreaFromSelectionBtn` busy -> `dialogStop`, restored with `'auto'` (was a remembered color).
- Verified live in dark: buttons of all plugins. MCcalc first failed to open ("Undefined function
  'MCcalcGUI'"): the file was `McCalcGUI.mlapp` while the class inside is `MCcalcGUI`. Renamed to
  `MCcalcGUI.mlapp`; with `core.ignorecase = true` git saw only a content change, so the rename was
  recorded with `git mv -f`, otherwise case-sensitive clones (Linux, macOS) keep the old name.
- GolgiOrientation: three color-coded tabs whose visible color sits on the grid layout filling each
  tab (the tabs' own colors, yellow `[1 1 0.0667]` and `[0.8627 0.9333 0.9608]`, are hidden by the
  grids in both themes and left alone). New palette entries, dark tints tried on the live window:

  | entry | light | dark | contrast |
  |-|-|-|-|
  | `panelRed` (Complete model files) | `[0.9882 0.9216 0.9216]` | `[0.27 0.176 0.176]` | 8.9:1 |
  | `panelMint` (Cropped cells dirs) | `[0.9098 0.9882 0.902]` | `[0.153 0.25 0.15]` | 8.1:1 |
  | `panelSky` (Settings) | `[0.8196 0.9294 0.9686]` | `[0.15 0.26 0.3]` | 7.5:1 |
  | `widgetMint` (buttons/fields on red and mint) | `[0.9882 1 0.9882]` | `[0.102 0.12 0.102]` | 11.9:1 |

  First try for the red, S 0.42 (`[0.28 0.162 0.162]`), read as an error red; desaturated to S 0.35.
  `applyThemeColors` now also collects `uigridlayout` into the container group (no other `.mlapp`
  has a grid in a matched tint). `filenameExtensionGridLayout` carries the pre-R2025a default grey
  `[0.9412]` (the only use in any `.mlapp`): set to auto in the constructor, a local line.
  `infoHTML` is written in `addInfo` (on each mode change), which prepends `themeHtmlStyle`; the
  local `golgiOrientationThemeChanged` = `applyThemeColors` + `addInfo`. Verified live: 3 tabs in
  dark, Dark -> Light -> Dark with the window open.
- Checking `uihtml` by eye without `exportapp`: `java.awt.Robot().createScreenCapture` over the
  figure `Position` (y flipped against `groot.ScreenSize`) captures the real rendering.

## Choosing the theme from MIB (implemented 2026-09-27)
Investigated 2026-09-26 on R2026a in MATLAB (not in a compiled build); route 1 below was implemented.

**Route 1 - the MATLAB setting (preferred).**
- `s = settings; s.matlab.appearance.MATLABTheme` has `ActiveValue`, `TemporaryValue`,
  `PersonalValue`, `InstallationValue`, `FactoryValue`. On the test machine: `PersonalValue = 'Dark'`,
  `FactoryValue = 'System'` (follow the OS). Values: `'Light'`, `'Dark'`, `'System'`.
- `TemporaryValue = 'Light'|'Dark'` switches everything at once: the main window (`AppContainer`,
  created with `EnableTheming = true` in `initializeMibView.m`), its panels and every dialog. All `ThemeChangedFcn` handlers run,
  which is how every change in this note was tested. `clearTemporaryValue` returns to the user's own
  setting.
- `TemporaryValue` lasts for the MATLAB session only and does not touch the saved preference;
  `PersonalValue` would persist in the user's MATLAB settings - too intrusive for a MIB option.
- Side effect in MATLAB: the setting is global, so the whole MATLAB desktop and all other figures
  switch with MIB while the session runs.

**Route 2 - per window (MIB only, but incomplete).**
- `theme(fig, 'light'|'dark')` sets one figure and switches its `ThemeMode` from `'auto'` to
  `'manual'`; `fig.ThemeMode = 'auto'` makes it follow MATLAB again.
- Works for `AppContainer` panel figures too: in a throwaway `AppContainer` on a dark desktop, a
  `FigurePanel` forced to light rendered light next to a dark panel.
- But the `AppContainer` chrome (ribbon, panel title bars, document area) follows only the MATLAB
  setting: the class has no theme property, only `EnableTheming` and an internal
  `handleThemeSupport` method. Forcing light on a dark desktop gives light panels inside a dark ribbon.
- No default for new figures: `set(groot, 'defaultFigureTheme', ...)` fails with "SET or GET of
  default values is not permitted on the Theme property of the Figure class". Every window would need
  the theme applied at creation (`core.ChildView` would cover the `+views` dialogs; `utils.dlgs`
  dialogs, progress dialogs and plain `figure`/`uifigure` windows would each need it).

**Not verified - compiled version.** `isdeployed` was 0 in this session, and the MathWorks
documentation does not say how standalone apps pick their theme or whether the `settings` API works
in MATLAB Runtime. Commit `9f27a830` ("dark theme ... compiled version") suggests the compiled app does
show the dark theme. To check in a compiled build: read
`settings().matlab.appearance.MATLABTheme.ActiveValue` and try setting `TemporaryValue`.

**Implementation (2026-09-27).**
- Preference **`preferences.Colors.Theme`** = `'System' | 'Light' | 'Dark'`, default `'System'` in
  `generatePreferences.m`. `initializePreferences.m` backfills it (and replaces an unknown value),
  because a `mib3.mat` of the same MIB version replaces the defaults wholesale instead of merging.
- Chosen in the Home ribbon, Preferences section: `homeHandles.themeButton` (DropDownButton) with
  the list items `systemTheme`, `lightTheme`, `darkTheme` (`addRibbonHome.m`), handled in
  `MibRibbon/home_Callbacks.m` by their text. The switch is immediate. The earlier `Theme` dropdown on
  `ColorsPanel` of `PreferencesGUI.mlapp` is not wired.
- `utils.setMibTheme(themeName)` - the one place that touches the setting: `'System'` ->
  `clearTemporaryValue` (only when a temporary value exists), `'Light'`/`'Dark'` -> `TemporaryValue`.
  Returns `false` without an error when the setting does not exist (before R2025a) or the settings
  API throws (possibly the compiled runtime); the ribbon callback then shows a message and does not
  store the choice.
- Startup: `initializeMibView.m` calls it **before** the `AppContainer` is created, so the window is
  built in the chosen theme; `'System'` is not applied at startup (nothing to undo).
- Exit: `exitProgram.m` calls `utils.setMibTheme('System')` when the preference is not `'System'`.
  The panel figures are destroyed only after `exitProgram` returns, so it first clears
  `ThemeChangedFcn` on every `FigurePanel` in `obj.view.handles.panels` (Datasets and Segmentation
  have one). Without that, closing with the window's X button raised "Invalid or deleted object" in
  `MibSegmentation.materialsTable_CellSelectionCallback` ("Error while evaluating DestroyedObject
  ThemeChangedFcn"). Closing with `mib.view.gui.close()` from the command line did not show the
  error, so that is not a valid test for this path.
- `Preferences` apply writes its whole copy of `preferences` back to the model; it now keeps
  `Colors.Theme` from the model first, otherwise a copy made before a ribbon switch (or reset by the
  Defaults button) would store the wrong theme.
- Verified live on R2026a (desktop Light): Dark, Light, System from the ribbon; Dark saved on exit
  and applied at the next start; MATLAB back to Light after exit.
- Still unverified: the compiled version.

References: MathWorks, [Graphics and App Themes](https://www.mathworks.com/help/matlab/creating_plots/graphics-and-app-themes.html),
[Change Desktop Theme and Colors](https://www.mathworks.com/help/matlab/matlab_env/change-desktop-colors-and-select-dark-theme.html),
[Design Graphics and Apps for Different Themes](https://www.mathworks.com/help/matlab/creating_plots/design-graphics-and-apps-for-different-themes.html).

## Rules
Which approach, by what the color does:

| the color is... | example | approach |
|-|-|-|
| a decorative state | dialog buttons, buffer buttons, highlighted tab | dark version of the hue from `themeColors`, text on auto |
| color-coding of window parts | DeepMIB Preprocess/Train/Predict tabs | `panel...` / `widget...` tints: dark hue, widgets darker than the panel |
| a plain background for values | Preferences color tables (value cells), materials table names, text areas | follow the theme: `...ColorMode = 'auto'`, or for `uistyle` cells `tableCell` + explicit `FontColor = text` (selected cell: `tableHighlight`, greyed out: `disabledText`) |
| the information itself | seam-quality table and minimap | keep the pale color, pin the text black |
| chosen by the user | Selection/Mask/Annotations color buttons | text black or white from the color's luminance (0.179), theme-independent |

- Restore a default state with `...ColorMode = 'auto'`, never with a remembered color.
- Explicit colors are not remapped on a theme switch: give the figure a `ThemeChangedFcn` that repaints
  (`applyThemeColors` installs itself; a window with more to repaint wraps it, like
  `preferencesThemeChanged`).
- `uitable` text: only `uistyle('FontColor', ...)` works in the dark theme; set it explicitly whenever a
  style sets the cell background.

## Recipe for the next dialog
1. Survey its `.mlapp` for fixed colors (`BackgroundColor`, `FontColor`, `ForegroundColor`) and grep its
   controller for `BackgroundColor = [`, `FontColor`, `uistyle` - runtime colors are not seen by
   `applyThemeColors`, which runs once at construction.
2. Pick the approach from the Rules table. Standard colors are handled by the constructor line
   `utils.applyThemeColors(obj.view.gui)`; add a new entry to `themeColors` (and to the matcher in
   `applyThemeColors` if it should switch generically) rather than a literal. Dark colors need >= 4.5:1
   against `[0.851 0.851 0.851]`.
3. Runtime repaints read `utils.themeColors(obj.view.gui).<name>`.
4. Test live in both themes and across a switch (`MATLABTheme.TemporaryValue`, then
   `clearTemporaryValue`). Check tables and `uihtml` by eye: `exportapp` does not show them reliably.
   Open and close dialogs through `startController` / `closeWindow` - deleting a window leaves its
   model listeners behind.

Alternative for windows where adapting is not worth it: pin the window to light with
`theme(fig, 'light')` (as `MibDeep.m` did until 2026-09-26); explicit background colors are preserved.
