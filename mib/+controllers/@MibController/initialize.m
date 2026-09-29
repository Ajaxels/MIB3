function initialize(obj)
% INITIALIZE - Initialize the main MibController class.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.initialize()
%
% Output Arguments:
%   (none)
%

arguments (Input)
    obj controllers.MibController
end

% tweaks
showSplashScreen = true;

% ---- show splash screen
if showSplashScreen
    [hSplashScreen, hSplashAxes, hLabel] = obj.showSplashScreen(sprintf('MIB %s', obj.mibVersion), sprintf('Staring MIB\n%s\nPlease wait...', obj.mibVersion));
    %hLabel.String = 'adding something else';
end

% generate the resource file for icons and images
assetsDir = fullfile(obj.mibPath, 'assets');
resourceFile  = fullfile(obj.mibPath, 'assets', 'mib_icons.res');
if ~isfile(resourceFile)
    core.MibIconCache.buildResourceFile(assetsDir, resourceFile);
    % usage example:
    % imgBrush = core.MibIconCache.get('about_16px');         % loads from the resource class on first call
    % h.brushButton.Icon = imgBrush;
end

% Initialize the cheap non-Java libraries and configure the lazy Java library
% gateway (utils.ensureJavaLibraries caches mibPath/ExternalDirs); Java
% libraries (Bio-Formats, Fiji, Imaris, ...) are linked on their first use.
% imageselection is included here because javaaddpath silently fails once
% loci.formats.Memoizer objects exist (BioFormats use), so it must be loaded
% before the first Bio-Formats call.
obj.initializeLibraries({'bm3d', 'imageselection'});

% get the current version of Matlab
obj.matlabVersion = obj.mibModel.matlabVersion;

%% ----------------- INIT THE MAIN VIEW -----------------
obj.view = views.MibView(obj);
obj.mibModel.mibGUI = obj.view.gui;
obj.mibModel.mibController = obj;   % back-reference, used by MibModel.getProgressBarParent to reach the active document
% --- create controller for panels and add view into them
obj.addGuiControllers();

% ---- add callbacks ----
% add callback for selection of the
obj.view.handles.ribbon.global.SelectedTabChangedFcn = @(~, ~)obj.globalTabGroup_SelectionCallback;


% seed the brush cursor visibility from the segmentation tool that the dropdown
% starts with: segmentationTool_Callback does not fire during startup and
% updateGuiWidgets only runs when a dataset is loaded, so without this the flag
% would stay wrong until the user switches tools. The same tool list is used in
% MibSegmentation.segmentationTool_Callback and MibController.updateGuiWidgets.
% preferences.System.EnableSelection is not the condition here: it is a
% per-dataset property, and updateBrushCursor already re-checks browse-only
% datasets on every mouse move
obj.view.brushCursorShow = ismember(obj.cSegmentation.handles.segmTool.Value, ...
    {'3D ball', 'Spot', 'Brush'});

% --------- update listeners
% callback for change of properties in obj.view.handles.imageViewDocGroup, used to track selection of panels in the image view panel
obj.listeners{1} = addlistener(obj.view.handles.imageViewDocGroup, 'PropertyChanged', @obj.listener_appStateChanged);
obj.listeners{end+1} = addlistener(obj.mibModel, 'NewDataset', @(src, evnt) obj.listener_newDataset(src, evnt)); % update toolbar buttons
obj.listeners{end+1} = addlistener(obj.mibModel, 'ShowErrorDialog', @(src, evnt) obj.listener_showErrorDialog(src, evnt));
obj.listeners{end+1} = addlistener(obj.mibModel, 'ShowImage', @(src, evnt) obj.listener_showImage(src, evnt));
obj.listeners{end+1} = addlistener(obj.mibModel, 'UpdateDatasetAxes', @(src, evnt) obj.listener_updateDatasetAxes(src, evnt));
obj.listeners{end+1} = addlistener(obj.mibModel, 'UpdateToolbar', @(src, evnt) obj.listener_updateToolbar(src, evnt)); % update toolbar buttons
obj.listeners{end+1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src, evnt) obj.listener_updateGuiWidgets(src, evnt)); % update GUI widgets
obj.listeners{end+1} = addlistener(obj.mibModel, 'UpdateUserScore', @(src, evnt) obj.listner_ModelEvent(src, evnt)); % update GUI widgets
obj.listeners{end+1} = addlistener(obj.mibModel, 'KeyPressEvent', @(src,evnt) obj.listner_ModelEvent(src, evnt));

