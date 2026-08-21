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
% The files that were picked up are reported to the command window unless the
% model was constructed with ``Verbose = false`` (``obj.verboseStartup``);
% warnings raised by a failed handover of the MIB2 statistics are printed either way.
%
% Input Arguments:
%   none
%
% Usage:
%   **Example 1** - called internally during MibModel initialization
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

% 'defaults' mode (tests) stops after the defaults generated above: no file of
% the user is read, written or moved, see the Preferences argument of the constructor
restoreSavedPreferences = strcmp(obj.preferencesMode, 'saved');

if restoreSavedPreferences && exist(prefsFn, 'file') ~= 0
    % Load previously saved preferences
    load(prefsFn); %#ok<LOAD> load mib_pars structure
    if obj.verboseStartup; fprintf('MIB parameters file: %s\n', prefsFn); end
elseif restoreSavedPreferences
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
        if obj.verboseStartup; fprintf('MIB override global parameters file: %s\n', overridePreferencesFile); end

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
% Handle preference migration when MIB version changes.
% Preferences are forward-compatible but not backward-compatible: a newer MIB
% understands everything an older one wrote, while an older one must not adopt
% settings it does not implement. The three cases below follow from that.
if exist('mib_pars', 'var') && isfield(mib_pars, 'mibVersion')  %#ok<NODEF>
    if mib_pars.mibVersion < mibVersionNumeric
        % Saved by an older MIB: merge old preferences with new defaults, so
        % fields added since keep their default value
        obj.preferences = utils.concatenateStructures(obj.preferences, mib_pars.preferences);

        % If this version ran before and was downgraded in between, its own
        % preferences were parked in mib3_<version>.mat by the branch below.
        % Restore them as the base and let the values the older session changed
        % win on top, so neither the settings unknown to the older MIB nor the
        % edits made while on it are lost.
        parkedFn = fullfile(prefdir, sprintf('mib3_%.2f.mat', mibVersionNumeric));
        if isfile(parkedFn)
            try
                parked = load(parkedFn);   %#ok<LOAD> holds a mib_pars structure
                obj.preferences = utils.concatenateStructures(obj.preferences, parked.mib_pars.preferences);
                obj.preferences = utils.concatenateStructures(obj.preferences, mib_pars.preferences);
                if obj.verboseStartup; fprintf('MIB preferences of this version restored from: %s\n', parkedFn); end
            catch parkedErr
                warning('MIB:preferencesRestore', 'Could not restore the parked preferences from %s: %s', ...
                    parkedFn, parkedErr.message);
            end
        end
    elseif mib_pars.mibVersion == mibVersionNumeric
        % Same version: restore preferences but reinitialize Users.Tiers
        % Users.Tiers is not stored and must be reinitialized each session
        mib_pars.preferences.Users.Tiers = obj.preferences.Users.Tiers;
        obj.preferences = mib_pars.preferences;
    else
        % Saved by a NEWER MIB than the one running now. MibController.exitProgram
        % rewrites mib3.mat unconditionally, so this session would otherwise
        % overwrite the newer settings with the defaults of this version.
        % 1. park a copy under the version that wrote it, to be picked up by the
        %    branch above when that version runs again
        parkedFn = fullfile(prefdir, sprintf('mib3_%.2f.mat', mib_pars.mibVersion));
        try
            copyfile(prefsFn, parkedFn);   % always refreshed: mib3.mat is the newest state of that version
        catch parkErr
            warning('MIB:preferencesPark', 'Could not park the newer preferences to %s: %s', ...
                parkedFn, parkErr.message);
            parkedFn = '';
        end

        % 2. take over only the settings this version actually implements; a
        %    field added after this release would otherwise be carried in and
        %    written back on exit without ever being used
        obj.preferences = utils.concatenateStructures(obj.preferences, mib_pars.preferences, true);

        downgradeMsg = sprintf(['The preferences file was written by MIB %.2f, ' ...
            'while this is MIB %.2f.\n\nOnly the settings known to this version were ' ...
            'restored; the newer ones were left out.'], mib_pars.mibVersion, mibVersionNumeric);
        if ~isempty(parkedFn)
            downgradeMsg = sprintf('%s\n\nA copy of the newer preferences is kept in:\n%s\nand is restored automatically when MIB %.2f is started again.', ...
                downgradeMsg, parkedFn, mib_pars.mibVersion);
        end
        warning('MIB:preferencesFromNewerVersion', '%s', downgradeMsg);
        % shown once by controllers.MibController.initialize, when there is a window to parent it to
        obj.sessionSettings.PreferencesDowngradeMessage = downgradeMsg;
    end
end

% force update of cpuParallelLimit; when the limit was not provided to the
% constructor it is computed lazily (get.cpuParallelLimitMax) to avoid the
% slow parcluster query during startup - the lazy getter applies this clamp
if ~isempty(obj.cpuParallelLimitMaxCached)
    obj.preferences.System.cpuParallelLimit = min([obj.preferences.System.cpuParallelLimit, obj.cpuParallelLimitMaxCached]);
end

% ------------ restore user statistics ------------
if ~restoreSavedPreferences
    % 'defaults' mode: no shard is read and no migration runs, so the session
    % starts from the zeroed Users.Tiers that generatePreferences produced and
    % anything written on exit would be exactly this session's own points.
    % UserStatsProfile keeps the default path, but nothing here touches it.
    obj.preferences.System.UserStatsPromptShown = true;   % never ask for a location
    obj.sessionSettings.UserStats.TotalAtLoad = obj.preferences.Users.Tiers;
    obj.sessionSettings.UserStats.OwnShardAtLoad = struct();
    return;
