function buildPluginsTab(obj, lazyInit)
% function buildPluginsTab(obj, lazyInit)
% build the Plugins tab group (obj.handles.toolbar.plugins)
% and add it to obj.handles.toolbar.global 
%
% Parameters:
% lazyInit: [@em optional default=false] logical, when true do only
% place maker initialization of the panel. The full rendering is upon the
% first call, using
% "controllers.MibController.globalTabGroup_SelectionCallback" function

arguments (Input)
    obj views.MibView
    lazyInit logical = false
end

%% Lazy initialization
if lazyInit
    % lazy initialization, the real initialization is in controllers.MibController.globalTabGroup_SelectionCallback
    % Make the tab
    obj.handles.toolbar.plugins = matlab.ui.internal.toolstrip.Tab("Plugins");
    obj.handles.toolbar.plugins.Tag = 'toolbarPlugins';

    % Add tab to the tab group
    obj.handles.toolbar.global.add(obj.handles.toolbar.plugins);
    return
end

% get list of plugins groups
pluginSections = dir(fullfile(obj.controller.mibPath, 'plugins'));
isDir = [pluginSections.isdir];
names = {pluginSections.name};
pluginSections = names(isDir & ~ismember(names, {'.', '..'}));

%% ============= Make "Plugins" section =============
section = obj.handles.toolbar.plugins.addSection("Plugins");
column = section.addColumn();

% add popup for the plugins gallery
popup = matlab.ui.internal.toolstrip.GalleryPopup('GalleryItemRowCount', 1);

for sectionId = 1:numel(pluginSections)
    % get list of plugins in the category
    pluginList = dir(fullfile(obj.controller.mibPath, 'plugins', pluginSections{sectionId}));
    isDir = [pluginList.isdir];
    names = {pluginList.name};
    pluginList = names(isDir & ~ismember(names, {'.', '..'}));

    % add space before capital letter
    categoryName = regexprep(pluginSections{sectionId}, '([A-Z])', ' $1');
    categoryName = strtrim(categoryName); % Remove possible leading space
    % Create the gallery categories
    category = matlab.ui.internal.toolstrip.GalleryCategory(categoryName);

    for pluginId = 1:numel(pluginList)
        iconFileName = fullfile(fullfile(obj.controller.mibPath, 'plugins', pluginSections{sectionId}, pluginList{pluginId}, 'icon_24px.png' ));
        if isfile(iconFileName)
            icon = matlab.ui.internal.toolstrip.Icon(iconFileName);
        else
            icon = matlab.ui.internal.toolstrip.Icon.PLAY_24;
        end
        % add space before capital letter
        pluginName = regexprep(pluginList{pluginId}, '([A-Z])', ' $1');
        pluginName = strtrim(pluginName); % Remove possible leading space

        item = matlab.ui.internal.toolstrip.GalleryItem(pluginName, icon);
        %item.Description = 'Trypanosoma brucei cell and a model of nuclei, endoplasmic reticulum, mitochondria, vesicles, lipid droplets, and cytoplasm';
        item.ItemPushedFcn = @(varargin)(fprintf('Plugin: "%s" pressed\n', item.Text));
        category.add(item);
    end
    popup.add(category);
end

% Create the main gallery and add it to the view column.
obj.handles.plugins.gallery = matlab.ui.internal.toolstrip.Gallery(popup, 'MinColumnCount', 3, 'MaxColumnCount', 5 );
column.add( obj.handles.plugins.gallery )


end