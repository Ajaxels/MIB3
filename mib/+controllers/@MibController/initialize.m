function initialize(obj)
% function initialize(obj)
% Initialize the main MibController class

arguments (Input)
    obj controllers.MibController
end

% tweaks
showSplashScreen = false;

% ---- show splash screen
if showSplashScreen
    [hSplashScreen, hSplashAxes, hLabel] = obj.showSplashScreen(sprintf('MIB %s', obj.mibVersion), sprintf('Staring MIB\n%s\nPlease wait...', obj.mibVersion));
    %hLabel.String = 'adding something else';
end

%% define global preferences
% see also PreferencesController.defaultBtn_Callback()
obj.mibModel.preferences = utils.defaults.generatePreferences();

%% Restore preferences from the last time
prefdir = utils.getPrefDir();
prefsFn = fullfile(prefdir, 'mib3.mat');
if exist(prefsFn, 'file') ~= 0
    load(prefsFn); %#ok<LOAD> load mib_pars structure
    fprintf('MIB parameters file: %s\n', prefsFn);
else
    % check for preference override file ('mib3_prefs_override.mat') located at the same
    % directory where MIB is installed
    overridePreferencesFile = fullfile(obj.mibPath, 'mib3_prefs_override.mat');
    if exist(overridePreferencesFile, 'file') ~= 0
        overridePrefs = load(overridePreferencesFile); %#ok<LOAD>
        fprintf('MIB override global parameters file: %s\n', overridePreferencesFile);
        % remove some fields that should not be used in the override settings
        if isfield(overridePrefs.mib_pars.preferences, 'Users')
            % Users field has Users.Tiers structure to track user's movements
            overridePrefs.mib_pars.preferences = rmfield(overridePrefs.mib_pars.preferences, 'Users');
        end
        % fix the key shortcuts
        if numel(overridePrefs.mib_pars.preferences.KeyShortcuts.Action) < numel(obj.mibModel.preferences.KeyShortcuts.Action)
            overridePrefs.mib_pars.preferences.KeyShortcuts = obj.mibModel.preferences.KeyShortcuts;
        end

        obj.mibModel.preferences = utils.concatenateStructures(obj.mibModel.preferences, overridePrefs.mib_pars.preferences);
    end
end
% define the starting path
if ispc
    start_path = 'C:';
else
    start_path = '/';
end

%% update preferences
if exist('mib_pars', 'var') && isfield(mib_pars, 'mibVersion')  %#ok<NODEF> % % detection for new preferences from MIB 2.72
    % concatenate stored with default preference structures only when versions mismatch
    if mib_pars.mibVersion < obj.mibVersionNumeric
        obj.mibModel.preferences = mibConcatenateStructures(obj.mibModel.preferences, mib_pars.preferences);
    elseif mib_pars.mibVersion == obj.mibVersionNumeric
        % .Users.Tiers is not stored with the preferences and has to be reinitialized 
        mib_pars.preferences.Users.Tiers = obj.mibModel.preferences.Users.Tiers; 
        obj.mibModel.preferences = mib_pars.preferences; 
    end
end

% restore user's stats
userStatsFn = fullfile(prefdir, 'mib_user.mat');
if isfile(userStatsFn)
    load(userStatsFn, 'Tiers');  % load Tiers variable
    if exist('Tiers', 'var')
        obj.mibModel.preferences.Users.Tiers = utils.concatenateStructures(obj.mibModel.preferences.Users.Tiers, Tiers);
    end
end

% update tips of a day settings
tipFolder = fullfile(obj.mibPath, 'assets', 'tips', '*.html');
tipsFiles = dir(tipFolder);
obj.mibModel.preferences.Tips.Files = cell([numel(tipsFiles), 1]); % path to the tip files
for i=1:numel(tipsFiles)
    obj.mibModel.preferences.Tips.Files{i} = fullfile(fullfile(obj.mibPath, 'assets', 'tips'), tipsFiles(i).name);
end

% check whether the last path is still available
if isdir(obj.mibModel.preferences.System.Dirs.LastPath) == 0 %#ok<*ISDIR> isfolder is not compatible with empty stirngs: isfolder([])
    obj.mibModel.preferences.System.Dirs.LastPath = start_path;
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


%% Add paths and Java libraries
%% Update Java libraries

% update Fiji and Omero libs if they are present in Matlab path already
warningState = warning('off');     % store warning settings