end

% Statistics live in the folder of the path stored in preferences, as one file
% per workstation (mib_user_<COMPUTERNAME>.mat). The shards found there are
% summed, so pointing several machines at one shared folder makes their
% statistics add up without any of them overwriting the others.
%
% Backfill first: a preferences file saved by the same MIB version replaces the
% defaults wholesale above, so fields added after it was written are simply
% absent rather than merged in.
if ~isfield(obj.preferences.System, 'UserStatsProfile') || isempty(obj.preferences.System.UserStatsProfile)
    defaultStatsDir = utils.getUserStatsDir();
    if isempty(defaultStatsDir); defaultStatsDir = prefdir; end
    obj.preferences.System.UserStatsProfile = fullfile(defaultStatsDir, ...
        sprintf('mib_user_%s.mat', utils.identifyComputerName()));
end
if ~isfield(obj.preferences.System, 'UserStatsPromptShown')
    obj.preferences.System.UserStatsPromptShown = false;
end

userStatsDir = fileparts(obj.preferences.System.UserStatsProfile);
% Only the folder of the stored path matters: the file name is always this
% machine's shard, so a preference pointing at any other name still resolves here
userStatsFn = fullfile(userStatsDir, sprintf('mib_user_%s.mat', utils.identifyComputerName()));

% --- one-time handover of the statistics collected with MIB2 ---
% MIB2 keeps its points in <prefdir>/mib_user.mat, under the variable Tiers,
% and rewrites that file on every exit (mibController.exitProgram). MIB3 reads
% it exactly once - while this workstation still has no shard of its own - and
% leaves it untouched: MIB2 goes on using its file, and once the MIB3 shard
% exists the MIB2 file is out of scope, so points earned in MIB2 afterwards are
% not counted here. The shard is written straight away, so the handover happens
% even if this session is closed without earning a single point.
mib2StatsFn = fullfile(prefdir, 'mib_user.mat');
if ~isfile(userStatsFn) && isfile(mib2StatsFn)
    try
        importedStats = load(mib2StatsFn, 'Tiers');
        if isfield(importedStats, 'Tiers')
            utils.saveUserStats(userStatsDir, importedStats.Tiers);
            if obj.verboseStartup; fprintf('MIB user statistics imported from MIB2: %s\n', mib2StatsFn); end
        end
    catch importErr
        warning('MIB:userStatsImport', 'Could not import the MIB2 statistics from %s: %s', ...
            mib2StatsFn, importErr.message);
    end
end

% --- sum the shards of every workstation sharing this folder ---
[totalTiers, ownTiers, shardNames] = utils.loadUserStats(userStatsDir, ...
    'tierPointsCoef', obj.preferences.Users.tierPointsCoef);
if ~isempty(totalTiers)
    obj.preferences.Users.Tiers = utils.concatenateStructures(obj.preferences.Users.Tiers, totalTiers);
    if obj.verboseStartup; fprintf('MIB user statistics folder: %s (%d workstation(s))\n', userStatsDir, numel(shardNames)); end
end
obj.preferences.System.UserStatsProfile = userStatsFn;

% Baselines needed by MibController.exitProgram to write back this machine's
% contribution alone: preferences.Users.Tiers holds the sum over all
% workstations, so the session delta has to be added to the shard this machine
% started from rather than the total being written out as-is.
obj.sessionSettings.UserStats.TotalAtLoad = obj.preferences.Users.Tiers;
obj.sessionSettings.UserStats.OwnShardAtLoad = ownTiers;

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
if ~isfield(obj.preferences.IO.Zarr, 'ChunkCacheMB')
    obj.preferences.IO.Zarr.ChunkCacheMB = 512;
end
% backfill the pyenv execution mode for preferences saved before this field existed
if ~isfield(obj.preferences.ExternalDirs, 'PythonExecutionMode') || ...
        isempty(obj.preferences.ExternalDirs.PythonExecutionMode)
    obj.preferences.ExternalDirs.PythonExecutionMode = 'OutOfProcess';
end
io.zarr.Config.setLibrary(obj.preferences.IO.Zarr.Library);
io.zarr.Config.setSmoothing(obj.preferences.IO.Zarr.Smoothing);
io.zarr.Config.setPythonPath(obj.preferences.ExternalDirs.PythonInstallationPath);
io.zarr.Config.setExecutionMode(obj.preferences.ExternalDirs.PythonExecutionMode);
io.zarr.ChunkCache.setBudgetMB(obj.preferences.IO.Zarr.ChunkCacheMB);

% ------------ BioFormats / WSI reader backend ------------
% Push the configured BioFormats reader engine into the process-wide
% io.bioformats.Config used by io.bioformats.Reader. Guard for older saved prefs.
if ~isfield(obj.preferences.IO, 'BioFormats'); obj.preferences.IO.BioFormats = struct(); end
if ~isfield(obj.preferences.IO.BioFormats, 'Library')
    obj.preferences.IO.BioFormats.Library = 'mib';
end
io.BioFormats.Config.setLibrary(obj.preferences.IO.BioFormats.Library);
% Memoizer (.bfmemo) cache directory for the 'mib' backend.
if isfield(obj.preferences, 'ExternalDirs') && ...
        isfield(obj.preferences.ExternalDirs, 'BioFormatsMemoizerMemoDir') && ...
        ~isempty(obj.preferences.ExternalDirs.BioFormatsMemoizerMemoDir)
    io.BioFormats.Config.setMemoDir(obj.preferences.ExternalDirs.BioFormatsMemoizerMemoDir);
end

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