%obj.listeners{end+1} = addlistener(obj.model, 'modelNotify', @(src, evnt) obj.listner_ModelEvent_Callback(src, evnt));
%obj.listeners{end+1} = addlistener(obj.model, 'modelNotify', @obj.listner_ModelEvent_Callback);
%obj.listeners{end+1} = addlistener(obj.model, 'keyPressEvent', @obj.listner2_Callback);
%obj.listeners{end+1} = addlistener(obj.model, 'newFileCreated', @obj.listner2_Callback);

% Make the GUI visible
drawnow;
obj.view.gui.Visible = true;


if showSplashScreen; hSplashScreen.focus; end  % focus on the splash screen
%pause(2);

% do GUI post-initialization tasks that require GUI to be visible
obj.view.doPostInitializationTasks();

% show image
obj.showImage();

if showSplashScreen
    %hLabel.String = 'finishing'; drawnow nocallbacks;
    % close the splash screen
    delete(hSplashScreen);
end

if obj.mibModel.preferences.Tips.ShowTips == 1
    try     % on MacOs this gives an error
        obj.startController('controllers.WelcomeTips');
    catch err
        obj.mibModel.preferences.Tips.ShowTips = false;
    end
end

% tell the user that mib3.mat came from a newer MIB than this one, which is
% detected in models.MibModel.initializePreferences long before there is a
% window to parent a dialog to. Only the settings this version implements were
% restored, and the newer file was parked under its own version - worth saying
% out loud, since the standalone application shows no command window
if isfield(obj.mibModel.sessionSettings, 'PreferencesDowngradeMessage')
    downgradeMsg = obj.mibModel.sessionSettings.PreferencesDowngradeMessage;
    obj.mibModel.sessionSettings = rmfield(obj.mibModel.sessionSettings, 'PreferencesDowngradeMessage');   % show once
    try
        dlgOptions.MsgBoxOnly = true;
        dlgOptions.Icon = 'puffin_warning';
        dlgOptions.HeaderLines = 4;
        utils.dlgs.inputUniversalDlg(obj.view.gui, downgradeMsg, {}, {}, ...
            'Preferences from a newer MIB', dlgOptions);
    catch err
        warning('MIB:preferencesFromNewerVersion', ...
            'Could not show the preferences version dialog: %s', err.message);
    end
end

