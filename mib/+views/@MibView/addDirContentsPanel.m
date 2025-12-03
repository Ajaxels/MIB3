function panelHandles = addDirContentsPanel(obj)
% function panelHandles = addDirContentsPanel(obj)
% add the DirContents panel, add context menus and callbacks for widgets
% The callbacks are added in the controller of the panel:
% controllers.MibDirContents during its creation in
% MibController.initialize() -> MibController.addGuiControllers()

arguments (Input)
    obj views.MibView
end

%% ---------------------- DIRECTORY CONTENTS PANEL ----------------------
panelOptions.Title = "Directory contents";
panelOptions.Region = "left";
obj.handles.panels.dirContentsPanel = matlab.ui.internal.FigurePanel(panelOptions);
obj.handles.panels.dirContentsPanel.PreferredHeight = 220;
obj.handles.panels.dirContentsPanel.Figure.AutoResizeChildren = 'off';
panelHandles = views.components.DirectoryContents('Parent', obj.handles.panels.dirContentsPanel.Figure, ...
    'Units', 'normalized', 'Position', [0 0 1 1]); % needs to have normalized units, by default those are pixels

% add handle tags to tooltips
if obj.mibModel.preferences.System.DeveloperMode; utils.overrideDescriptions(panelHandles.handles, true, 'panelHandles.handles'); end

% ---------------------- ADD CONTEXT MENUs ----------------------
% ---------------------- Add context menu for fileList ----------------------
panelHandles.handles.fileListContext = uicontextmenu(obj.handles.panels.dirContentsPanel.Figure);
panelHandles.handles.fileListContextCombine = uimenu(panelHandles.handles.fileListContext, ...
    'Text', 'Combine selected datasets', 'Tag', 'fileListContextCombine');
panelHandles.handles.fileListContextLoadPart = uimenu(panelHandles.handles.fileListContext, ...
    'Text', 'Load part of dataset (AM, TIF, BioFormats)...', 'Tag', 'fileListContextLoadPart');
panelHandles.handles.fileListContextLoadNth = uimenu(panelHandles.handles.fileListContext, ...
    'Text', 'Load each N-th file...', 'Tag', 'fileListContextLoadNth');
panelHandles.handles.fileListContextInsert = uimenu(panelHandles.handles.fileListContext, ...
    'Text', 'Insert into open dataset...', 'Tag', 'fileListContextInsert');
% ----
panelHandles.handles.fileListContextColorCombine = uimenu(panelHandles.handles.fileListContext, ...
    'Text', 'Combine files as color channels...', 'Tag', 'fileListContextColorCombine', 'Separator', 'on');
panelHandles.handles.fileListContextColorAdd = uimenu(panelHandles.handles.fileListContext, ...
    'Text', 'Add as a new color channel...', 'Tag', 'fileListContextColorAdd');
panelHandles.handles.fileListContextColorAddNth = uimenu(panelHandles.handles.fileListContext, ...
    'Text', 'Add each N-th file as a new color channel...', 'Tag', 'fileListContextColorAddNth');
% ----
panelHandles.handles.fileListContextRename = uimenu(panelHandles.handles.fileListContext, ...
    'Text', 'Rename selected file...', 'Tag', 'fileListContextRename', 'Separator', 'on');
panelHandles.handles.fileListContextDelete = uimenu(panelHandles.handles.fileListContext, ...
    'Text', 'Delete selected files...', 'Tag', 'fileListContextDelete');
% ----
panelHandles.handles.fileListContextProps = uimenu(panelHandles.handles.fileListContext, ...
    'Text', 'File properties', 'Tag', 'fileListContextProps', 'Separator', 'on');
% Add the context menu to fileList
panelHandles.handles.fileList.ContextMenu = panelHandles.handles.fileListContext;

% ---------------------- Add context menu for fileFilters ----------------------
panelHandles.handles.fileFiltersContext = uicontextmenu(obj.handles.panels.dirContentsPanel.Figure);
panelHandles.handles.fileFiltersContextRegister = uimenu(panelHandles.handles.fileFiltersContext, ...
    'Text', 'Register extension', 'Tag', 'fileFiltersContextRegister');
panelHandles.handles.fileFiltersContextUnregister = uimenu(panelHandles.handles.fileFiltersContext, ...
    'Text', 'Register extension', 'Tag', 'fileFiltersContextUnregister');
% Add the context menu to fileFilters
panelHandles.handles.fileFilters.ContextMenu = panelHandles.handles.fileFiltersContext;

% ---------------------- Update default UserData for widgets ----------------------
panelHandles.handles.fileFilters.UserData = 'all known';

obj.handles.panels.dirContents = panelHandles;

% add the panel to the gui
obj.gui.add(obj.handles.panels.dirContentsPanel);


end