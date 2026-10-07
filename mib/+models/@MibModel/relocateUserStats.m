function relocateUserStats(obj, statsFolder)
% RELOCATEUSERSTATS - Keep the user statistics of this workstation in another folder.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.relocateUserStats(statsFolder)
%
% Points this workstation at ``statsFolder`` and carries its own statistics
% over, so that moving to a shared folder (OneDrive, a network home) never
% costs the user their level.  What happens, in order:
%
% 1. this machine's shard is written into ``statsFolder`` - the points it
%    earned belong to it and follow it;
% 2. every shard in ``statsFolder`` is summed, so the statistics already left
%    there by other workstations are picked up immediately;
% 3. the session baselines in ``sessionSettings.UserStats`` are reset to the
%    new folder, so that the shard written on exit is computed against the
%    right starting point.
%
% ``statsFolder`` may already hold a shard of this machine: it was used
% before, or ``mib3.mat`` was lost and the first-run prompt is shown again
% while the shared folder keeps the full history. That shard is never
% replaced by the one carried over. Both are snapshots of the history of the
% same machine, one usually ahead of the other, so they are merged counter
% by counter with the larger value winning (the earliest ``logStartDate``,
% the value of the existing file for anything that is not a scalar number),
% and the points of the current session are added on top. Summing them
% instead would count the shared part of the history twice. The merge loses
% nothing that either file holds, unless the two grew independently (two
% MIB installations of the same machine pointing at different folders), in
% which case each counter keeps the larger of the two.
%
% The relocation either completes or changes nothing. It throws, with the
% previous folder and the session baselines left as they were, when
%
% - this machine's shard exists in ``statsFolder`` but cannot be read -
%   typically a OneDrive placeholder that cannot be downloaded while
%   offline, or a damaged file. Writing there would replace a file whose
%   contents are unknown (``MIB:relocateUserStats:unreadableShard``);
% - the shard cannot be written to ``statsFolder``
%   (``MIB:relocateUserStats:writeFailed``).
%
% The message of both errors is written for the user, so the caller can show
% it as it is.
%
% Shards left behind in the previous folder are **not** deleted or moved.
% They may belong to other workstations, which are not this machine's to
% relocate; a machine that is later pointed back at the old folder simply
% picks its own shard up again.
%
% Input Arguments:
%   - **statsFolder** - [char] folder that should hold the statistics from
%     now on; created when it does not exist
%
% Usage:
%   **Example 1** - adopt the folder chosen by the user
%
%   .. code-block:: matlab
%
%      chosenFolder = utils.dlgs.chooseUserStatsLocation(obj.view.gui, currentFolder);
%      if ~isempty(chosenFolder)
%          try
%              obj.mibModel.relocateUserStats(chosenFolder);
%          catch err
%              utils.dlgs.showErrorDialog(obj.view.gui, err, 'Statistics folder');
%          end
%      end
%
% See also: utils.dlgs.chooseUserStatsLocation, utils.loadUserStats,
% utils.saveUserStats, models.MibModel.getOwnStatsShard

arguments (Input)
    obj models.MibModel
    statsFolder (1,:) char
end

% 1. carry this workstation's own points over to the new folder, merged with
% the shard this workstation may already have there rather than replacing it
shardPath = fullfile(statsFolder, sprintf('mib_user_%s.mat', utils.identifyComputerName()));
[~, existingOwnTiers] = utils.loadUserStats(statsFolder, ...
    'tierPointsCoef', obj.preferences.Users.tierPointsCoef);
if isfile(shardPath) && isempty(existingOwnTiers)
    error('MIB:relocateUserStats:unreadableShard', ...
        ['The statistics file of this computer exists in the selected folder but could not be read:\n%s\n\n' ...
        'It may not be synchronized yet (OneDrive) or may be damaged. The statistics folder was not ' ...
        'changed, so that this file is not overwritten. Try again once the file is available.'], shardPath);
end

previousSessionSettings = obj.sessionSettings;
if ~isfield(obj.sessionSettings, 'UserStats')
    % without baselines getOwnStatsShard takes the current values as this
    % machine's own; spelled out here, so that the merge below has a baseline
    obj.sessionSettings.UserStats.TotalAtLoad = obj.preferences.Users.Tiers;
    obj.sessionSettings.UserStats.OwnShardAtLoad = obj.preferences.Users.Tiers;
end
if ~isempty(existingOwnTiers)
    % getOwnStatsShard adds the points of this session on top of this baseline
    obj.sessionSettings.UserStats.OwnShardAtLoad = mergeShardSnapshots( ...
        existingOwnTiers, obj.sessionSettings.UserStats.OwnShardAtLoad);
end
try
    utils.saveUserStats(statsFolder, obj.getOwnStatsShard());
catch saveErr
    % keep the previous location rather than losing track of the statistics
    obj.sessionSettings = previousSessionSettings;
    error('MIB:relocateUserStats:writeFailed', ...
        'The statistics could not be written to:\n%s\n\n%s\n\nThe statistics folder was not changed.', ...
        statsFolder, saveErr.message);
end

obj.preferences.System.UserStatsProfile = shardPath;

% 2. pick up whatever the other workstations left in the same folder
[totalTiers, ownTiers, shardNames] = utils.loadUserStats(statsFolder, ...
    'tierPointsCoef', obj.preferences.Users.tierPointsCoef);
if ~isempty(totalTiers)
    obj.preferences.Users.Tiers = utils.concatenateStructures(obj.preferences.Users.Tiers, totalTiers);
    if obj.verboseStartup; fprintf('MIB user statistics folder: %s (%d workstation(s))\n', statsFolder, numel(shardNames)); end
end

% 3. rebase the session so that the shard written on exit is computed against
% the new folder rather than the previous one
obj.sessionSettings.UserStats.TotalAtLoad = obj.preferences.Users.Tiers;
obj.sessionSettings.UserStats.OwnShardAtLoad = ownTiers;

end

% =====================================================================

function mergedTiers = mergeShardSnapshots(existingTiers, carriedTiers)
% Merge two snapshots of the statistics of the same workstation, see the
% help above: the larger value of every scalar counter, the earliest
% logStartDate, and the value of the existing file for anything else.
% tierLevel takes no part, it is recomputed from collectedPoints on load.

mergedTiers = existingTiers;
carriedFieldNames = fieldnames(carriedTiers);
for fieldId = 1:numel(carriedFieldNames)
    fieldName = carriedFieldNames{fieldId};
    carriedValue = carriedTiers.(fieldName);
    if ~isfield(mergedTiers, fieldName)
        mergedTiers.(fieldName) = carriedValue;
        continue;
    end
    existingValue = mergedTiers.(fieldName);
    if isdatetime(existingValue) && isdatetime(carriedValue)
        mergedTiers.(fieldName) = min(existingValue, carriedValue);
    elseif ~strcmp(fieldName, 'tierLevel') && isnumeric(existingValue) && isnumeric(carriedValue) && ...
            isscalar(existingValue) && isscalar(carriedValue)
        mergedTiers.(fieldName) = max(existingValue, carriedValue);
    end
end

end
