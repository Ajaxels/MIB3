function addDatasetsPanel(obj)
% function addDatasetsPanel(obj)
% add the Datasets panel, add context menus and callbacks for widgets

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
obj.handles.panels.datasets = views.components.Datasets('Parent', obj.handles.panels.datasetsPanel.Figure, ...
    'Units', 'normalized', 'Position', [0 0 1 1]); % needs to have normalized units, by default those are pixels
% add handle tags to tooltips
if obj.mibModel.developerMode; utils.overrideDescriptions(obj.handles.panels.datasets.handles, true, 'obj.handles.panels.datasets.handles'); end

% ---------------------- ADD CONTEXT MENUs ----------------------
% ---------------------- Add context menu for buffer buttons ----------------------
obj.handles.panels.datasets.handles.buffersContext = uicontextmenu(obj.handles.panels.datasetsPanel.Figure);
obj.handles.panels.datasets.handles.buffersContextDuplicate = uimenu(obj.handles.panels.datasets.handles.buffersContext, ...
    'Text', 'Duplicate dataset', 'Tag', 'buffersContextDuplicate', ...
    'MenuSelectedFcn', @(src, event)obj.controller.datasetsBuffers_ContextMenu(src, event));
obj.handles.panels.datasets.handles.buffersContextSyncXY = uimenu(obj.handles.panels.datasets.handles.buffersContext, ...
    'Text', 'Sync view (x,y) with...', 'Tag', 'buffersContextSyncXY', 'Separator', 'on', ...
    'MenuSelectedFcn', @(src, event)obj.controller.datasetsBuffers_ContextMenu(src, event));
obj.handles.panels.datasets.handles.buffersContextSyncXYZ = uimenu(obj.handles.panels.datasets.handles.buffersContext, ...
    'Text', 'Sync view (x,y,z) with...', 'Tag', 'buffersContextSyncXYZ', ...
    'MenuSelectedFcn', @(src, event)obj.controller.datasetsBuffers_ContextMenu(src, event));
obj.handles.panels.datasets.handles.buffersContextSyncXYZT = uimenu(obj.handles.panels.datasets.handles.buffersContext, ...
    'Text', 'Sync view (x,y,z,t) with...', 'Tag', 'buffersContextSyncXYZT', ...
    'MenuSelectedFcn', @(src, event)obj.controller.datasetsBuffers_ContextMenu(src, event));
obj.handles.panels.datasets.handles.buffersContextLink = uimenu(obj.handles.panels.datasets.handles.buffersContext, ...
    'Text', 'Link view with... [Unlinked]', 'Tag', 'buffersContextLink', 'Separator', 'on', ...
    'MenuSelectedFcn', @(src, event)obj.controller.datasetsBuffers_ContextMenu(src, event));
obj.handles.panels.datasets.handles.buffersContextClose = uimenu(obj.handles.panels.datasets.handles.buffersContext, ...
    'Text', 'Close dataset', 'Tag', 'buffersContextClose', 'Separator', 'on', ...
    'MenuSelectedFcn', @(src, event)obj.controller.datasetsBuffers_ContextMenu(src, event));
obj.handles.panels.datasets.handles.buffersContextCloseSet = uimenu(obj.handles.panels.datasets.handles.buffersContext, ...
    'Text', 'Close all datasets of the set', 'Tag', 'buffersContextCloseSet', ...
    'MenuSelectedFcn', @(src, event)obj.controller.datasetsBuffers_ContextMenu(src, event));

% Add context menu to buttons
obj.handles.panels.datasets.handles.buffer1.ContextMenu = obj.handles.panels.datasets.handles.buffersContext;
obj.handles.panels.datasets.handles.buffer2.ContextMenu = obj.handles.panels.datasets.handles.buffersContext;
obj.handles.panels.datasets.handles.buffer3.ContextMenu = obj.handles.panels.datasets.handles.buffersContext;
obj.handles.panels.datasets.handles.buffer4.ContextMenu = obj.handles.panels.datasets.handles.buffersContext;
obj.handles.panels.datasets.handles.buffer5.ContextMenu = obj.handles.panels.datasets.handles.buffersContext;
obj.handles.panels.datasets.handles.buffer6.ContextMenu = obj.handles.panels.datasets.handles.buffersContext;
obj.handles.panels.datasets.handles.buffer7.ContextMenu = obj.handles.panels.datasets.handles.buffersContext;
obj.handles.panels.datasets.handles.buffer8.ContextMenu = obj.handles.panels.datasets.handles.buffersContext;
obj.handles.panels.datasets.handles.buffer9.ContextMenu = obj.handles.panels.datasets.handles.buffersContext;
obj.handles.panels.datasets.handles.buffer10.ContextMenu = obj.handles.panels.datasets.handles.buffersContext;

