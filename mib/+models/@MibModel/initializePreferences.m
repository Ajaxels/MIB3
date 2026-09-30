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
% When the user has no ``mib3.mat`` yet, the first override file found in
% ``obj.mibPath`` is merged over the defaults, in this order:
% ``mib3_prefs_override_<COMPUTERNAME>.json``, ``mib3_prefs_override_<COMPUTERNAME>.mat``,
% ``mib3_prefs_override.json``, ``mib3_prefs_override.mat``. A JSON file, written by
% :func:`models.MibModel.saveOverridePreferences`, may list any subset of the settings;
% the rest keep their defaults. Its values are coerced back to the class and shape of
% the defaults - ``jsondecode`` returns every vector as a column, ``{}`` as ``[]`` and
% cannot hold ``Inf``/``NaN``, which the file stores as the strings ``"Inf"``,
% ``"-Inf"``, ``"NaN"``. ``"_comment"`` keys are dropped, unknown settings are dropped
% with a ``MIB:preferencesOverride`` warning, and a file that cannot be read is ignored
% with the same warning. ``Users`` is never taken from an override file, and
% ``KeyShortcuts`` only when the file has at least as many actions as this version.
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
    % Override file allows system-wide preference defaults. The first file found
    % wins: the one for this computer before the one for all computers, and JSON
    % (written by MibModel.saveOverridePreferences) before the legacy MAT copy of mib3.mat
    computerName = utils.identifyComputerName();
    overrideCandidates = fullfile(obj.mibPath, { ...
        sprintf('mib3_prefs_override_%s.json', computerName), ...
        sprintf('mib3_prefs_override_%s.mat', computerName), ...
        'mib3_prefs_override.json', ...
        'mib3_prefs_override.mat'});
    overridePreferencesFile = overrideCandidates(isfile(overrideCandidates));

    if ~isempty(overridePreferencesFile)
        overridePreferencesFile = overridePreferencesFile{1};
        overridePreferences = [];
        try
            [~, ~, overrideExt] = fileparts(overridePreferencesFile);
            if strcmpi(overrideExt, '.json')
                overrideJson = jsondecode(fileread(overridePreferencesFile));
                overridePreferences = coercePreferences(overrideJson.preferences, obj.preferences, '');
            else
                overrideMat = load(overridePreferencesFile);
                overridePreferences = overrideMat.mib_pars.preferences;
            end
            if obj.verboseStartup; fprintf('MIB override global parameters file: %s\n', overridePreferencesFile); end
        catch overrideErr
            % a hand-edited file may be malformed: start from the defaults instead
            warning('MIB:preferencesOverride', 'The preferences override file was ignored: %s\n%s', ...
                overridePreferencesFile, overrideErr.message);
        end

        if ~isempty(overridePreferences)
            % Remove fields that should not be overridden
            if isfield(overridePreferences, 'Users')
                % Users.Tiers structure tracks user movements and should not be overridden
                overridePreferences = rmfield(overridePreferences, 'Users');
            end

            % Ensure key shortcuts are complete: the arrays are matched by index to
            % KeyShortcuts.Action, so a file written by a MIB with a different number
            % of actions would shift the shortcuts onto the wrong actions. A JSON
            % file may hold only some of the arrays, each of them has to fit
            if isfield(overridePreferences, 'KeyShortcuts')
                numberOfActions = numel(obj.preferences.KeyShortcuts.Action);
                shortcutArrays = struct2cell(overridePreferences.KeyShortcuts);
                if ~all(cellfun(@(shortcutArray) numel(shortcutArray) == numberOfActions, shortcutArrays))
                    overridePreferences = rmfield(overridePreferences, 'KeyShortcuts');
                end
            end

            % Merge override preferences with defaults
            obj.preferences = utils.concatenateStructures(obj.preferences, overridePreferences);
        end
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
        parkedFn = fullfile(prefdir, sprintf('mib3_%s.mat', versionToText(mibVersionNumeric)));
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
        parkedFn = fullfile(prefdir, sprintf('mib3_%s.mat', versionToText(mib_pars.mibVersion)));
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

        downgradeMsg = sprintf(['The preferences file was written by MIB %s, ' ...
            'while this is MIB %s.\n\nOnly the settings known to this version were ' ...
            'restored; the newer ones were left out.'], versionToText(mib_pars.mibVersion), versionToText(mibVersionNumeric));
        if ~isempty(parkedFn)
            downgradeMsg = sprintf('%s\n\nA copy of the newer preferences is kept in:\n%s\nand is restored automatically when MIB %s is started again.', ...
                downgradeMsg, parkedFn, versionToText(mib_pars.mibVersion));
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
% backfill the theme for preferences saved before this field existed
if ~isfield(obj.preferences.Colors, 'Theme') || ...
        ~any(strcmp(obj.preferences.Colors.Theme, {'System', 'Light', 'Dark'}))
    obj.preferences.Colors.Theme = 'System';
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

