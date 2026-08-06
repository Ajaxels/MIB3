function widgetHandles = addRibbonPlugins(obj, lazyInit)
% ADDRIBBONPLUGINS - build the Plugins tab group and add it to the global ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%      widgetHandles = obj.addRibbonPlugins()
%      widgetHandles = obj.addRibbonPlugins(lazyInit)
%
% Input Arguments:
%   - **lazyInit** *(optional)* - [logical] when ``true``, only a placeholder is
%     initialized; full rendering occurs on first tab activation via
%     ``MibController.globalTabGroup_SelectionCallback`` (default: ``false``)
%
% Output Arguments:
%   - **widgetHandles** - [struct] handles to the Plugins ribbon section widgets
%

arguments (Input)
    obj views.MibView
    lazyInit logical = false
end

%% Lazy initialization
if lazyInit
    % lazy initialization, the real initialization is in controllers.MibController.globalTabGroup_SelectionCallback
    % Make the tab
    obj.handles.ribbon.plugins = matlab.ui.internal.toolstrip.Tab("Plugins");
    obj.handles.ribbon.plugins.Tag = 'toolbarPlugins';

    % Add tab to the tab group
    obj.handles.ribbon.global.add(obj.handles.ribbon.plugins);
    widgetHandles = [];
    return
end

% get list of plugins groups
pluginSections = dir(fullfile(obj.controller.mibPath, 'plugins'));
isDir = [pluginSections.isdir];
names = {pluginSections.name};
pluginSections = names(isDir & ~ismember(names, {'.', '..'}));

%% ============= Make "Plugins" section =============
section = obj.handles.ribbon.plugins.addSection("Plugins");
column = section.addColumn();

% add popup for the plugins gallery
popup = matlab.ui.internal.toolstrip.GalleryPopup('GalleryItemRowCount', 1);

for sectionId = 1:numel(pluginSections)
    % get list of plugins in the category
    pluginList = dir(fullfile(obj.controller.mibPath, 'plugins', pluginSections{sectionId}));
    isDir = [pluginList.isdir];
    names = {pluginList.name};
    pluginList = names(isDir & ~ismember(names, {'.', '..'}));

    % split on lowercase→uppercase boundary (preserves acronyms like MC, GUI)
    categoryName = regexprep(pluginSections{sectionId}, '([a-z])([A-Z])', '$1 $2');
    categoryName = strtrim(categoryName);
    % Create the gallery categories
    category = matlab.ui.internal.toolstrip.GalleryCategory(categoryName);

    for pluginId = 1:numel(pluginList)
        pluginDir = fullfile(obj.controller.mibPath, 'plugins', pluginSections{sectionId}, pluginList{pluginId});
        if ~isdeployed; addpath(pluginDir); end

        iconFileName = fullfile(pluginDir, 'icon_24px.png');
        if ~isfile(iconFileName)
            iconFileName = fullfile(obj.controller.mibPath, 'assets', 'icons', 'mib_icon_24px.png');
        end
        icon = matlab.ui.internal.toolstrip.Icon(iconFileName);
        pluginClassName = pluginList{pluginId};
        % split on lowercase→uppercase boundary (preserves acronyms like MC, GUI)
        pluginName = regexprep(pluginClassName, '([a-z])([A-Z])', '$1 $2');
        pluginName = strtrim(pluginName);

        item = matlab.ui.internal.toolstrip.GalleryItem(pluginName, icon);
        %item.Description = 'Trypanosoma brucei cell and a model of nuclei, endoplasmic reticulum, mitochondria, vesicles, lipid droplets, and cytoplasm';
        item.ItemPushedFcn = @(varargin) obj.controller.startController(pluginClassName);
        category.add(item);
    end
    popup.add(category);
end

% Create the main gallery and add it to the view column.
obj.handles.ribbonPlugins.gallery = matlab.ui.internal.toolstrip.Gallery(popup, 'MinColumnCount', 3, 'MaxColumnCount', 20);
column.add( obj.handles.ribbonPlugins.gallery )

widgetHandles = obj.handles.ribbonPlugins;

end
