function shardPath = saveUserStats(statsFolder, ownTiers)
% SAVEUSERSTATS - Write this workstation's MIB statistics shard.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      shardPath = saveUserStats(statsFolder, ownTiers)
%
% Writes ``mib_user_<COMPUTERNAME>.mat`` into ``statsFolder``, creating the
% folder when needed.  This machine only ever writes its own shard, which is
% what makes a shared folder (OneDrive, network home) safe: two workstations
% never write the same file, so the sync engine has nothing to resolve and
% no points can be lost.  The shards are summed back together at load time
% by :func:`utils.loadUserStats`.
%
% .. important::
%
%    ``ownTiers`` must be **this machine's contribution alone**, not the
%    session total.  The in-memory ``preferences.Users.Tiers`` holds the sum
%    across all workstations, so the caller has to subtract the total that
%    was loaded at startup and add the result to the shard it started from -
%    see :func:`controllers.MibController.exitProgram`.  Writing the session
%    total here would re-count every other machine on every exit.
%
% Input Arguments:
%   - **statsFolder** - [char] destination folder for the shard
%   - **ownTiers** - [struct] statistics contributed by this workstation,
%     saved as the ``Tiers`` variable of the ``.mat`` file
%
% Output Arguments:
%   - **shardPath** - [char] full path of the file that was written
%
% Usage:
%
%   **Example 1** - store the shard next to the configured profile
%
%   .. code-block:: matlab
%
%      statsFolder = fileparts(obj.mibModel.preferences.System.UserStatsProfile);
%      shardPath = utils.saveUserStats(statsFolder, ownTiers);
%
% See also: utils.loadUserStats, utils.getUserStatsCandidates,
% controllers.MibController.exitProgram

arguments (Input)
    statsFolder (1,:) char
    ownTiers struct
end

arguments (Output)
    shardPath (1,:) char
end

if ~isfolder(statsFolder)
    mkdir(statsFolder);
end

shardPath = fullfile(statsFolder, sprintf('mib_user_%s.mat', utils.identifyComputerName()));

Tiers = ownTiers;   % saved under the variable name expected by utils.loadUserStats
save(shardPath, 'Tiers');

end
