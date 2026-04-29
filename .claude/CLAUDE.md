# MIB3 Session Context

Supplementary to the root `CLAUDE.md` (architecture, conventions, essential conversion rules).

---

## Subtopic Guides

| File | When to read |
|------|--------------|
| [appdesigner_guide.md](appdesigner_guide.md) | Starting any new GUIDE → AppDesigner port: file layout, widget syntax, constructor pattern, checklist |
| [conversion_reference.md](conversion_reference.md) | Full conversion tables: PoolWaitbar, backup, clearing, data structures, bit packing, misc |
| [conversion_ui.md](conversion_ui.md) | Modifier keys, image display coords, orientation switching |
| [doc_template.md](doc_template.md) | Legacy Doxygen template — superseded by RST style |
| [../development/docs_api_sphinx.md](../development/docs_api_sphinx.md) | **RST docblock style guide** — use this for all new/updated docs |
| [port_batchprocessing.md](port_batchprocessing.md) | Full plan: 31 files, phased steps, `.mlapp` widget list |
| [port_roi.md](port_roi.md) | ROI architecture, widget handles, `roiToSelection` remaining |
| [port_loadmodel.md](port_loadmodel.md) | BatchOpt fields, extension→loader map, edge cases |
| [port_movelayers.md](port_movelayers.md) | Property mapping, fast/slow path, performance notes |
| [port_splitpanel.md](port_splitpanel.md) | Root causes, all fixes, reliable UI chain diagram |
| [sync_memory.md](sync_memory.md) | One-time setup command for Claude memory sync on a new workstation |
| [plan_crop.md](plan_crop.md) | CropDataset port log: all widget/event/BatchOpt conversions, runtime fixes, mlapp startupFcn pattern, pending `cropDataset` backend |
| [link_views_plan.md](link_views_plan.md) | Linked-view propagation: `linkedPairs` on MibModel, propagation in `showImage`, buffer-switch sync |
| [plan_resample.md](plan_resample.md) | ResampleDataset port log: all fixes, data-write pattern, boundingBox/dim sync, remaining tests |

---

## Essential Conversion Patterns (Quick Reference)

### Naming
- Classes: `mibXxxController` → `Xxx` (PascalCase, no `mib` prefix), in `+controllers/@Xxx/`
- Views: `mibXxxGUI.fig` → `+views/XxxGUI.mlapp`; accessed as `obj.view` (lowercase)
- Orientation XY: `4` → `3`; layer `'model'` → `'labels'`

### Data Accessors
```matlab
% getData unchanged (type first); setData SWAPPED — dataset first in MIB3!
obj.mibModel.getData2D(type, slice, orient, col, opts)
obj.mibModel.setData2D(dataset, type, slice, orient, col, opts)  % MIB2 was (type,dataset,...)
% Use [] not NaN for current slice/orient
% Always: BatchOpt.id = obj.getActiveId()  — obj.id may be stale in split-panel
```

### Events
| MIB2 | MIB3 |
|------|------|
| `notify(obj, 'plotImage')` | `notify(obj, 'ShowImage')` |
| `notify(obj, 'updateGuiWidgets')` / `'updateId'` | `notify(obj, 'UpdateGuiWidgets')` |
| `notify(obj, 'showModel', evd)` | `obj.showModel=true; notify(obj,'ShowImage')` |
| `notify(obj, 'showMask')` | `obj.showMask=true; notify(obj,'ShowImage')` |
| `notify(obj, 'updateLayerSlider', evd)` | update `slices{orient}` then `notify('SliceChanged')` |
| `notify(obj, 'updateTimeSlider', evd)` | update `slices{5}` then `notify('FrameChanged')` |
| `notify(obj, 'updatedAnnotations')` | `notify(obj, 'UpdateAnnotations')` |
| `ToggleEventData(x)` | `core.ToggleEventData(x)` |

### Modifier Keys (CRITICAL)
`UIFigure.CurrentModifier` is **unreliable** — stale after `pyrun()`, wrong in sub-figures.
```matlab
modifier = obj.mibController.currentModifier;  % CORRECT
modifier = hFig.CurrentModifier;               % WRONG
```

