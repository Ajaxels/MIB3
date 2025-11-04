function addToolbarTabs(obj)
% function addToolbarTabs(obj)
% Add the global toolbar, which is matlab.ui.internal.toolstrip.TabGroup()
% stored in 
% - obj.handles.toolbar.*
% - obj.handles.toolbar.global

arguments (Input)
    obj views.MibView
end

% create the global tab group
obj.handles.toolbar.global = matlab.ui.internal.toolstrip.TabGroup();
obj.handles.toolbar.global.Tag = 'toolbarGlobal';

% add tabs to the global tab group
obj.buildHomeTab();         % obj.handles.toolbar.home
obj.buildDatasetTab();      % obj.handles.toolbar.dataset
obj.buildImageTab();        % obj.handles.toolbar.image
obj.buildModelTab();        % obj.handles.toolbar.model
obj.buildMaskTab();         % obj.handles.toolbar.mask
obj.buildSelectionTab();    % obj.handles.toolbar.selection
obj.buildToolsTab();        % obj.handles.toolbar.tools
obj.buildPluginsTab();      % obj.handles.toolbar.plugins

% focus on the selected tab
obj.handles.toolbar.global.SelectedTab = obj.handles.toolbar.home;

% add the global tab group to MIB
obj.gui.add(obj.handles.toolbar.global);
end