% ---------------------- Add context menu for sets dropdown ----------------------
obj.handles.panels.datasets.handles.setsContext = uicontextmenu(obj.handles.panels.datasetsPanel.Figure);
obj.handles.panels.datasets.handles.setsContextAdd = uimenu(obj.handles.panels.datasets.handles.setsContext, ...
    'Text', 'Add set...', 'Tag', 'setsContextAdd',  ...
    'MenuSelectedFcn', @(src, event)obj.controller.datasetsSetsOps_Callbacks(src, event));
obj.handles.panels.datasets.handles.setsContextRename = uimenu(obj.handles.panels.datasets.handles.setsContext, ...
    'Text', 'Rename set...', 'Tag', 'setsContextRename', 'Separator', 'on', ...
    'MenuSelectedFcn', @(src, event)obj.controller.datasetsSetsOps_Callbacks(src, event));
obj.handles.panels.datasets.handles.setsContextRemove = uimenu(obj.handles.panels.datasets.handles.setsContext, ...
    'Text', 'Remove set...', 'Tag', 'setsContextRemove', 'Separator', 'on', ...
    'MenuSelectedFcn', @(src, event)obj.controller.datasetsSetsOps_Callbacks(src, event));

% Add context menu to the dropdown and the add set button
obj.handles.panels.datasets.handles.sets.ContextMenu = obj.handles.panels.datasets.handles.setsContext;
obj.handles.panels.datasets.handles.addSet.ContextMenu = obj.handles.panels.datasets.handles.setsContext;

% ---------------------- ADD CALLBACKS TO WIDGETS ----------------------
obj.handles.panels.datasets.handles.buffer1.ButtonPushedFcn = @(src, event)obj.controller.datasetsBuffers_Callback(src, event);
obj.handles.panels.datasets.handles.buffer2.ButtonPushedFcn = @(src, event)obj.controller.datasetsBuffers_Callback(src, event);
obj.handles.panels.datasets.handles.buffer3.ButtonPushedFcn = @(src, event)obj.controller.datasetsBuffers_Callback(src, event);
obj.handles.panels.datasets.handles.buffer4.ButtonPushedFcn = @(src, event)obj.controller.datasetsBuffers_Callback(src, event);
obj.handles.panels.datasets.handles.buffer5.ButtonPushedFcn = @(src, event)obj.controller.datasetsBuffers_Callback(src, event);
obj.handles.panels.datasets.handles.buffer6.ButtonPushedFcn = @(src, event)obj.controller.datasetsBuffers_Callback(src, event);
obj.handles.panels.datasets.handles.buffer7.ButtonPushedFcn = @(src, event)obj.controller.datasetsBuffers_Callback(src, event);
obj.handles.panels.datasets.handles.buffer8.ButtonPushedFcn = @(src, event)obj.controller.datasetsBuffers_Callback(src, event);
obj.handles.panels.datasets.handles.buffer9.ButtonPushedFcn = @(src, event)obj.controller.datasetsBuffers_Callback(src, event);
obj.handles.panels.datasets.handles.buffer10.ButtonPushedFcn = @(src, event)obj.controller.datasetsBuffers_Callback(src, event);
obj.handles.panels.datasets.handles.sets.ValueChangedFcn = @(src, event)obj.controller.datasetsSetsOps_Callbacks(src, event);
obj.handles.panels.datasets.handles.addSet.ButtonPushedFcn = @(src, event)obj.controller.datasetsSetsOps_Callbacks(src, event, 'setsContextAdd');
obj.handles.panels.datasets.handles.datasetType.ValueChangedFcn = @(src, event)obj.controller.datasetsType_Callbacks(src, event);


% add the panel to GUI
obj.gui.add(obj.handles.panels.datasetsPanel);

end