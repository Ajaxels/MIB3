function initializeMibView(obj)
% function initializeMibView(obj)
% Initialize the main MIB view

arguments (Input)
    obj views.MibView
end

% Construct the app
appOptions.Tag = "mibView";
% generate the title
appOptions.Title = sprintf('MIB %s', obj.controller.mibVersion);
if isdeployed; appOptions.Title = sprintf('%s deployed version', appOptions.Title); end

obj.gui = matlab.ui.container.internal.AppContainer(appOptions); % Uncomment for release version of code, point browser to http://localhost:<app.DebugPort> to view JavaScript Debugger

% If the value is "true" the app will participate with the desktop theming
% i.e. if the desktop is in dark theme, then the app will also be in dark theme.
% If the value is "false" the app will not participate with the desktop theming
% i.e. if the desktop is in dark theme, the app will continue to be in default light theme.
% This property cannot be changed after the app has been been constructed.

% s = settings;
% s.matlab.appearance.MATLABTheme.TemporaryValue = 'Light'; % or, 'Dark', 'Light'

obj.gui.EnableTheming = true;

% add MIB icon
obj.gui.Icon = fullfile(obj.controller.mibPath, 'assets/icons/mib_icon_32px.png');

% expand the status bar to the whole width of MIB
obj.gui.StatusBarSpansFullWidth = true;

% ------------ add Widgets ------------
obj.addToolbarTabs();  % add toolbars to MIB, stored as obj.handles.toolbar
obj.addQuickAccessBar(); % add quick access buttons

% add panels
obj.addDatasetsPanel(); % add the Datasets panel
obj.addDirContentsPanel(); % add the DirContents panel
% obj.addSegmentationPanel(); % add the Segmentation panel
% roiHandles = obj.addSelectionViewSettingsPanel(); % add the Segmentation panel
% roiHandles = obj.addRoiPanel(); % add the ROI panel

obj.addStatusBar()  % add status bar to MIB, stored as obj.handles.status

% ------------ add FigureDocumentGroup ------------
% alternative to add DocumentGroup(groupOptions);
% documentGroup = matlab.ui.container.internal.appcontainer.DocumentGroup(groupOptions);
% selection of the figure-document is listened by MibController.listenerAppStateChanged
obj.handles.imageViewDocGroup = matlab.ui.internal.FigureDocumentGroup();
obj.handles.imageViewDocGroup.Tag = 'imageViewDocGroup';
obj.handles.imageViewDocGroup.EnableDockControls = true;
obj.handles.imageViewDocGroup.Title = 'ImageView Figures';
obj.gui.add(obj.handles.imageViewDocGroup);

% init default variables
obj.handles.figureDocs = {}; % cell array of handles for added matlab.ui.internal.FigureDocument
obj.handles.imView = {}; % cell array of handles for the component of FigureDocument

% % Add the first figure-based document for default set
% figOptions.Title = "Image view / Set 1";
% figOptions.DocumentGroupTag = obj.handles.imageViewDocGroup.Tag;
% obj.handles.figureDocs{1} = matlab.ui.internal.FigureDocument(figOptions);
% obj.handles.figureDocs{1}.EnableDockControls = true;
% obj.handles.figureDocs{1}.Closable = false;
% % obj.handles.figureDocs{1}.CanCloseFcn
% 
% obj.handles.figureDocs{1}.Figure.AutoResizeChildren = 'off';
% obj.handles.imView{1} = views.components.ImageView('Parent', obj.handles.figureDocs{1}.Figure, ...
%      'Units', 'normalized', 'Position', [0 0 1 1]);
% 
% obj.gui.add(obj.handles.figureDocs{1});

% ------------ add callbacks ------------
obj.gui.CanCloseFcn =  @(target)obj.controller.exitProgram(target);

% ------------ place MIB in the screen center ------------
obj.gui.WindowBounds = [100  100 1400 980];  % default: 100 540 1200 800
obj.recenterGui();

end