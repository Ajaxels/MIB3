# `utils.startController` — Launching Child Controllers

## Problem

`MibController.startController` was the traditional way to open any child controller
(e.g. `ResampleDataset`, `CropDataset`).  It manages a tracked list of open windows
and handles interactive, batch, and already-open cases.

Plugin controllers only hold a reference to `MibModel` — they have no access to
`MibController` and therefore cannot call `obj.mibController.startController(...)`.

Several built-in controllers (`Annotations`, `Quantification`, `MibDeep`, `Lines3dDialog`)
had their own duplicate `startController` / `purgeControllers` implementations to
work around this limitation.

## Solution

`utils.startController(parentObj, controllerName, varargin)` provides the same
behaviour as a free utility that any controller can use.

All controllers — `MibController`, `Annotations`, `Quantification`, `MibDeep`,
plugin controllers, and any future controller — call it directly.  There is one
shared implementation and no per-controller wrappers.

---

## Contract — what the parent controller must provide

```matlab
properties
    childControllers    = {}    % cell array of open child controller handles
    childControllersIds = {}    % cell array of open child controller class names
    mibModel                    % handle to MibModel
end
```

No other infrastructure is required on the parent side.

## Contract — what the child controller must provide

| Requirement | Description |
|-------------|-------------|
| Constructor | `MyController(mibModel)` — interactive, or `MyController(mibModel, [], BatchOpt)` — batch |
| Event | `CloseEvent` — fired when the controller closes (both interactive and batch) |
| Property | `view` — set to the GUI handle in interactive mode; stays `[]` in batch mode |

---

## Usage

### Interactive mode — opens a GUI window

```matlab
utils.startController(obj, 'controllers.ResampleDataset');
```

- If the window is already open, it is brought to front and refreshed.
- `CloseEvent` cleanup is wired automatically.

### Batch mode — runs silently with no GUI

Pass a `BatchOpt` struct as the third argument (second vararg):

```matlab
BatchOpt.SomeField = 'value';
utils.startController(obj, 'controllers.ResampleDataset', [], BatchOpt);
```

- The child constructor merges the provided `BatchOpt` with its defaults,
  executes its action, and returns immediately.
- If the window is already open, batch mode still runs through without
  re-using the existing instance.

### Signature

```matlab
utils.startController(parentObj, controllerName)
utils.startController(parentObj, controllerName, [], BatchOpt)
utils.startController(parentObj, controllerName, [], NaN)   % trigger returnBatchOpt
```

---

## Lifecycle and cleanup

`utils.startController` wires a `CloseEvent` listener on the child that calls
`utils.purgeChildController(parentObj, src)`, which:

1. Guards against a deleted parent (`isvalid` check).
2. Finds the child by `class(src)` in `parentObj.childControllersIds`.
3. Calls `delete` on the child if still valid.
4. Removes the child from both tracking arrays.

### Batch-mode cleanup detail

In batch mode the child fires `CloseEvent` **inside its constructor**, before
`addlistener` has been called.  After the constructor returns, `view` is still
empty.  `utils.startController` detects this and re-fires `CloseEvent`, which
is caught by the now-wired listener and triggers cleanup.

### Parent closes before child

Every `closeWindow` method that owns a `childControllers` list **must** close
all children before tearing down its own GUI.  Failing to do so leaves the child
window open on screen with a dead parent reference.

`utils.purgeChildController` contains an `isvalid(parentObj)` guard as a
last-resort safety net, but it is not a substitute for explicit teardown.

The required pattern — placed at the very top of `closeWindow`, before deleting
the GUI or listeners:

```matlab
function closeWindow(obj)
    for i = numel(obj.childControllers):-1:1
        if isvalid(obj.childControllers{i})
            obj.childControllers{i}.closeWindow();
        end
    end
    obj.childControllers    = {};
    obj.childControllersIds = {};
    % ... delete GUI, listeners, notify CloseEvent ...
end
```

Iterating in **reverse** (`numel:-1:1`) avoids index-shifting if a child's own
`CloseEvent` modifies the list during teardown.

This pattern is currently applied in:
`@Quantification`, `@MibDeep`, `@Annotations`, `@Lines3dDialog`,
`plugins/Tutorials/GuiTutorial`.

---

## Files

| File | Role |
|------|------|
| `mib/+utils/startController.m` | Main utility — instantiates, tracks, and wires the child |
| `mib/+utils/purgeChildController.m` | CloseEvent callback — removes the child from tracking arrays |
| `mib/+controllers/@MibController/startController.m` | Thin wrapper — delegates to `utils.startController` |
