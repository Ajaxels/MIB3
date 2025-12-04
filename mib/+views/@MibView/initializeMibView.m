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

obj.gui = matlab.ui.container.internal.AppContainer(appOptions); 

% s = settings;
% s.matlab.appearance.MATLABTheme.TemporaryValue = 'Light'; % or, 'Dark', 'Light'

obj.gui.EnableTheming = true;

% add MIB icon
obj.gui.Icon = fullfile(obj.controller.mibPath, 'assets/icons/mib_icon_32px.png');

% expand the status bar to the whole width of MIB
obj.gui.StatusBarSpansFullWidth = true;

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

% ------------ add callbacks ------------
obj.gui.CanCloseFcn =  @(target)obj.controller.exitProgram(target);

% ------------ place MIB in the screen center ------------
obj.gui.WindowBounds = [100  100 1400 980];  % default: 100 540 1200 800
obj.recenterGui();

end