% MATLAB R2026b and newer no longer bundle a Java runtime. MIB starts without
% it (utils.ensureJavaLibraries skips the Java libraries), but Bio-Formats,
% Fiji, Imaris, OMERO and, outside Windows, the image clipboard need Java, so
% explain what is missing and offer utils.JavaSetup, which finds an installed
% Java (or links to the download) and writes the MATLAB / MATLAB Runtime
% setting. On Windows imclipboard falls back to .NET. Three cases:
% - the MATLAB Java setting already points to a folder: only the restart is missing
% - preferences.ExternalDirs.JavaInstallationPath holds a Java folder: MIB was set
%   up before, typically a new MATLAB release or MATLAB Runtime lost the setting
%   (mib3.mat is shared between releases, the MATLAB setting is not); re-apply it
% - otherwise: search for Java
if ~usejava('jvm')
    storedJavaPath = '';
    if isfield(obj.mibModel.preferences.ExternalDirs, 'JavaInstallationPath')
        storedJavaPath = char(obj.mibModel.preferences.ExternalDirs.JavaInstallationPath);
        if isempty(utils.JavaSetup.inspectFolder(storedJavaPath)); storedJavaPath = ''; end
    end
    pendingJavaPath = utils.JavaSetup.configuredHome();

    % plain text in a placeholder (NaN) row: inputUniversalDlg renders <html>
    % only in MsgBoxOnly mode, and this dialog needs OK + Cancel
    clipboardItem = '';
    if ~ispc; clipboardItem = sprintf('\n  - copying images to and from the system clipboard'); end
    javaMsg = sprintf(['MIB works without Java, but these features need it:\n' ...
        '  - Bio-Formats readers (CZI, LIF, ND2, ZVI and many other microscope formats) and saving OME-TIFF\n' ...
        '  - Fiji, Imaris and OMERO connections%s\n\n'], clipboardItem);
    okButtonText = 'Configure Java';
    if ~isempty(pendingJavaPath)
        javaMsg = [javaMsg sprintf(['Java is already set to\n%s\nbut becomes available only after a restart: ' ...
            'please %s.'], pendingJavaPath, utils.JavaSetup.restartText())];
        okButtonText = 'OK';
    elseif ~isempty(storedJavaPath)
        javaMsg = [javaMsg sprintf(['MIB was set up to use Java from\n%s\nbut this MATLAB is not connected ' ...
            'to it, which happens after installing a new MATLAB version.\n\n' ...
            'Press "Configure Java" to connect it again.'], storedJavaPath)];
    else
        javaMsg = [javaMsg sprintf(['Press "Configure Java": MIB looks for an installed Java and helps you ' ...
            'download one when there is none.\n\n' ...
            'The same settings are in Home -> Preferences -> External directories -> Java.'])];
    end
    try
        dlgOptions = struct();
        dlgOptions.Icon = 'puffin_warning';
        dlgOptions.HeaderLines = 1;
        dlgOptions.OkBtnText = okButtonText;
        dlgOptions.HelpBtnText = 'Instructions';
        dlgOptions.HelpUrl = @() utils.openHelpPage( ...
            fullfile(fileparts(obj.mibPath), 'docs', 'html', 'getting-started', 'installation', 'java.html'), ...
            'http://mib.helsinki.fi/help/main3/getting-started/installation/java.html');
        dlgOptions.WindowWidth = 520;
        dlgOptions.mibPath = obj.mibPath;
        answer = utils.dlgs.inputUniversalDlg(obj.view.gui, 'Java was not found', {javaMsg}, {NaN}, ...
            'Java is missing', dlgOptions);
        if ~isempty(answer) && isempty(pendingJavaPath)
            [javaStatus, javaHome] = utils.JavaSetup.configure(obj.view.gui, obj.mibPath, storedJavaPath);
            if javaStatus; obj.mibModel.preferences.ExternalDirs.JavaInstallationPath = javaHome; end
        end
    catch err
        warning('MIB:javaNotFound', ['Java was not found (%s); Bio-Formats, Fiji, Imaris and OMERO ' ...
            'are unavailable. Use Home -> Preferences -> External directories -> Java'], err.message);
    end
end

% ask once per workstation where the user statistics should be kept.
% The default folder is machine-local: on Windows %APPDATA% only travels
% between computers when an administrator configured a roaming profile, which
% is rarely the case, so without asking the statistics would silently stay
% behind. The flag lives in the machine-local mib3.mat, hence once per
% computer - which is what is needed, as every computer has to be pointed at
% the shared folder on its own.
% Deliberately not part of deferredStartupTasks: unlike the update check this
% costs no network, and a dialog appearing seconds after the window is up
% would be jarring.
if ~obj.mibModel.preferences.System.UserStatsPromptShown
    obj.mibModel.preferences.System.UserStatsPromptShown = true;    % ask only once, even if the dialog fails
    try
        currentStatsFolder = fileparts(obj.mibModel.preferences.System.UserStatsProfile);
        chosenStatsFolder = utils.dlgs.chooseUserStatsLocation(obj.view.gui, currentStatsFolder, ...
            struct('mibPath', obj.mibModel.mibPath, ...
                   'tierPointsCoef', obj.mibModel.preferences.Users.tierPointsCoef, ...
                   'firstRun', true));
        if ~isempty(chosenStatsFolder) && ~strcmp(chosenStatsFolder, currentStatsFolder)
            obj.mibModel.relocateUserStats(chosenStatsFolder);
        end
    catch err
        warning('MIB:userStatsPrompt', ...
            'Could not show the statistics location dialog: %s', err.message);
    end
end

% run deferred startup tasks (parallel limit warm-up, check for update) from
% a single-shot timer, so the slow parcluster query and the network request
% (up to 4 s timeout when offline) never block the startup
obj.updateCheckTimer = timer('StartDelay', 8, 'ExecutionMode', 'singleShot', ...
    'TimerFcn', @(~,~) obj.deferredStartupTasks(), 'Name', 'MIB-DeferredStartup');
start(obj.updateCheckTimer);

end
