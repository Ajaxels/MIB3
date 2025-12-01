function globalTabGroup_SelectionCallback(obj, hWidget, hData)
% function globalTabGroup_SelectionCallback(obj, hWidget, hData)
% Callback for selection of a tab in the top ribbon of MIB
% used to apply lazy loading of the tabs upon the first selection

arguments (Input)
    obj controllers.MibController
    hWidget matlab.ui.internal.toolstrip.TabGroup
    hData matlab.ui.internal.toolstrip.base.ToolstripEventData
end

switch obj.view.handles.toolbar.global.SelectedTab.Title
    case 'Dataset'
        if isfield(obj.view.handles, 'dataset') % already initialized
            return;
        end
        obj.view.buildDatasetTab(); % lazily init the ribbon
    case 'Image'
        if isfield(obj.view.handles, 'image') % already initialized
            return;
        end
        obj.view.buildImageTab(); % lazily init the ribbon
    case 'Model'
        if isfield(obj.view.handles, 'model') % already initialized
            return;
        end
        obj.view.buildModelTab(); % lazily init the ribbon
    case 'Mask'
        if isfield(obj.view.handles, 'mask') % already initialized
            return;
        end
        obj.view.buildMaskTab(); % lazily init the ribbon
    case 'Selection'
        if isfield(obj.view.handles, 'selection') % already initialized
            return;
        end
        obj.view.buildSelectionTab(); % lazily init the ribbon
    case 'Tools'
        if isfield(obj.view.handles, 'tools') % already initialized
            return;
        end
        obj.view.buildToolsTab(); % lazily init the ribbon
    case 'Plugins'
        if isfield(obj.view.handles, 'plugins') % already initialized
            return;
        end
        obj.view.buildPluginsTab(); % lazily init the ribbon
end

fprintf('MibController.globalTabGroup_SelectionCallback: selection of a ribbon\n');