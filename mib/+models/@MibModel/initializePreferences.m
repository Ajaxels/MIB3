function initializePreferences(obj)
% INITIALIZEPREFERENCES - Initialize and update MIB preferences from a file.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.initializePreferences()
%
% Initializes MIB preferences by loading saved preferences from the
% user's preferences directory. Handles preference upgrades when
% version changes occur, applies override settings when available,
% and restores user statistics.
%
% Input Arguments:
%   none
%
% Usage:
%   **Example 1** — called internally during MibModel initialization
%
%   .. code-block:: matlab
%
%      obj.initializePreferences();
%
% See also: utils.defaults.generatePreferences, utils.getPrefDir, controllers.Preferences.defaultBtn_Callback

arguments (Input)
    obj models.MibModel
end

% get numerical value of the current MIB version
mibVersionNumeric = utils.getMibVersionNumberic(obj.mibVersion);

% generate default preferences
% see also PreferencesController.defaultBtn_Callback()
obj.preferences = utils.defaults.generatePreferences();

% ------------ define default starting path ------------
% Set platform-specific default path for file operations
if ispc
    start_path = 'C:';
else
    start_path = '/';
end


% ------------ restore preferences from previous session ------------
% Get the preferences directory and check for saved preferences file
prefdir = utils.getPrefDir();
prefsFn = fullfile(prefdir, 'mib3.mat');

if exist(prefsFn, 'file') ~= 0
    % Load previously saved preferences
    load(prefsFn); %#ok<LOAD> load mib_pars structure
    fprintf('MIB parameters file: %s\n', prefsFn);
else
    % ------------ check for preference override file ------------
    % Override file allows system-wide preference defaults
    % get computer name:
    computerName = utils.identifyComputerName();
    overridePreferencesFile = fullfile(obj.mibPath, sprintf('mib3_prefs_override_%s.mat', computerName));
    if ~isfile(overridePreferencesFile)
        overridePreferencesFile = fullfile(obj.mibPath, 'mib3_prefs_override.mat');
    end

    if isfile(overridePreferencesFile)
        overridePrefs = load(overridePreferencesFile); %#ok<LOAD>
        fprintf('MIB override global parameters file: %s\n', overridePreferencesFile);

        % Remove fields that should not be overridden
        if isfield(overridePrefs.mib_pars.preferences, 'Users')
            % Users.Tiers structure tracks user movements and should not be overridden
            overridePrefs.mib_pars.preferences = rmfield(overridePrefs.mib_pars.preferences, 'Users');
        end

        % Ensure key shortcuts are complete
        if numel(overridePrefs.mib_pars.preferences.KeyShortcuts.Action) < numel(obj.preferences.KeyShortcuts.Action)
            overridePrefs.mib_pars.preferences.KeyShortcuts = obj.preferences.KeyShortcuts;
        end

        % Merge override preferences with defaults
        obj.preferences = utils.concatenateStructures(obj.preferences, overridePrefs.mib_pars.preferences);
    end
end

% ------------ update preferences for version changes ------------
% Handle preference migration when MIB version changes
if exist('mib_pars', 'var') && isfield(mib_pars, 'mibVersion')  %#ok<NODEF>
    if mib_pars.mibVersion < mibVersionNumeric
        % Version mismatch: merge old preferences with new defaults
        obj.preferences = utils.concatenateStructures(obj.preferences, mib_pars.preferences);
    elseif mib_pars.mibVersion == mibVersionNumeric
        % Same version: restore preferences but reinitialize Users.Tiers
        % Users.Tiers is not stored and must be reinitialized each session
        mib_pars.preferences.Users.Tiers = obj.preferences.Users.Tiers;
        obj.preferences = mib_pars.preferences;
    end
end

% force update of cpuParallelLimit; when the limit was not provided to the
% constructor it is computed lazily (get.cpuParallelLimitMax) to avoid the
% slow parcluster query during startup — the lazy getter applies this clamp
if ~isempty(obj.cpuParallelLimitMaxCached)
    obj.preferences.System.cpuParallelLimit = min([obj.preferences.System.cpuParallelLimit, obj.cpuParallelLimitMaxCached]);
end

% ------------ restore user statistics ------------
% Use the path stored in preferences (initialised in generatePreferences from
% the OS roaming directory; user can override via the milestone dialog).
% Migration chain runs on first upgrade when the file is not found at the
% stored path, moving it forward from older locations.
userStatsFn = obj.preferences.System.UserStatsProfile;

