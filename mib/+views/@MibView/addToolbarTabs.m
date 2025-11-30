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
lazyInit = true;            % init the panel lazily only upon the first time show
obj.buildHomeTab();         % obj.handles.toolbar.home
obj.buildDatasetTab(lazyInit);  % obj.handles.toolbar.dataset
obj.buildImageTab(lazyInit);        % obj.handles.toolbar.image
obj.buildModelTab(lazyInit);        % obj.handles.toolbar.model
obj.buildMaskTab(lazyInit);         % obj.handles.toolbar.mask
obj.buildSelectionTab(lazyInit);    % obj.handles.toolbar.selection
obj.buildToolsTab(lazyInit);        % obj.handles.toolbar.tools
obj.buildPluginsTab(lazyInit);      % obj.handles.toolbar.plugins

% focus on the selected tab
obj.handles.toolbar.global.SelectedTab = obj.handles.toolbar.home;

% add the global tab group to MIB
obj.gui.add(obj.handles.toolbar.global);
end