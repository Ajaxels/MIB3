function ownTiers = getOwnStatsShard(obj)
% GETOWNSTATSSHARD - Return this workstation's contribution to the user statistics.
%
% Syntax:
%   .. code-block:: matlab
%
%      ownTiers = obj.getOwnStatsShard()
%
% User statistics are stored as one file per workstation
% (``mib_user_<COMPUTERNAME>.mat``) inside a folder that may be shared
% between machines, and :func:`utils.loadUserStats` sums those files at
% startup.  ``preferences.Users.Tiers`` therefore holds the **total across
% every workstation**, which is what the user sees, but it is not what this
% machine may write back: writing the total into this machine's shard would
% re-count all the other machines on every exit, and the totals would double
% each session.
%
% This method reconstructs the value this machine is entitled to write:
%
%   ``shard at startup + (current total - total at startup)``
%
% where both baselines were captured by
% :func:`models.MibModel.initializePreferences` into
% ``sessionSettings.UserStats``.  Only scalar numeric counters take part;
% ``tierLevel`` is skipped because it is derived from ``collectedPoints`` and
% recomputed when the shards are summed, and ``logStartDate`` is taken from
% this machine's own shard so that its log keeps starting when MIB first ran
% here.
%
% When the baselines are missing - a fresh installation, or a session that
% started before this bookkeeping existed - the current values are returned
% unchanged, which is correct because there was nothing to double-count.
%
% Input Arguments:
%   none
%
% Output Arguments:
%   - **ownTiers** - [struct] statistics contributed by this workstation,
%     ready to be passed to :func:`utils.saveUserStats`
%
% Usage:
%   **Example 1** - store this workstation's shard
%
%   .. code-block:: matlab
%
%      statsFolder = fileparts(obj.preferences.System.UserStatsProfile);
%      utils.saveUserStats(statsFolder, obj.getOwnStatsShard());
%
% See also: utils.saveUserStats, utils.loadUserStats,
% models.MibModel.initializePreferences, models.MibModel.relocateUserStats

arguments (Input)
    obj models.MibModel
end

currentTiers = obj.preferences.Users.Tiers;

totalAtLoad = struct();
ownShardAtLoad = struct();
if isstruct(obj.sessionSettings) && isfield(obj.sessionSettings, 'UserStats')
    totalAtLoad = obj.sessionSettings.UserStats.TotalAtLoad;
    ownShardAtLoad = obj.sessionSettings.UserStats.OwnShardAtLoad;
end

ownTiers = currentTiers;    % keeps the non-numeric and derived fields as they are
tierFieldNames = fieldnames(currentTiers);
for tierFieldId = 1:numel(tierFieldNames)
    tierFieldName = tierFieldNames{tierFieldId};
    if strcmp(tierFieldName, 'tierLevel'); continue; end   % derived, recomputed on load

    currentValue = currentTiers.(tierFieldName);
    if ~isnumeric(currentValue) || ~isscalar(currentValue); continue; end

    sessionDelta = currentValue;
    if isfield(totalAtLoad, tierFieldName) && isnumeric(totalAtLoad.(tierFieldName))
        sessionDelta = currentValue - totalAtLoad.(tierFieldName);
    end

    if isfield(ownShardAtLoad, tierFieldName) && isnumeric(ownShardAtLoad.(tierFieldName))
        ownTiers.(tierFieldName) = ownShardAtLoad.(tierFieldName) + sessionDelta;
    else
        ownTiers.(tierFieldName) = sessionDelta;
    end
end

if isfield(ownShardAtLoad, 'logStartDate')
    ownTiers.logStartDate = ownShardAtLoad.logStartDate;
end

end
