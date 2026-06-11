function doPostInitializationTasks(obj)
% DOPOSTINITIALIZATIONTASKS - perform post-initialization tasks after the main GUI window is visible.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.doPostInitializationTasks()
%

arguments (Input)
    obj views.MibView
end

drawnow nocallbacks;

% restore the default layout; wait until the AppContainer reaches the RUNNING
% state so that PanelLayout can be applied (bounded poll instead of a fixed pause)
layoutWaitTimer = tic;
while obj.gui.State ~= matlab.ui.container.internal.appcontainer.AppState.RUNNING ...
        && toc(layoutWaitTimer) < 5
    pause(0.05);
end
status = obj.controller.loadLayout('localDefault');
drawnow nocallbacks;

% update all widgets of the Datasets panel
for i=1:obj.mibModel.Sets.datasetsInSet
    Options.mode = 'resize';
    Options.index = i;
    eventdata = core.ToggleEventData(Options);
    notify(obj.mibModel, 'UpdateDatasetAxes', eventdata);
end

obj.handles.panels.selectionPanel.Selected = true;

% update GUI elements
%obj.handles.status.zoom.Value = sprintf('%3d %%', 1/obj.controller.mibModel.I{obj.controller.mibModel.id}.magFactor*100);
segmHandles = obj.handles.panels.segmentation.handles;
segmHandles.addMaterial.Icon = core.MibIconCache.get('alpha_cache', 'plus_16px');
segmHandles.addMaterial.Tooltip = 'Add a new material to the model';
segmHandles.removeMaterial.Icon = core.MibIconCache.get('alpha_cache', 'minus_16px');
segmHandles.removeMaterial.Tooltip = 'Remove selected material from the model';

% ------------ add file drag-and-drop functionality callbacks -----------
% requires GUI to be visible, otherwise the window is not grabbed correctly
% check addition of drag and drop for files
webWindowsList = matlab.internal.webwindowmanager.instance.windowList;
for i = numel(webWindowsList):-1:1
    % the last webWindow should be one needed, but lets still check
    if isempty(webWindowsList(i).Title) || numel(webWindowsList(i).Title) < 24; continue; end
    if strcmp(webWindowsList(i).Title(1:8), 'MIB ver.')
        obj.controller.mibWebWindow = webWindowsList(i);
        obj.controller.dndBridgeButton = utils.attachFileDnD( ...
            obj.controller.mibWebWindow, ...
            obj.handles.panels.selectionPanel.Figure, ...
            @(params) obj.controller.dragNdrop_Callback(params));
        fprintf('Drag-and-drop filenames: Enabled\n');
        break;
    end
end

end
