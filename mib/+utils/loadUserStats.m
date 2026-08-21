function [totalTiers, ownTiers, shardNames] = loadUserStats(statsFolder, options)
% LOADUSERSTATS - Load and merge the per-machine MIB statistics shards.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      [totalTiers, ownTiers, shardNames] = loadUserStats(statsFolder)
%      [totalTiers, ownTiers, shardNames] = loadUserStats(statsFolder, 'tierPointsCoef', 500)
%
% MIB statistics are stored as one file per workstation
% (``mib_user_<COMPUTERNAME>.mat``, written by :func:`utils.saveUserStats`)
% so that a folder shared through OneDrive or a network home can be used
% from several machines at once.  Because no two machines ever write the
% same file, a sync engine can never merge them incorrectly or produce
% conflict copies; this function does the merging instead, by summing the
% shards at load time.
%
% Merge rules, matching the semantics of the ``Users.Tiers`` fields defined
% in :func:`utils.defaults.generatePreferences`:
%
% - ``logStartDate`` - the earliest value across the shards, so the log
%   still starts when the user first ran MIB anywhere;
% - ``tierLevel`` - **recomputed** from the summed ``collectedPoints`` using
%   the same rule as the level-up check in
%   ``MibImageDocument.gui_WindowButtonUpFcn`` (level up while
%   ``collectedPoints > tierPointsCoef * 2^tierLevel``).  Summing the stored
%   levels would be meaningless, since the level is derived, not counted;
% - every other numeric field is a monotonic counter and is summed.
%
% Only per-workstation shards are read. A plain ``mib_user.mat`` in the same
% folder is ignored on purpose: that is the name MIB2 writes its own statistics
% to on every exit, and MIB3 takes those points over once through the handover
% in :func:`models.MibModel.initializePreferences`. Summing the file here as
% well would count the imported points a second time, and again after every
% MIB2 session.
%
% Unreadable or corrupt shards are skipped with a warning rather than
% failing the load - a half-synchronised file on a slow OneDrive folder
% must never prevent MIB from starting.
%
% Input Arguments:
%   - **statsFolder** - [char] folder holding the shard files.  A missing
%     folder is not an error and yields empty outputs
%   - **options** - [struct] optional name-value arguments:
%
%     - ``tierPointsCoef`` - [numeric] coefficient of the level-up rule,
%       normally ``preferences.Users.tierPointsCoef``.  Default: ``500``
%
% Output Arguments:
%   - **totalTiers** - [struct] merged statistics across all shards, or
%     ``struct([])`` when the folder holds no readable shard.  Callers
%     should test with ``isempty`` and fall back to the defaults
%   - **ownTiers** - [struct] statistics of this workstation's shard alone,
%     or ``struct([])`` when this machine has not written one yet.  Needed
%     by :func:`controllers.MibController.exitProgram` to write back only
%     this machine's contribution
%   - **shardNames** - [cell] names of the shard files that were merged
%
% Usage:
%
%   **Example 1** - load the totals from the configured folder
%
%   .. code-block:: matlab
%
%      statsFolder = fileparts(obj.preferences.System.UserStatsProfile);
%      [totalTiers, ownTiers] = utils.loadUserStats(statsFolder, ...
%          'tierPointsCoef', obj.preferences.Users.tierPointsCoef);
%
% See also: utils.saveUserStats, utils.getUserStatsCandidates,
% utils.defaults.generatePreferences

arguments (Input)
    statsFolder (1,:) char
    options.tierPointsCoef (1,1) double = 500
end

arguments (Output)
    totalTiers struct
    ownTiers struct
    shardNames cell
end

totalTiers = struct([]);
ownTiers = struct([]);
shardNames = {};

if isempty(statsFolder) || ~isfolder(statsFolder); return; end

% Per-workstation shards only. The trailing underscore keeps a plain
% mib_user.mat out of the sum - that file belongs to MIB2, which keeps writing
% to it, and its points are taken over once by the handover in
% models.MibModel.initializePreferences.
shardFiles = dir(fullfile(statsFolder, 'mib_user_*.mat'));
if isempty(shardFiles); return; end

ownShardName = sprintf('mib_user_%s.mat', utils.identifyComputerName());

merged = struct();
maxStoredLevel = 0;
for fileId = 1:numel(shardFiles)
    if shardFiles(fileId).isdir; continue; end
    shardPath = fullfile(statsFolder, shardFiles(fileId).name);
    try
        loadedVars = load(shardPath, 'Tiers');
    catch loadErr
        warning('MIB:loadUserStats', 'Skipping unreadable statistics file %s: %s', ...
            shardPath, loadErr.message);
        continue;
    end
    if ~isfield(loadedVars, 'Tiers') || ~isstruct(loadedVars.Tiers); continue; end

    shardTiers = loadedVars.Tiers;
    shardNames{end+1} = shardFiles(fileId).name; %#ok<AGROW>
    if isfield(shardTiers, 'tierLevel') && isnumeric(shardTiers.tierLevel)
        maxStoredLevel = max(maxStoredLevel, shardTiers.tierLevel);
    end
    merged = i_mergeTiers(merged, shardTiers);

    if strcmpi(shardFiles(fileId).name, ownShardName)
        ownTiers = shardTiers;
    end
end

if isempty(fieldnames(merged)); return; end

% Recompute the derived level from the summed points
if isfield(merged, 'collectedPoints') && isnumeric(merged.collectedPoints)
    tierLevel = 1;
    while merged.collectedPoints > options.tierPointsCoef * 2^tierLevel
        tierLevel = tierLevel + 1;
    end
    merged.tierLevel = tierLevel;
elseif maxStoredLevel > 0
    merged.tierLevel = maxStoredLevel;   % no points recorded, keep the highest level seen
end

totalTiers = merged;

end

% =====================================================================

function merged = i_mergeTiers(merged, shardTiers)
% Fold one shard into the accumulator following the rules in the help above.
% tierLevel is deliberately ignored here and recomputed by the caller.

fieldNames = fieldnames(shardTiers);
for fieldId = 1:numel(fieldNames)
    fieldName = fieldNames{fieldId};
    if strcmp(fieldName, 'tierLevel'); continue; end
    shardValue = shardTiers.(fieldName);

    if ~isfield(merged, fieldName)
        merged.(fieldName) = shardValue;
        continue;
    end

    mergedValue = merged.(fieldName);
    if isdatetime(shardValue) && isdatetime(mergedValue)
        merged.(fieldName) = min(mergedValue, shardValue);
    elseif isnumeric(shardValue) && isnumeric(mergedValue) && ...
            isscalar(shardValue) && isscalar(mergedValue)
        merged.(fieldName) = mergedValue + shardValue;
    end
    % anything else (char, cell, non-scalar) keeps the first value seen
end

end
