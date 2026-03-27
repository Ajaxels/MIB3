function addCallbacks(obj)
% function addCallbacks(obj)
% Wire all widget callbacks once from the constructor.
%
% Called once at the end of the Quantification constructor.
% Every widget that needs a callback is wired here so the constructor
% stays clean.  Callbacks are set as anonymous functions so MATLAB passes
% the controller handle implicitly.
%
%|
% @b Examples:
% @code obj.addCallbacks();   // called inside Quantification constructor @endcode

% Updates
%

h = obj.view.handles;

% close callback — always set first
obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();

% buttons
h.quantify.ButtonPushedFcn = @(~,~) obj.quantification_Callback();
h.export.ButtonPushedFcn    = @(~,~) obj.exportButton_Callback();
h.closeBtn.ButtonPushedFcn        = @(~,~) obj.closeWindow();
h.defineProperties.ButtonPushedFcn     = @(~,~) obj.multipleBtn_Callback();
h.updateBtn.ButtonPushedFcn       = @(~,~) obj.updateWidgets();

% dropdowns
h.Material.ValueChangedFcn    = @(~,~) obj.material_Callback();
h.Property.ValueChangedFcn    = @(~,~) obj.property_Callback();
h.Units.ValueChangedFcn       = @(~,~) obj.units_Callback();
h.sortTable.ValueChangedFcn = @(~,~) obj.updateSortingSettings();
h.DatasetType.ValueChangedFcn = @(hObj,~) obj.updateBatchOptFromGUI(hObj);
h.ColorChannel1.ValueChangedFcn = @(hObj,~) obj.updateBatchOptFromGUI(hObj);
h.ColorChannel2.ValueChangedFcn = @(hObj,~) obj.updateBatchOptFromGUI(hObj);

% checkboxes
h.Multiple.ValueChangedFcn     = @(~,~) obj.multiple_Callback();
h.logScale.ValueChangedFcn    = @(~,~) obj.histScale_Callback();
h.highlightOnClick.ValueChangedFcn = @(hObj,~) obj.updateBatchOptFromGUI(hObj);

% radio buttons / button groups — use ButtonGroup SelectionChangedFcn
% (fires once per selection change; evt.NewValue is the newly selected button)
h.ObjectShape.SelectionChangedFcn   = @(~,evt) obj.radioButton_Callback(evt.NewValue);
h.DetectionType.SelectionChangedFcn = @(~,evt) obj.radioButton_Callback(evt.NewValue);

% table
h.statTable.CellSelectionCallback = @(~,evnt) obj.statTable_CellSelectionCallback(evnt.Indices, 'skip');

% histogram click
obj.view.gui.WindowButtonDownFcn = @(~,~) obj.gui_WindowButtonDownFcn();
h.highlightRange.ButtonPushedFcn = @(~,~) obj.highlightRange_Callback();

% keyboard shortcuts (undo, escape) — shared handler for child dialogs
obj.view.gui.WindowKeyPressFcn = @(h,d) utils.childWindowKeyPressFcn(obj, h, d);

% context menu
obj.createContextMenus();
end
