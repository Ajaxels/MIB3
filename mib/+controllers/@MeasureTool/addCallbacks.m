function addCallbacks(obj)
% ADDCALLBACKS - Wire widget callbacks and build context menu.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.addCallbacks()
%
% Called once from the constructor after the view is created.
% All widget callbacks route through ``gui_Callbacks`` (dispatched by ``src.Tag``).
% The context menu is created here and attached to ``measureTable``.
%
% Input Arguments:
%   - **obj** — :class:`controllers.MeasureTool`
%

viewGui = obj.view.gui;

viewGui.CloseRequestFcn = @(~,~) obj.closeWindow();

h = obj.view.handles;
% Measure panel callbacks
h.measureTypeDropdown.ValueChangedFcn = @obj.gui_Callbacks;
h.integrateCheck.ValueChangedFcn      = @obj.gui_Callbacks;
h.interpolationModePopup.ValueChangedFcn  = @obj.gui_Callbacks;

% Plot panel
h.markersCheck.ValueChangedFcn        = @obj.gui_Callbacks;
h.linesCheck.ValueChangedFcn          = @obj.gui_Callbacks;
h.textCheck.ValueChangedFcn           = @obj.gui_Callbacks;
h.optionsBtn.ButtonPushedFcn          = @obj.gui_Callbacks;

% Voxel size panel
h.updateVoxelsButton.ButtonPushedFcn  = @obj.gui_Callbacks;

% Measurements panel
h.filterPopup.ValueChangedFcn         = @obj.gui_Callbacks;
h.refreshTableBtn.ButtonPushedFcn     = @obj.gui_Callbacks;
h.measureTable.CellSelectionCallback  = @obj.gui_Callbacks;

% Bottom buttons
h.loadBtn.ButtonPushedFcn             = @obj.gui_Callbacks;
h.saveBtn.ButtonPushedFcn             = @obj.gui_Callbacks;
h.deleteAllBtn.ButtonPushedFcn        = @obj.gui_Callbacks;
h.helpBtn.ButtonPushedFcn             = @obj.gui_Callbacks;
h.addBtn.ButtonPushedFcn              = @obj.gui_Callbacks;
h.closeBtn.ButtonPushedFcn            = @obj.gui_Callbacks;

% Context menu attached to measureTable
contextMenuHandle = uicontextmenu(viewGui);
uimenu(contextMenuHandle, 'Text', 'Modify info...', 'MenuSelectedFcn', @(~,~) obj.contextMenu('ModifyInfo'));
uimenu(contextMenuHandle, 'Text', 'Jump to measurement', 'MenuSelectedFcn', @(~,~) obj.contextMenu('Jump'), 'Separator','on');
uimenu(contextMenuHandle, 'Text', 'Modify measurement...', 'MenuSelectedFcn', @(~,~) obj.contextMenu('Modify'));
uimenu(contextMenuHandle, 'Text', 'Recalculate selected...', 'MenuSelectedFcn', @(~,~) obj.contextMenu('Recalculate'));
uimenu(contextMenuHandle, 'Text', 'Duplicate measurement', 'MenuSelectedFcn', @(~,~) obj.contextMenu('Duplicate'));
uimenu(contextMenuHandle, 'Text', 'Generate kymograph...', 'MenuSelectedFcn', @(~,~) obj.contextMenu('Kymograph'), 'Separator','on');
uimenu(contextMenuHandle, 'Text', 'Plot intensity profile...', 'MenuSelectedFcn', @(~,~) obj.contextMenu('Plot'));
uimenu(contextMenuHandle, 'Text', 'Delete measurement', 'MenuSelectedFcn', @(~,~) obj.contextMenu('Delete'), 'Separator','on');
h.measureTable.ContextMenu = contextMenuHandle;
end
