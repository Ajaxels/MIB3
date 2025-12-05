function globalTabGroup_SelectionCallback(obj, hWidget, hData)
% function globalTabGroup_SelectionCallback(obj, hWidget, hData)
% Callback for selection of a tab in the top ribbon of MIB
% used to apply lazy loading of the tabs upon the first selection

arguments (Input)
    obj controllers.MibController
    hWidget matlab.ui.internal.toolstrip.TabGroup
    hData matlab.ui.internal.toolstrip.base.ToolstripEventData
end

switch obj.view.handles.ribbon.global.SelectedTab.Title
    case 'Dataset'
        if isfield(obj.view.handles, 'ribbonDataset') % already initialized
            return;
        end
        obj.cRibbon.handles.ribbonDataset = obj.view.addRibbonDataset(); % lazily init the ribbon
        obj.cRibbon.addCallbacksToDatasetRibbon();
    case 'Image'
        if isfield(obj.view.handles, 'ribbonImage') % already initialized
            return;
        end
        obj.cRibbon.handles.ribbonImage = obj.view.addRibbonImage(); % lazily init the ribbon
        obj.cRibbon.addCallbacksToDatasetImage();
    case 'Model'
        if isfield(obj.view.handles, 'ribbonModel') % already initialized
            return;
        end
        obj.cRibbon.handles.ribbonModel = obj.view.addRibbonModel(); % lazily init the ribbon
        obj.cRibbon.addCallbacksToDatasetModel();
    case 'Mask'
        if isfield(obj.view.handles, 'ribbonMask') % already initialized
            return;
        end
        obj.cRibbon.handles.ribbonMask = obj.view.addRibbonMask(); % lazily init the ribbon
        obj.cRibbon.addCallbacksToDatasetMask();
    case 'Selection'
        if isfield(obj.view.handles, 'ribbonSelection') % already initialized
            return;
        end
        obj.cRibbon.handles.ribbonSelection = obj.view.addRibbonSelection(); % lazily init the ribbon
        obj.cRibbon.addCallbacksToDatasetSelection();
    case 'Tools'
        if isfield(obj.view.handles, 'ribbonTools') % already initialized
            return;
        end
        obj.cRibbon.handles.ribbonTools = obj.view.addRibbonTools(); % lazily init the ribbon
        obj.cRibbon.addCallbacksToDatasetTools();
    case 'Plugins'
        if isfield(obj.view.handles, 'ribbonPlugins') % already initialized
            return;
        end
        obj.cRibbon.handles.ribbonPlugins = obj.view.addRibbonPlugins(); % lazily init the ribbon
        %obj.cRibbon.addCallbacksToDatasetPlugins();
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('MibController.globalTabGroup_SelectionCallback: selection of a ribbon\n');
end
end