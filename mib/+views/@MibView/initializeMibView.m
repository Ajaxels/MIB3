function initializeMibView(obj)
% INITIALIZEMIBVIEW - initialize the main MIB view and its components.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.initializeMibView()
%

arguments (Input)
    obj views.MibView
end

% Construct the app
appOptions.Tag = "mibView";
% generate the title
titleString = sprintf('MIB %s', obj.controller.mibVersion);
if isdeployed; titleString = sprintf('%s deployed version', titleString); end
titleString = [titleString '    level ' obj.mibModel.preferences.Users.tierLevelRanks{min(obj.mibModel.preferences.Users.Tiers.tierLevel, numel(obj.mibModel.preferences.Users.tierLevelRanks))}];
appOptions.Title =  titleString;

% apply the theme chosen in Home ribbon -> Theme before the window is built;
% 'System' leaves the MATLAB theme as it is
if ~strcmp(obj.mibModel.preferences.Colors.Theme, 'System')
    utils.setMibTheme(obj.mibModel.preferences.Colors.Theme);
end

obj.gui = matlab.ui.container.internal.AppContainer(appOptions);

obj.gui.EnableTheming = true;

% add MIB and other icons
obj.gui.Icon = fullfile(obj.controller.mibPath, 'assets/icons/mib_icon_32px.png');

% expand the status bar to the whole width of MIB
obj.gui.StatusBarSpansFullWidth = true;

% ------------ add FigureDocumentGroup ------------
% alternative to add DocumentGroup(groupOptions);
% documentGroup = matlab.ui.container.internal.appcontainer.DocumentGroup(groupOptions);
% selection of the figure-document is listened by MibController.listener_appStateChanged
obj.handles.imageViewDocGroup = matlab.ui.internal.FigureDocumentGroup();
obj.handles.imageViewDocGroup.Tag = 'imageViewDocGroup';
obj.handles.imageViewDocGroup.EnableDockControls = true;
obj.handles.imageViewDocGroup.Title = 'ImageView Figures';
obj.gui.add(obj.handles.imageViewDocGroup);

% init default variables
obj.handles.figureDocs = {}; % cell array of handles for added matlab.ui.internal.FigureDocument

% generate obj.brushSizeNumbers dictionary for efficient loading of cursor
% with the brush size value
numbersImg = 1 - imread(fullfile(obj.mibModel.mibPath, 'assets', 'misc', 'numbers.png'));
charTable = '1234567890.-';
charWidth = 8;
charHeight = 16;
% Create dictionary for O(1) lookup
obj.brushSizeNumbers = dictionary();
for i = 1:numel(charTable)
    char_key = charTable(i);
    col_start = (i-1) * charWidth + 1;
    col_end = col_start + charWidth - 1;

    % Extract and store 16x8 character array
    obj.brushSizeNumbers{char_key} = numbersImg(1:charHeight, col_start:col_end);
end

% ------------ add callbacks ------------
obj.gui.CanCloseFcn =  @(target)obj.controller.exitProgram(target);

% ------------ place MIB in the screen center ------------
obj.gui.WindowBounds = [100  100 1400 980];  % default: 100 540 1200 800
obj.recenterGui();

end
