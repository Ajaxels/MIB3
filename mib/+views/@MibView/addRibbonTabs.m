function [ribbonHandles, ribbonWidgets] = addRibbonTabs(obj)
% function [ribbonHandles, ribbonWidgets] = addRibbonTabs(obj)
% Add the global ribbon, which is matlab.ui.internal.toolstrip.TabGroup()
% stored in 
% - ribbonHandles.*
% - ribbonHandles.global

arguments (Input)
    obj views.MibView
end

% create the global tab group
obj.handles.ribbon.global = matlab.ui.internal.toolstrip.TabGroup();
obj.handles.ribbon.global.Tag = 'ribbonGlobal';

% add tabs to the global tab group
lazyInit = true;                    % init the panel lazily only upon the first time show
ribbonWidgets.ribbonHome = obj.addRibbonHome();                 % obj.handles.ribbonHome
ribbonWidgets.ribbonDataset = obj.addRibbonDataset(lazyInit);      % obj.handles.ribbonDataset
ribbonWidgets.ribbonImage = obj.addRibbonImage(lazyInit);        % obj.handles.ribbonImage
ribbonWidgets.ribbonModel = obj.addRibbonModel(lazyInit);        % obj.handles.ribbonModel
%obj.buildMaskTab(lazyInit);         % ribbonHandles.mask
%obj.buildSelectionTab(lazyInit);    % ribbonHandles.selection
%obj.buildToolsTab(lazyInit);        % ribbonHandles.tools
%obj.buildPluginsTab(lazyInit);      % ribbonHandles.plugins

% focus on the selected tab
obj.handles.ribbon.global.SelectedTab = obj.handles.ribbon.home;

ribbonHandles = obj.handles.ribbon;

% add the global tab group to MIB
obj.gui.add(obj.handles.ribbon.global);
end