% ------------ add BMxD to Matlab path ------------
if ~isdeployed
    if isdir(obj.mibModel.preferences.ExternalDirs.bm3dInstallationPath); addpath(obj.mibModel.preferences.ExternalDirs.bm3dInstallationPath); end
    if isdir(obj.mibModel.preferences.ExternalDirs.bm4dInstallationPath); addpath(obj.mibModel.preferences.ExternalDirs.bm4dInstallationPath); end
end

% Get the Java classpath
javapath = javaclasspath('-all'); 

% ------------ add OMERO ------------
if isdir(obj.mibModel.preferences.ExternalDirs.OmeroInstallationPath)
    if ~isdeployed
        if isfile(fullfile(obj.mibModel.preferences.ExternalDirs.OmeroInstallationPath, 'loadOmero.m'))
            addpath(obj.mibModel.preferences.ExternalDirs.OmeroInstallationPath);
            loadOmero();
        end
    else
        utils.defaults.addToJavaClasspath(javapath, fullfile(obj.mibModel.preferences.ExternalDirs.OmeroInstallationPath, 'libs'));
        import omero.*;
    end
else
    if ~isempty(obj.mibModel.preferences.ExternalDirs.OmeroInstallationPath)
        fprintf('Warning! Omero path is not correct!\nPlease fix it using MIB Preferences dialog (MIB->Home->Preferences->External dirs)\n');
    end
end

% ------------ add Mij.jar to java class, seems to fix the problem of using MIB
% with the recent Fiji release
if all(cellfun(@isempty, strfind(javapath, 'mij.jar')))
    cPath = fullfile(obj.mibPath, 'jars', 'mij.jar');
    javaaddpath(cPath, '-end');
    fprintf('MIB: adding "%s" to Matlab java path\n', cPath);
end

% ------------ add Bio-formats java libraries ------------
if all(cellfun(@isempty, strfind(javapath, 'bioformats_package.jar')))  %#ok<*STRCLFH>
    cPath = fullfile(obj.mibPath, 'jars', 'BioFormats', 'bioformats_package.jar');
    javaaddpath(cPath, '-end');
    fprintf('MIB: adding "%s" to Matlab java path\n', cPath);
end
% Initialize bio-formats logging, otherwise in R2022b use of bio-formats
% generates multiple warning messages
bfInitLogging();

% ------------ add ImageSelection.java for imclipboard ------------
if all(cellfun(@isempty, strfind(javapath, 'ImageSelection')))
    cPath = fullfile(obj.mibPath, 'jars', 'ImageSelection');
    javaaddpath(cPath, '-end');
    fprintf('MIB: adding "%s" to Matlab java path\n', cPath);
end

% ------------ Add Fiji.app ------------
if isdir(obj.mibModel.preferences.ExternalDirs.FijiInstallationPath)
    fprintf('MIB: adding Fiji libraries from "%s" .', obj.mibModel.preferences.ExternalDirs.FijiInstallationPath);
    if ~isdeployed
        addpath(fullfile(obj.mibModel.preferences.ExternalDirs.FijiInstallationPath, 'scripts'));    % add Fiji/scripts path to Matlab path
        fprintf('.');
        utils.defaults.addToJavaClasspath(javapath, fullfile(obj.mibModel.preferences.ExternalDirs.FijiInstallationPath, 'jars'));
        fprintf('.');
        utils.defaults.addToJavaClasspath(javapath, fullfile(obj.mibModel.preferences.ExternalDirs.FijiInstallationPath, 'plugins'));
        fprintf('.');
        fprintf('done!\n');
    else
        % add Mij.jar to java class, seems to fix the problem of using MIB
        % with the recent Fiji release
        if all(cellfun(@isempty, strfind(javapath, 'mij.jar')))
            % Important!!!
            % during compiling include MIB/jars to the files installed for the end user
            % and do not include it into the required files to run
            cPath = fullfile(obj.mibPath, 'jars', 'mij.jar');
            javaaddpath(cPath);
            fprintf('MIB: adding %s to Matlab java path\n', cPath);
        end

        % Add all libraries in jars/ and plugins/ to the classpath
        utils.defaults.addToJavaClasspath(javapath, fullfile(obj.mibModel.preferences.ExternalDirs.FijiInstallationPath, 'jars'));
        utils.defaults.addToJavaClasspath(javapath, fullfile(obj.mibModel.preferences.ExternalDirs.FijiInstallationPath, 'plugins'));

        % Set the Fiji directory (and plugins.dir which is not Fiji.app/plugins/)
        java.lang.System.setProperty('ij.dir', obj.mibModel.preferences.ExternalDirs.FijiInstallationPath);
        java.lang.System.setProperty('plugins.dir', obj.mibModel.preferences.ExternalDirs.FijiInstallationPath);
    end
