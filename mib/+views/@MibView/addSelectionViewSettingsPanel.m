function panelHandles = addSelectionViewSettingsPanel(obj)
% function panelHandles = addSelectionViewSettingsPanel(obj)
% add the Selection and View Settings panel, add context menus and callbacks for widgets
% The callbacks are added in the controller of the panel:
% controllers.MibSelection during its creation in
% MibController.initialize() -> MibController.addGuiControllers()

arguments (Input)
    obj views.MibView
end

%% ---------------------- SELECTION AND VIEW SETTINGS PANEL ----------------------
panelOptions.Title = "Selection and View settings";
panelOptions.Region = "bottom";

obj.handles.panels.selectionPanel = matlab.ui.internal.FigurePanel(panelOptions);
obj.handles.panels.selectionPanel.WindowBounds(3) = 100;
obj.handles.panels.selectionPanel.Resizable = false;
obj.handles.panels.selectionPanel.Figure.AutoResizeChildren = 'off';

panelHandles = views.components.SelectionViewSettings( ...
    'Parent', obj.handles.panels.selectionPanel.Figure, ...
    'Units', 'normalized', ...
    'Position', [0 0 1 1]); % needs to have normalized units, by default those are pixels

% add handle tags to tooltips when the developer mode is enable
if obj.mibModel.preferences.System.DeveloperMode 
    utils.overrideDescriptions(panelHandles.handles, true, 'obj.cSelection.view.handles'); 
end

% remove headers for the LUT table
panelHandles.handles.lutTable.ColumnName = {};

% ---------------------- Add CONTEXT Menus ----------------------
% ---------------------- Add context menu for lutTable ----------------------
panelHandles.handles.lutTableContext = uicontextmenu(obj.handles.panels.selectionPanel.Figure);

panelHandles.handles.lutTableContextInsert = uimenu(panelHandles.handles.lutTableContext, ...
    'Text', 'Insert empty channel', 'Tag', 'lutTableContextInsert');
panelHandles.handles.lutTableContextCopy = uimenu(panelHandles.handles.lutTableContext, ...
    'Text', 'Copy channel', 'Tag', 'lutTableContextCopy', 'Separator', 'on');
panelHandles.handles.lutTableContextInvert = uimenu(panelHandles.handles.lutTableContext, ...
    'Text', 'Invert channel', 'Tag', 'lutTableContextInvert');
panelHandles.handles.lutTableContextRotate = uimenu(panelHandles.handles.lutTableContext, ...
    'Text', 'Rotate channel', 'Tag', 'lutTableContextRotate');
panelHandles.handles.lutTableContextShift = uimenu(panelHandles.handles.lutTableContext, ...
    'Text', 'Shift channel', 'Tag', 'lutTableContextShift');
panelHandles.handles.lutTableContextSwap = uimenu(panelHandles.handles.lutTableContext, ...
    'Text', 'Swap channels', 'Tag', 'lutTableContextSwap');
panelHandles.handles.lutTableContextDelete = uimenu(panelHandles.handles.lutTableContext, ...
    'Text', 'Delete channel', 'Tag', 'lutTableContextDelete');
panelHandles.handles.lutTableContextSetLUT = uimenu(panelHandles.handles.lutTableContext, ...
    'Text', 'Set LUT color', 'Tag', 'lutTableContextSetLUT', 'Separator', 'on');

% Add the context menu to lutTable
panelHandles.handles.lutTable.ContextMenu = panelHandles.handles.lutTableContext;

obj.handles.panels.selection = panelHandles;

% add the panel to GUI
obj.gui.add(obj.handles.panels.selectionPanel);

end