% sessionSettings.ImageFilters is intentionally NOT created here: it is built on
% the first call of the image filters dialog by
% controllers.ImageFilters.updateSessionSettings, which also preloads TestImg -
% the image used for filter previews. Creating even an empty field here would
% satisfy the isfield() guard in the ImageFilters constructor and leave the
% filter defaults unpopulated.

% ------------ update tips of a day settings ------------
tipFolder = fullfile(obj.mibPath, 'assets', 'tips', '*.html');
tipsFiles = dir(tipFolder);
obj.preferences.Tips.Files = cell([numel(tipsFiles), 1]); % path to the tip files
for i=1:numel(tipsFiles)
    obj.preferences.Tips.Files{i} = fullfile(fullfile(obj.mibPath, 'assets', 'tips'), tipsFiles(i).name);
end

end

%% ------------------------------------------------------------------------
function decoded = coercePreferences(decoded, defaults, parentPath)
% Restore the MATLAB class and shape that jsondecode loses, using the defaults as
% the reference, so no per-setting type table is needed:
%   - 1-D arrays come back as columns: turned into rows when the default is a row
%     (or empty, as an array grown with end+1 is a row)
%   - {} comes back as []: turned back into an empty cell
%   - "Inf", "-Inf" and "NaN", written for numbers that JSON cannot hold, become numbers
% The "_comment" objects, read by jsondecode as x_comment, are dropped. A setting the
% defaults do not have is dropped with a warning, it is most likely misspelled; a
% struct whose default has no fields (DoNotShowDialogs) takes any field.
if isfield(decoded, 'x_comment'); decoded = rmfield(decoded, 'x_comment'); end
if isempty(fieldnames(defaults)); return; end

decodedFields = fieldnames(decoded);
for fieldId = 1:numel(decodedFields)
    fieldName = decodedFields{fieldId};
    settingPath = fieldName;
    if ~isempty(parentPath); settingPath = [parentPath '.' fieldName]; end
    if ~isfield(defaults, fieldName)
        warning('MIB:preferencesOverride', 'Unknown setting in the preferences override file was ignored: %s', settingPath);
        decoded = rmfield(decoded, fieldName);
        continue;
    end

    value = decoded.(fieldName);
    defaultValue = defaults.(fieldName);
    if isstruct(defaultValue) && isscalar(defaultValue)
        if isstruct(value) && isscalar(value)
            value = coercePreferences(value, defaultValue, settingPath);
        end
    elseif isnumeric(defaultValue) || islogical(defaultValue)
        if ischar(value) || iscell(value)
            % "Inf"/"-Inf"/"NaN" of a scalar, or a vector mixing them with numbers
            nonFiniteNames = {'Inf', '-Inf', 'NaN'};
            if ischar(value) && any(strcmp(value, nonFiniteNames))
                value = str2double(value);
            elseif iscell(value) && all(cellfun(@(element) (isnumeric(element) && isscalar(element)) || ...
                    (ischar(element) && any(strcmp(element, nonFiniteNames))), value))
                isText = cellfun(@ischar, value);
                value(isText) = cellfun(@str2double, value(isText), 'UniformOutput', false);
                value = cell2mat(value);
            end
        end
        if (isnumeric(value) || islogical(value)) && ~isempty(defaultValue)
            % keep the class of the default: 0/1 of a logical switch, true/false of a
            % numeric one; an empty default ([] for "not set") says nothing about it
            value = cast(value, 'like', defaultValue);
        end
        value = orientLikeDefault(value, defaultValue);
    elseif iscell(defaultValue)
        if isnumeric(value) && isempty(value)
            value = {};
        elseif ischar(value)
            value = {value};
        end
        value = orientLikeDefault(value, defaultValue);
    end
    decoded.(fieldName) = value;
end
end

%% ------------------------------------------------------------------------
function value = orientLikeDefault(value, defaultValue)
% turn a vector that jsondecode returned as a column into the orientation of the
% default; an empty default is treated as a row, the shape end+1 grows it into.
% Cells nested in a cell have no default of their own and get the orientation of
% the outer default, e.g. {{'AM'}, 'TIF'}
if iscell(value)
    for elementId = 1:numel(value)
        if iscell(value{elementId}); value{elementId} = orientLikeDefault(value{elementId}, defaultValue); end
    end
end
if ~isvector(value) || isscalar(value) || ischar(value); return; end
if isempty(defaultValue) || isrow(defaultValue)
    value = reshape(value, 1, []);
elseif iscolumn(defaultValue)
    value = reshape(value, [], 1);
end
end

%% ------------------------------------------------------------------------
function versionText = versionToText(versionNumeric)
% numeric MIB version as text, for messages and for the parked preferences file
% name. Releases are YYYY.MM and previews YYYY.MMDD, so %.2f would print every
% preview of a month as the same version and give them one shared parked file.
% Four decimals keep them apart; the trailing "00" of a release is dropped, so
% 2026.10 stays "2026.10" and its file name matches the one older MIB wrote
versionText = sprintf('%.4f', versionNumeric);
if endsWith(versionText, '00'); versionText = versionText(1:end-2); end
end