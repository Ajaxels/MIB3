function panelHandles = addDatasetsPanel(obj)
% function panelHandles = addDatasetsPanel(obj)
% add the Datasets panel, add context menus and callbacks for widgets
% The callbacks are added in the controller of the panel:
% controllers.MibDatasets during its creation in
% MibController.initialize() -> MibController.addGuiControllers()

arguments (Input)
    obj views.MibView
end

%% ---------------------- DATASETS PANEL ----------------------
panelOptions.Title = "Datasets";
panelOptions.Region = "left";
obj.handles.panels.datasetsPanel = matlab.ui.internal.FigurePanel(panelOptions);
obj.handles.panels.datasetsPanel.PreferredHeight = 70;
%obj.handles.panels.datasetsPanel.PreferredWidth = 120;
obj.handles.panels.datasetsPanel.Resizable = false;
%obj.handles.panels.datasetsPanel.Maximizable = false;
obj.handles.panels.datasetsPanel.Figure.AutoResizeChildren = 'off';

panelHandles = views.components.Datasets('Parent', obj.handles.panels.datasetsPanel.Figure, ...
    'Units', 'normalized', 'Position', [0 0 1 1]); % needs to have normalized units, by default those are pixels

% ---------------------- ADD CONTEXT MENUs ----------------------
% ---------------------- Add context menu for buffer buttons ----------------------
panelHandles.handles.buffersContext = uicontextmenu(obj.handles.panels.datasetsPanel.Figure);
panelHandles.handles.buffersContextDuplicate = uimenu(panelHandles.handles.buffersContext, ...
    'Text', 'Duplicate dataset', 'Tag', 'buffersContextDuplicate');
panelHandles.handles.buffersContextSyncXY = uimenu(panelHandles.handles.buffersContext, ...
    'Text', 'Sync view (x,y) with...', 'Tag', 'buffersContextSyncXY', 'Separator', 'on');
panelHandles.handles.buffersContextSyncXYZ = uimenu(panelHandles.handles.buffersContext, ...
    'Text', 'Sync view (x,y,z) with...', 'Tag', 'buffersContextSyncXYZ');
panelHandles.handles.buffersContextSyncXYZT = uimenu(panelHandles.handles.buffersContext, ...
    'Text', 'Sync view (x,y,z,t) with...', 'Tag', 'buffersContextSyncXYZT');
panelHandles.handles.buffersContextLink = uimenu(panelHandles.handles.buffersContext, ...
    'Text', 'Link view with... [Unlinked]', 'Tag', 'buffersContextLink', 'Separator', 'on');
panelHandles.handles.buffersContextClose = uimenu(panelHandles.handles.buffersContext, ...
    'Text', 'Close dataset', 'Tag', 'buffersContextClose', 'Separator', 'on');
panelHandles.handles.buffersContextCloseSet = uimenu(panelHandles.handles.buffersContext, ...
    'Text', 'Close all datasets of the set', 'Tag', 'buffersContextCloseSet');

% Add context menu to buttons
panelHandles.handles.buffer1.ContextMenu = panelHandles.handles.buffersContext;
panelHandles.handles.buffer2.ContextMenu = panelHandles.handles.buffersContext;
panelHandles.handles.buffer3.ContextMenu = panelHandles.handles.buffersContext;
panelHandles.handles.buffer4.ContextMenu = panelHandles.handles.buffersContext;
panelHandles.handles.buffer5.ContextMenu = panelHandles.handles.buffersContext;
panelHandles.handles.buffer6.ContextMenu = panelHandles.handles.buffersContext;
panelHandles.handles.buffer7.ContextMenu = panelHandles.handles.buffersContext;
panelHandles.handles.buffer8.ContextMenu = panelHandles.handles.buffersContext;
panelHandles.handles.buffer9.ContextMenu = panelHandles.handles.buffersContext;
panelHandles.handles.buffer10.ContextMenu = panelHandles.handles.buffersContext;

% ---------------------- Add context menu for sets dropdown ----------------------
panelHandles.handles.setsContext = uicontextmenu(obj.handles.panels.datasetsPanel.Figure);
panelHandles.handles.setsContextAdd = uimenu(panelHandles.handles.setsContext, ...
    'Text', 'Add set...', 'Tag', 'setsContextAdd');
panelHandles.handles.setsContextRename = uimenu(panelHandles.handles.setsContext, ...
    'Text', 'Rename set...', 'Tag', 'setsContextRename', 'Separator', 'on');
panelHandles.handles.setsContextRemove = uimenu(panelHandles.handles.setsContext, ...
    'Text', 'Remove set...', 'Tag', 'setsContextRemove', 'Separator', 'on');

% Add context menu to the dropdown and the add set button
panelHandles.handles.sets.ContextMenu = panelHandles.handles.setsContext;
panelHandles.handles.addSet.ContextMenu = panelHandles.handles.setsContext;

panelHandles.handles.datasetType.ValueChangedFcn = @(src, event)obj.controller.datasetsType_Callbacks(src, event);

obj.handles.panels.datasets = panelHandles;

% add the panel to GUI
obj.gui.add(obj.handles.panels.datasetsPanel);

end