else
    if ~isempty(obj.mibModel.preferences.ExternalDirs.FijiInstallationPath)
        fprintf('Warning! Fiji path is not correct!\nPlease fix it using MIB Preferences dialog (MIB->Home->Preferences->External dirs)\n');
    end
end

% ------------ add Apache POI java library for xlwrite ------------
if ~ispc && all(cellfun(@isempty, strfind(javapath, 'poi-3.8-20120326.jar')))
    poi_path = fullfile(obj.mibPath, 'jars', 'xlwrite');
    fprintf('MIB: adding "%s" to Matlab java path\n', poi_path);

    javaaddpath(fullfile(poi_path, 'poi-3.8-20120326.jar'));
    javaaddpath(fullfile(poi_path, 'poi-ooxml-3.8-20120326.jar'));
    javaaddpath(fullfile(poi_path, 'poi-ooxml-schemas-3.8-20120326.jar'));
    javaaddpath(fullfile(poi_path, 'xmlbeans-2.3.0.jar'));
    javaaddpath(fullfile(poi_path, 'dom4j-1.6.1.jar'));
    javaaddpath(fullfile(poi_path, 'stax-api-1.0.1.jar'));
end

% ------------ set Imaris path ------------
loadImarisLib = 0;
if isdir(fullfile(obj.mibModel.preferences.ExternalDirs.ImarisInstallationPath, 'XT', 'matlab'))
    setenv('IMARISPATH', obj.mibModel.preferences.ExternalDirs.ImarisInstallationPath);
    loadImarisLib = 1;
else
    obj.mibModel.preferences.ExternalDirs.ImarisInstallationPath = [];
end
if loadImarisLib && isdir(fullfile(obj.mibModel.preferences.ExternalDirs.ImarisInstallationPath, 'XT', 'matlab'))
    % Add the ImarisLib.jar package to the java class path
    if all(cellfun(@isempty, strfind(javapath, 'ImarisLib.jar')))
        javaaddpath(fullfile(obj.mibModel.preferences.ExternalDirs.ImarisInstallationPath, 'XT', 'matlab', 'ImarisLib.jar'));
    end
end
% restore warning settings
warning(warningState);     


%% define default sessionSettings
obj.mibModel.sessionSettings = utils.defaults.generateSessionSettings();
% preload an image used for filter previews
obj.mibModel.sessionSettings.ImageFilters.TestImg = imread(fullfile(obj.mibPath, 'assets', 'images', 'test_img_for_previews.png'));

%% ----------------- INIT THE MAIN VIEW -----------------
obj.view = views.MibView(obj);
obj.mibModel.mibGUI = obj.view.gui;
% --- create controller for panels and add view into them
obj.addGuiControllers();

% ---- add callbacks ----
% add callback for selection of the
obj.view.handles.ribbon.global.SelectedTabChangedFcn = @obj.globalTabGroup_SelectionCallback;

% get the current version of Matlab; keep this variable to be faster and not call ver function
v = ver('matlab'); %#ok<VERMATLAB>
obj.matlabVersion = str2double(v(1).Version);   % conversion is not correct as version named as 9.8, 9.9, 9.10...
obj.mibModel.matlabVersion = obj.matlabVersion;

% this custom icons are RGB doubles with NaNs for transparency areas
obj.view.handles.panels.segmentation.handles.addMaterial.Icon = core.MibIconCache.get('alpha_cache', 'plus_16px'); %obj.mibModel.sessionSettings.guiImages.plus;
obj.view.handles.panels.segmentation.handles.removeMaterial.Icon = core.MibIconCache.get('alpha_cache', 'minus_16px'); %obj.mibModel.sessionSettings.guiImages.minus;

% update mibModel parameters
obj.mibModel.myPath = obj.mibModel.preferences.System.Dirs.LastPath;  % define current working directory

