# MIB2 → MIB3 Plugin System

## Overview

MIB ships with an extensible plugin system that lets users drop a folder of
MATLAB code under `plugins/` (MIB3) or `Plugins/` (MIB2) and have it appear in
the UI as a launchable tool. The discovery is purely filesystem-based: the
folder layout *is* the configuration. No registry, no manifest.

```
plugins/
  <SectionName>/             one folder per section/category
    <PluginName>/            one folder per plugin
      <PluginName>.m         class file (handle class)
      <PluginName>GUI.mlapp  AppDesigner GUI (optional)
      icon_24px.png          ribbon/menu icon (24 px)
      icon_16px.png          small icon (16 px, currently unused by ribbon)
      ...                    plugin-specific helper files
```

Both versions share the contract that the plugin's *class name matches the
folder name*, so a folder `FileProcessing/ImageConverter/` contains
`ImageConverter.m` defining `classdef ImageConverter < handle`.

---

## MIB2

### Discovery and path setup

`GuiTools/mibGUI.m:364-400` walks `<mibPath>/Plugins/<Section>/<Plugin>/`,
creates a nested `uimenu` under the **Plugins** menu, and — crucially — calls
`addpath(custom_dir2)` for each plugin folder when running from source
(skipped under `isdeployed`, since the standalone build bakes everything in):

```matlab
func_dir = fullfile(handles.mibController.mibPath, 'Plugins');
if ~isdeployed(); addpath(func_dir); end
% ... iterate sections ...
%     iterate plugins ...
        if ~isdeployed; addpath(custom_dir2); end
        uimenu(hSubmenu, 'Label', <spaced name>, ...
            'Callback', @(s,e) handles.mibController.startPlugin(<folder name>));
```

### Class naming convention

Plugin classes are named `<FolderName>Controller`, e.g. folder
`DemoPluginAppDesigner/` contains `DemoPluginAppDesignerController.m`.

### Launch path

`Classes/@mibController/startPlugin.m`:

```matlab
function startPlugin(obj, pluginName)
    obj.startController([pluginName 'Controller']);
end
```

So the menu callback hands the *folder name* to `startPlugin`, which appends
the `Controller` suffix and delegates to the generic `startController`. From
there the standard child-controller machinery (dedup via `findChildId`,
`CloseEvent` listener, etc.) takes over.

---

## MIB3

### Discovery

`mib/+views/@MibView/addRibbonPlugins.m` walks
`<mibPath>/plugins/<Section>/<Plugin>/` and builds a toolstrip
`Gallery` (one `GalleryCategory` per section, one `GalleryItem` per plugin).
Each item uses `icon_24px.png` from the plugin's folder, falling back to
`matlab.ui.internal.toolstrip.Icon.PLAY_24` when the icon is missing.
Section/plugin display names are derived from the folder names by inserting a
space before each capital letter (`MultiRenameTool` → `Multi Rename Tool`).

The function supports a `lazyInit` mode: on first ribbon construction it only
creates the empty **Plugins** tab, and the actual gallery is built the first
time the user clicks the tab (driven by
`controllers.MibController.globalTabGroup_SelectionCallback`).

### Path setup

MIB3 ships as a MATLAB project (`MIB3.prj`) that handles automatic linking of
all source directories — including `plugins/<Section>/<Plugin>/` — onto the
MATLAB path. No explicit `addpath` in user code is needed.

### Class naming convention

Unlike MIB2, MIB3 plugin classes have **no** `Controller` suffix — the class
name equals the folder name exactly. Example:

```
mib/plugins/FileProcessing/ImageConverter/
    ImageConverter.m           (classdef ImageConverter < handle)
    ImageConverterGUI.mlapp
```

The plugin's own doc-comment shows the launch contract:

```matlab
% obj.startController('ImageConverter');                        % as GUI tool
% obj.startController('ImageConverter', [], BatchOpt);          % batch mode
% obj.startController('ImageConverter', [], NaN);               % return BatchOpt
```

### Launch path

`utils.startController(parentObj, controllerName, varargin)`
(`mib/+utils/startController.m`) is the single shared implementation used by
every controller — `MibController`, built-in controllers (`Annotations`,
`Quantification`, `MibDeep`, `Lines3dDialog`), and plugins alike.
`controllers.MibController.startController` is a thin delegate to it.

`utils.startController`:

1. Calls `find(strcmp(parentObj.childControllersIds, controllerName))` to dedup;
   if already open, refocuses and calls `updateWidgets()` (or, in batch mode,
   just re-invokes the constructor).
2. Otherwise allocates a new slot, builds the controller via
   `str2func(controllerName)(parentObj.mibModel, varargin{:})`, and stores it in
   `parentObj.childControllers{id}`.
3. Wires a `CloseEvent` listener bound to `utils.purgeChildController` so the
   slot is released when the child closes.
4. For batch-only / no-GUI controllers (`noGui` field, or empty `view`),
   immediately re-fires `CloseEvent` after the constructor so cleanup runs.

Plugin controllers call it directly with `obj` as the parent:

```matlab
utils.startController(obj, 'controllers.ResampleDataset');
utils.startController(obj, 'controllers.ResampleDataset', [], BatchOpt);
```

There is no separate `startPlugin` wrapper in MIB3 — the gallery callback calls
`utils.startController` (via `MibController.startController`) with the folder
name directly.

