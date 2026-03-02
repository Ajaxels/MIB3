function doPostInitializationTasks(obj)
% function doPostInitializationTasks(obj)
%   Do some post-initialization tasks that require that the main GUI window is visible
%   such as
%   - selecting an active panel
%   - adding dropdowns to the QABs

arguments (Input)
    obj views.MibView
end

drawnow nocallbacks;

% restore the default layout
pause(2);
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

% ------------ add file drag-and-drop functionality callbacks -----------
% requires GUI to be visible, otherwise the window is not grabbed correctly
% check addition of drag and drop for files
webWindowsList = matlab.internal.webwindowmanager.instance.windowList;
for i = numel(webWindowsList):-1:1
    % the last webWindow should be one needed, but lets still check
    if isempty(webWindowsList(i).Title) || numel(webWindowsList(i).Title) < 24; continue; end
    if strcmp(webWindowsList(i).Title(1:8), 'MIB ver.')
        obj.controller.mibWebWindow = webWindowsList(i);
        obj.controller.mibWebWindow.enableDragAndDropAll;
        % add drag-and-drop filename callback
        obj.controller.mibWebWindow.FileDragDropCallback = @(varargin)obj.controller.dragNdrop_Callback(varargin);
        %fprintf('Drag-and-drop filenames Enabled for %s\n', obj.controller.mibWebWindow.Title);
        fprintf('Drag-and-drop filenames: Enabled\n');
        break;
    end
end

end