% update MibModel properties based on GUI settings
obj.mibModel.hideImage = obj.view.handles.panels.selection.handles.hideImage.Value;   % define whether or not display the image layer
obj.mibModel.showModel =  obj.view.handles.panels.selection.handles.showModel.Value; % define whether or not display the model layer (used in obj.mibDataset.getRGBimage)
obj.mibModel.showMask = obj.view.handles.panels.selection.handles.showMask.Value; % define whether or not display the mask layer (used in obj.mibDataset.getRGBimage)
obj.mibModel.onFlyImageStretch = obj.view.handles.panels.selection.handles.onFly.Value; % enable/disable live stretching of image intensities
obj.mibModel.showAnnotations = obj.view.handles.panels.selection.handles.showAnnotations.Value;   % enable/disable rendering of annotations
obj.mibModel.showLines3D = obj.view.handles.panels.segmentation.handles.linesShowLines.Value;   % enable/disable show of 3D lines

% Update GUI widgets
obj.cActiveDataset.update_fromModel(); % update widgets of the Datasets panel from the values of obj.MibModel
obj.cSelection.lutTable_update_fromModel(); % update the LUT table in the Selection and View settings panel
%obj.segmentationPanelUpdate_fromModel(); % update widgets of the Segmentation panel

% --------- update listeners
% callback for change of properties in obj.view.handles.imageViewDocGroup, used to track selection of panels in the image view panel
obj.listeners{1} = addlistener(obj.view.handles.imageViewDocGroup, 'PropertyChanged', @obj.listenerAppStateChanged);
obj.listeners{end+1} = addlistener(obj.mibModel, 'ShowErrorDialog', @(src, evnt) obj.listenerShowErrorDialog(src, evnt));
obj.listeners{end+1} = addlistener(obj.mibModel, 'RenderImage', @(src, evnt) obj.listenerRenderImage(src, evnt));
obj.listeners{end+1} = addlistener(obj.mibModel, 'UpdateDatasetAxes', @(src, evnt) obj.listenerUpdateDatasetAxes(src, evnt));

%obj.listeners{end+1} = addlistener(obj.model, 'modelNotify', @(src, evnt) obj.listner_ModelEvent_Callback(src, evnt));
%obj.listeners{end+1} = addlistener(obj.model, 'modelNotify', @obj.listner_ModelEvent_Callback);
%obj.listeners{end+1} = addlistener(obj.model, 'keyPressEvent', @obj.listner2_Callback);
%obj.listeners{end+1} = addlistener(obj.model, 'newFileCreated', @obj.listner2_Callback);

% Make the GUI visible
obj.view.gui.Visible = true;

% update the initialized datasets using the obtained default settings
for i=1:numel(obj.mibModel.I)
    % check whether the selection is enabled or not
    if obj.mibModel.preferences.System.EnableSelection ~= obj.mibModel.I{i}.enableSelection
        fn = fullfile(obj.mibPath, 'assets', 'images', 'default.jpg');
        I = imread(fn);
        obj.mibModel.I{i} = core.MibDataset(I, [], 'Std', 'imageOnly');
        obj.mibModel.I{i}.enableSelection = false;
    end

    % update obj.I{i} properties
    obj.mibModel.I{i}.labels.materialColors = obj.mibModel.preferences.Colors.ModelMaterialColors; % update default model colors
    % update default LUT colors
    if obj.mibModel.I{i}.img.colors < size(obj.mibModel.preferences.Colors.LUTColors, 1)
        obj.mibModel.I{i}.img.lutColors = obj.mibModel.preferences.Colors.LUTColors;
    end

    % update dataset obj.mibModel.I{i}.axesX/Y and obj.mibModel.I{i}.magFactor 
    Options.mode = 'resize';
    Options.index = i;
    eventdata = core.ToggleEventData(Options);
    notify(obj.mibModel, 'UpdateDatasetAxes', eventdata);
end



if showSplashScreen; hSplashScreen.focus; end  % focus on the splash screen
pause(2);
% do GUI post-initialization tasks that require GUI to be visible
obj.view.doPostInitializationTasks();

if showSplashScreen
    %hLabel.String = 'finishing'; drawnow nocallbacks;
    % close the splash screen
    delete(hSplashScreen);
end

if obj.mibModel.preferences.Tips.ShowTips == 1
    try     % on MacOs this gives an error
        obj.startController('controllers.WelcomeTips');
    catch err
        obj.mibModel.preferences.Tips.ShowTips = 0;
    end
end


end
