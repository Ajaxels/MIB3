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
% add handle tags to the Home ribbon,
% other handles are overridden in MibController.globalTabGroup_SelectionCallback
if obj.mibModel.preferences.System.DeveloperMode
    utils.overrideDescriptions(ribbonWidgets.ribbonHome, true, 'obj.cRibbon.handles.ribbonHome');
end

ribbonWidgets.ribbonDataset = obj.addRibbonDataset(lazyInit);      % obj.handles.ribbonDataset
ribbonWidgets.ribbonImage = obj.addRibbonImage(lazyInit);        % obj.handles.ribbonImage
ribbonWidgets.ribbonModel = obj.addRibbonModel(lazyInit);        % obj.handles.ribbonModel
ribbonWidgets.ribbonMask = obj.addRibbonMask(lazyInit);         % obj.handles.ribbonMask
ribbonWidgets.ribbonSelection = obj.addRibbonSelection(lazyInit);         % obj.handles.ribbonSelection
ribbonWidgets.ribbonTools = obj.addRibbonTools(lazyInit);         % obj.handles.ribbonTools
ribbonWidgets.ribbonPlugins = obj.addRibbonPlugins(lazyInit);         % obj.handles.ribbonPlugins

% focus on the selected tab
obj.handles.ribbon.global.SelectedTab = obj.handles.ribbon.home;

ribbonHandles = obj.handles.ribbon;

% add the global tab group to MIB
obj.gui.add(obj.handles.ribbon.global);
end