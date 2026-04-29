function globalTabGroup_SelectionCallback(obj, hWidget)
% GLOBALTABGROUP_SELECTIONCALLBACK - Callback for selection of a tab in the top ribbon of MIB.
%
% Syntax:
%   function globalTabGroup_SelectionCallback(obj, hWidget)
%
% used to apply lazy loading of the tabs upon the first selection
%
% used as a callback upon selection of tabs in the ribbon:
% obj.view.handles.ribbon.global.SelectedTabChangedFcn = @(~, ~)obj.globalTabGroup_SelectionCallback;
%
% Input Arguments:
%   - **hWidget** — [char] indicating the handle of the tab, e.g. 'Dataset',
%     'Image', 'Model', matching the tab title: obj.view.handles.ribbon.global.SelectedTab.Title
%
% Usage:
%   <code>
%   // call from MibController to check/init the Image tab in the ribbon
%   obj.globalTabGroup_SelectionCallback('Image');
%   <endcode>
%

showDevInfo = false;
if nargin < 2
    hWidget = obj.view.handles.ribbon.global.SelectedTab.Title; 
    showDevInfo = true; % show DeveloperMode info at the end of the function
end

switch hWidget
    case 'Dataset'
        if isfield(obj.view.handles, 'ribbonDataset') % already initialized
            return;
        end
        obj.cRibbon.handles.ribbonDataset = obj.view.addRibbonDataset(); % lazily init the ribbon
        obj.cRibbon.addCallbacksToDatasetRibbon();
        if obj.mibModel.preferences.System.DeveloperMode
            utils.overrideDescriptions(obj.cRibbon.handles.ribbonDataset, true, 'obj.cRibbon.handles.ribbonDataset');
        end
    case 'Image'
        if isfield(obj.view.handles, 'ribbonImage') % already initialized
            return;
        end
        obj.cRibbon.handles.ribbonImage = obj.view.addRibbonImage(); % lazily init the ribbon
        obj.cRibbon.addCallbacksToDatasetImage();
        if obj.mibModel.preferences.System.DeveloperMode
            utils.overrideDescriptions(obj.cRibbon.handles.ribbonImage, true, 'obj.cRibbon.handles.ribbonImage');
        end
    case 'Model'
        if isfield(obj.view.handles, 'ribbonModel') % already initialized
            return;
        end
        obj.cRibbon.handles.ribbonModel = obj.view.addRibbonModel(); % lazily init the ribbon
        obj.cRibbon.addCallbacksToDatasetModel();
        if obj.mibModel.preferences.System.DeveloperMode
            utils.overrideDescriptions(obj.cRibbon.handles.ribbonModel, true, 'obj.cRibbon.handles.ribbonModel');
        end
    case 'Mask'
        if isfield(obj.view.handles, 'ribbonMask') % already initialized
            return;
        end
        obj.cRibbon.handles.ribbonMask = obj.view.addRibbonMask(); % lazily init the ribbon
        obj.cRibbon.addCallbacksToDatasetMask();
        if obj.mibModel.preferences.System.DeveloperMode
            utils.overrideDescriptions(obj.cRibbon.handles.ribbonMask, true, 'obj.cRibbon.handles.ribbonMask');
        end
    case 'Selection'
        if isfield(obj.view.handles, 'ribbonSelection') % already initialized
            return;
        end
        obj.cRibbon.handles.ribbonSelection = obj.view.addRibbonSelection(); % lazily init the ribbon
        obj.cRibbon.addCallbacksToDatasetSelection();
        if obj.mibModel.preferences.System.DeveloperMode
            utils.overrideDescriptions(obj.cRibbon.handles.ribbonSelection, true, 'obj.cRibbon.handles.ribbonSelection');
        end
    case 'Tools'
        if isfield(obj.view.handles, 'ribbonTools') % already initialized
            return;
        end
        obj.cRibbon.handles.ribbonTools = obj.view.addRibbonTools(); % lazily init the ribbon
        obj.cRibbon.addCallbacksToDatasetTools();
        if obj.mibModel.preferences.System.DeveloperMode
            utils.overrideDescriptions(obj.cRibbon.handles.ribbonTools, true, 'obj.cRibbon.handles.ribbonTools');
        end
    case 'Plugins'
        if isfield(obj.view.handles, 'ribbonPlugins') % already initialized
            return;
        end
        obj.cRibbon.handles.ribbonPlugins = obj.view.addRibbonPlugins(); % lazily init the ribbon
        %obj.cRibbon.addCallbacksToDatasetPlugins();
end

if showDevInfo && obj.mibModel.preferences.System.DeveloperMode
    fprintf('MibController.globalTabGroup_SelectionCallback: selection of a ribbon\n');
end
end