### Child controller teardown

Every controller that opens children must close them in its own `closeWindow`
before deleting its GUI:

```matlab
for i = numel(obj.childControllers):-1:1
    if isvalid(obj.childControllers{i})
        obj.childControllers{i}.closeWindow();
    end
end
obj.childControllers    = {};
obj.childControllersIds = {};
% ... delete GUI, listeners, notify CloseEvent ...
```

Omitting this leaves child windows open on screen after the parent closes.
See `development/guides/startController.md` for full lifecycle details.

---

## Side-by-side

| Aspect | MIB2 | MIB3 |
|--------|------|------|
| Plugin root | `<mibPath>\Plugins\` | `<mibPath>\plugins\` (lowercase) |
| UI surface | Top-level `Plugins` menu (`uimenu`) | Toolstrip ribbon **Plugins** tab, `Gallery` widget |
| Discovery code | `mibGUI.m:364-400` | `+views/@MibView/addRibbonPlugins.m` |
| Path setup | `addpath` in `mibGUI.m`, gated on `~isdeployed` | MATLAB project auto-links directories |
| Icons | None on `uimenu` | `icon_24px.png` per plugin (fallback `Icon.PLAY_24`) |
| Class name | `<Folder>Controller` | `<Folder>` (no suffix) |
| Wrapper method | `mibController.startPlugin(name)` adds `'Controller'` suffix | None — direct call |
| Launch | `startPlugin('Foo')` → `startController('FooController')` | `startController('Foo')` |
| Dedup / lifecycle | `findChildId` / `purgeControllers` per-controller | `utils.startController` / `utils.purgeChildController` — shared utility |
| Lazy init | n/a | Yes — gallery built on first Plugins-tab click |

---

## Current Plugins (MIB3)

```
plugins/
  FileProcessing/
    ImageConverter/        — ImageConverter.m + ImageConverterGUI.mlapp
    MultiRenameTool/       — MultiRenameTool.m + MultiRenameToolGUI.mlapp
```

---

## Plan: Wire the Ribbon Gallery to `startController`

### Problem

Up until this change, `addRibbonPlugins.m` did all the discovery work and
built the gallery correctly, but each item's `ItemPushedFcn` was a placeholder
that only printed to the command window:

```matlab
item.ItemPushedFcn = @(varargin)(fprintf('Plugin: "%s" pressed\n', item.Text));
```

Clicking a gallery item did nothing useful.

### Fix (applied)

In the inner `for pluginId = 1:numel(pluginList)` loop, capture the folder
name into a local variable *before* the spaced display name overwrites it,
and replace the dummy callback with a real launch call:

```matlab
pluginClassName = pluginList{pluginId};
% add space before capital letter
pluginName = regexprep(pluginClassName, '([A-Z])', ' $1');
pluginName = strtrim(pluginName);

item = matlab.ui.internal.toolstrip.GalleryItem(pluginName, icon);
item.ItemPushedFcn = @(varargin) obj.controller.startController(pluginClassName);
```

The new local variable matters because MATLAB anonymous functions capture
workspace values *at creation time*. Capturing `pluginClassName` (one binding
per iteration) guarantees each gallery item launches its own plugin.

### Why no `addpath`

MIB3's MATLAB project takes care of linking plugin directories. If a future
plugin lives outside the project's auto-linked tree, the discovery loop would
need an explicit `addpath` (gated on `~isdeployed`, like MIB2). Not currently
required.

### Files changed

- `mib/+views/@MibView/addRibbonPlugins.m` — 1 line added, 1 line replaced.

### Verification

1. Static check: `mcp__matlab__check_matlab_code` on the modified file —
   no warnings.
2. `cd C:\Matlab\MIB3\mib; mib3` → click **Plugins** ribbon tab.
3. Click **Image Converter** → `ImageConverterGUI.mlapp` opens.
4. Click it again while open → existing window refocuses (handled by
   `startController.m:35-43`), no duplicate.
5. Click **Multi Rename Tool** → `MultiRenameToolGUI.mlapp` opens.
6. Command window no longer prints `Plugin: "..." pressed`.

---

## Future work (not part of this change)

- **`icon_16px.png`** is required by the convention but not yet consumed by
  the ribbon (gallery items use 24 px). Consider also surfacing plugins in
  the Quick Access Bar or context menus where 16 px is the right size.
- **Per-plugin metadata**: MIB2 has no manifest; MIB3 could optionally read a
  small `plugin.json` (description, tooltip, hotkey, batch capability flag)
  to enrich the gallery item (`item.Description`, tooltips, etc.). The
  current code carries a TODO-style commented-out
  `%item.Description = '...'` line.
- **Deployed builds**: when MIB3 is compiled, plugin classes need to be
  picked up by the deployment script. Verify `deploymentScript.m` includes
  `mib/plugins/**` in the package set before the next standalone release.
- **Porting MIB2 plugins**: the bulk of the user-facing MIB2 plugins
  (`Plugins/Tutorials/*`, `Plugins/Tools/*`, etc.) still need the standard
  GUIDE → AppDesigner port and the `*Controller` → `*` rename. Each ported
  plugin slots into `mib/plugins/<Section>/<Name>/` and is picked up
  automatically by this gallery — no further wiring.
