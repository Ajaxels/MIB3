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
%      if ~isempty(chosenFolder); obj.mibModel.relocateUserStats(chosenFolder); end
%
% See also: utils.dlgs.chooseUserStatsLocation, utils.loadUserStats,
% utils.saveUserStats, models.MibModel.getOwnStatsShard

arguments (Input)
    obj models.MibModel
    statsFolder (1,:) char
end

% 1. carry this workstation's own points over to the new folder
try
    utils.saveUserStats(statsFolder, obj.getOwnStatsShard());
catch saveErr
    warning('MIB:relocateUserStats', ...
        'Could not write the user statistics to %s: %s', statsFolder, saveErr.message);
    return;     % keep the previous location rather than losing track of the statistics
end

obj.preferences.System.UserStatsProfile = fullfile(statsFolder, ...
    sprintf('mib_user_%s.mat', utils.identifyComputerName()));

% 2. pick up whatever the other workstations left in the same folder
[totalTiers, ownTiers, shardNames] = utils.loadUserStats(statsFolder, ...
    'tierPointsCoef', obj.preferences.Users.tierPointsCoef);
if ~isempty(totalTiers)
    obj.preferences.Users.Tiers = utils.concatenateStructures(obj.preferences.Users.Tiers, totalTiers);
    fprintf('MIB user statistics folder: %s (%d workstation(s))\n', statsFolder, numel(shardNames));
end

% 3. rebase the session so that the shard written on exit is computed against
% the new folder rather than the previous one
obj.sessionSettings.UserStats.TotalAtLoad = obj.preferences.Users.Tiers;
obj.sessionSettings.UserStats.OwnShardAtLoad = ownTiers;

end