% --- migration step 1 (Windows only): AppData\Roaming\MIB -> new path ---
if ~isfile(userStatsFn) && ispc
    appDataPath = getenv('APPDATA');
    if ~isempty(appDataPath)
        oldRoamingFn = fullfile(appDataPath, 'MIB', 'mib_user.mat');
        if isfile(oldRoamingFn)
            try
                destDir = fileparts(userStatsFn);
                if ~exist(destDir, 'dir'); mkdir(destDir); end
                movefile(oldRoamingFn, userStatsFn);
                fprintf('MIB user statistics migrated from old roaming path: %s\n', userStatsFn);
            catch migErr
                warning('MIB:userStatsMigration', 'Could not migrate from old roaming path: %s', migErr.message);
                userStatsFn = oldRoamingFn;
            end
        end
    end
end

% --- migration step 2: legacy ~/Matlab/mib_user.mat -> new path ---
if ~isfile(userStatsFn)
    legacyUserStatsFn = fullfile(prefdir, 'mib_user.mat');
    if isfile(legacyUserStatsFn) && ~strcmp(userStatsFn, legacyUserStatsFn)
        try
            destDir = fileparts(userStatsFn);
            if ~exist(destDir, 'dir'); mkdir(destDir); end
            movefile(legacyUserStatsFn, userStatsFn);
            fprintf('MIB user statistics migrated to roaming profile: %s\n', userStatsFn);
        catch migErr
            warning('MIB:userStatsMigration', 'Could not migrate mib_user.mat to roaming profile: %s', migErr.message);
            userStatsFn = legacyUserStatsFn;
        end
    end
end

if isfile(userStatsFn)
    load(userStatsFn, 'Tiers');  % load Tiers variable
    fprintf('MIB user statistics file: %s\n', userStatsFn);
    if exist('Tiers', 'var')
        % Merge saved tier data with defaults
        obj.preferences.Users.Tiers = utils.concatenateStructures(obj.preferences.Users.Tiers, Tiers);
    end
    % Keep preference in sync with the actual location used (may differ after migration)
    obj.preferences.System.UserStatsProfile = userStatsFn;
end

% ------------ validate last used path ------------
% Check if the last used path is still valid, otherwise use default
if isdir(obj.preferences.System.Dirs.LastPath) == 0 %#ok<*ISDIR> isfolder is not compatible with empty strings: isfolder([])
    obj.preferences.System.Dirs.LastPath = start_path;
end
% ------------ OME-Zarr v3 settings ------------
% Push the configured zarr backend + label-smoothing flag into the process-wide
% io.zarr.Config used by io.zarr.Array / io.zarr.Group / MibBigDataLabels.
% Guard for older saved prefs: the flat IO.ZarrLibrary field was migrated to the
% nested IO.Zarr.Library struct; carry an old value over if present.
if ~isfield(obj.preferences, 'IO'); obj.preferences.IO = struct(); end
if ~isfield(obj.preferences.IO, 'Zarr'); obj.preferences.IO.Zarr = struct(); end
if ~isfield(obj.preferences.IO.Zarr, 'Library')
    if isfield(obj.preferences.IO, 'ZarrLibrary')   % migrate old flat field
        obj.preferences.IO.Zarr.Library = obj.preferences.IO.ZarrLibrary;
    else
        obj.preferences.IO.Zarr.Library = 'native';
    end
end
if isfield(obj.preferences.IO, 'ZarrLibrary')
    obj.preferences.IO = rmfield(obj.preferences.IO, 'ZarrLibrary');   % drop legacy field
end
if ~isfield(obj.preferences.IO.Zarr, 'Smoothing')
    obj.preferences.IO.Zarr.Smoothing = true;
end
io.zarr.Config.setLibrary(obj.preferences.IO.Zarr.Library);
io.zarr.Config.setSmoothing(obj.preferences.IO.Zarr.Smoothing);
io.zarr.Config.setPythonPath(obj.preferences.ExternalDirs.PythonInstallationPath);

% preload an image used for filter previews
% move preloading to the first call of the image filters dialog
obj.sessionSettings.ImageFilters.TestImg = []; %imread(fullfile(obj.mibPath, 'assets', 'images', 'test_img_for_previews.png'));

% ------------ update tips of a day settings ------------
tipFolder = fullfile(obj.mibPath, 'assets', 'tips', '*.html');
tipsFiles = dir(tipFolder);
obj.preferences.Tips.Files = cell([numel(tipsFiles), 1]); % path to the tip files
for i=1:numel(tipsFiles)
    obj.preferences.Tips.Files{i} = fullfile(fullfile(obj.mibPath, 'assets', 'tips'), tipsFiles(i).name);
end

end