function ribbonHandles = addRibbonTabs(obj)
% function ribbonHandles = addRibbonTabs(obj)
% Add the global ribbon, which is matlab.ui.internal.toolstrip.TabGroup()
% stored in 
% - obj.handles.ribbon.*
% - obj.handles.ribbon.global

arguments (Input)
    obj views.MibView
end

% create the global tab group
obj.handles.ribbon.global = matlab.ui.internal.toolstrip.TabGroup();
obj.handles.ribbon.global.Tag = 'ribbonGlobal';

% add tabs to the global tab group
lazyInit = true;                    % init the panel lazily only upon the first time show
obj.buildHomeTab();                 % obj.handles.ribbon.home
obj.buildDatasetTab(lazyInit);      % obj.handles.ribbon.dataset
obj.buildImageTab(lazyInit);        % obj.handles.ribbon.image
obj.buildModelTab(lazyInit);        % obj.handles.ribbon.model
obj.buildMaskTab(lazyInit);         % obj.handles.ribbon.mask
obj.buildSelectionTab(lazyInit);    % obj.handles.ribbon.selection
obj.buildToolsTab(lazyInit);        % obj.handles.ribbon.tools
obj.buildPluginsTab(lazyInit);      % obj.handles.ribbon.plugins

% focus on the selected tab
obj.handles.ribbon.global.SelectedTab = obj.handles.ribbon.home;

% add the global tab group to MIB
obj.gui.add(obj.handles.ribbon.global);

ribbonHandles = obj.handles.ribbon;
end