### AppDesigner Widget Syntax
| GUIDE | AppDesigner |
|-------|-------------|
| `.String` (edit box) | `.Value` |
| `.String` (label / button) | `.Text` |
| `popup.String` (item list) | `popup.Items` |
| `popup.String{popup.Value}` | `popup.Value` (string directly) |
| set popup by index | `popup.Value = popup.Items{3}` |
| `.TooltipString` | `.Tooltip` |
| `.BackgroundColor = 'g'` | `.BackgroundColor = [0 1 0]` |
| `.CData` (button icon) | `.Icon` |
| `findjobj + jTable.changeSelection` | `scroll(uitableHandle,'row',r)` |
| Button `Callback` | `ButtonPushedFcn` |
| Edit `Callback` | `ValueChangedFcn` |

### Controller Constructor Pattern
```matlab
core.ChildView(obj, 'views.XxxGUI')    % creates view, sets obj.view
utils.fontSizeUpdate(gui, Font)
utils.moveWindowOutside(gui, mibGUI, 'left')
obj.addCallbacks()                      % wire ALL callbacks here; set CloseRequestFcn first
obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(s,e) obj.ViewListner_Callback2(obj,s,e));
obj.listener{2} = addlistener(obj.mibModel, 'NewDataset',       @(s,e) obj.ViewListner_Callback2(obj,s,e));
```
`ViewListner_Callback2` — always guard:
```matlab
methods (Static)
    function ViewListner_Callback2(obj, src, evnt)
        if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
            for i=1:numel(obj.listener); delete(obj.listener{i}); end; return;
        end
        switch evnt.EventName
            case {'UpdateGuiWidgets','NewDataset'}; obj.updateWidgets();
        end
    end
end
```

### Data Structures
| MIB2 | MIB3 |
|------|------|
| `obj.model{1}` | `obj.labels.data{1}` |
| `obj.modelMaterialNames` | `obj.labels.materialNames` |
| `obj.modelFilename` | `obj.labels.filename` |
| `obj.modelVariable` | `obj.labels.labelsVariable` |
| `size(img,1/2/4/5)` → h/w/d/t | `obj.image.height/width/depth/time` |
| `obj.mibModel.I{id}.pixSize` | `obj.mibModel.I{id}.image.pixSize` |
| `getImageProperty('orientation')` | `obj.mibModel.I{id}.orientation` |
| `global mibPath` | `obj.mibModel.mibPath` |
| `global Font` | `obj.mibModel.preferences.System.Font` |
| `containers.Map` | `dictionary(keys, values)` (R2022b+) |

### Backup / Clearing
```matlab
obj.mibModel.backup('selection', 0, opts)   % switch3d=0: current slice, 1: full stack
obj.mibModel.I{id}.clearLayer('selection', '2D'/'3D'/'4D')
if obj.mibModel.I{id}.enableSelection == 0; return; end   % always check first
```

### Parallel Progress
```matlab
pwb = core.PoolWaitbar(n, 'Processing...', obj.mibGUI, 'Title');
parfor (i=1:n, parforArg); pwb.increment(); end
pwb.deletePoolWaitbar();
% Sequential loops: use plain uiprogressdlg with wb.Value = k/n
```

### Misc Renames
| MIB2 | MIB3 |
|------|------|
| `obj.View` | `obj.view` |
| `okBtn_Callback` / `cancelBtn_Callback` | `applyButton_Callback` / `closeButton_Callback` |
| `mibRescaleWidgets(gui)` | remove — AppDesigner handles scaling |
| `mibUpdateFontSize(gui, Font)` | `utils.fontSizeUpdate(gui, Font)` |
| `moveWindowOutside(h, 'left')` | `utils.moveWindowOutside(gui, mibGUI, 'left')` |
| `BatchOpt.mibBatchSectionName = 'Menu -> …'` | `'Ribbon -> …'` |
