function candidates = getUserStatsCandidates()
% GETUSERSTATSCANDIDATES - List folders where MIB user statistics can be kept.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      candidates = getUserStatsCandidates()
%
% Builds the list of locations offered to the user for storing the
% per-machine statistics shards (``mib_user_<COMPUTERNAME>.mat``, see
% :func:`utils.saveUserStats`).  The list is ordered from the most likely
% to follow the user between workstations to the least:
%
% 1. the folder named by the ``MIB_USER_STATS`` environment variable, when
%    set - an explicit override so that IT can preconfigure a location for
%    a whole facility;
% 2. ``<OneDrive>\Apps\MIB``, falling back to ``<OneDrive>\Documents\MIB``
%    and then ``<OneDrive>\MIB`` depending on which of those folders the
%    account actually has.  ``Apps`` is the folder OneDrive designates for
%    third-party application data, so MIB does not land in the middle of the
%    user's own files.  ``<OneDrive>`` itself comes from
%    ``%OneDriveCommercial%``, then ``%OneDrive%``, then the
%    ``HKCU\Software\Microsoft\OneDrive\Accounts\*\UserFolder`` registry
%    values.  The registry fallback matters because the environment
%    variables are only present when the OneDrive client has run in the
%    current session, which is not the case for a deployed MIB started
%    from a service or a scheduled task.  The OneDrive root is **never**
%    constructed from ``%USERPROFILE%`` - it is frequently relocated to a
%    different drive;
% 3. ``<HOMESHARE>\MIB`` - the AD network home directory, which follows the
%    user across domain workstations but is unreachable off site;
% 4. the machine-local folder returned by :func:`utils.getUserStatsDir`,
%    which is always offered as the last entry.
%
% A candidate is listed only when its parent folder exists, so the returned
% list never contains an unusable entry.  The ``MIB`` subfolder itself is
% not created here - :func:`utils.saveUserStats` creates it on first write.
%
% .. warning::
%
%    This function touches the file system and, for ``HOMESHARE``, the
%    network.  It must only be called from user-initiated code such as
%    :func:`utils.dlgs.chooseUserStatsLocation`, never during startup: an
%    unreachable UNC path can block for several seconds.
%
% Output Arguments:
%   - **candidates** - [struct] 1xN structure array, one entry per
%     available location, with fields:
%
%     - ``label`` - [char] short name shown in the chooser dialog
%     - ``folder`` - [char] full path to the folder that would hold the shards
%     - ``note`` - [char] one-line explanation shown under the label
%     - ``syncs`` - [logical] true when the location is expected to follow
%       the user to other workstations
%
% Usage:
%
%   **Example 1** - list the locations and show the first one
%
%   .. code-block:: matlab
%
%      candidates = utils.getUserStatsCandidates();
%      fprintf('%s -> %s\n', candidates(1).label, candidates(1).folder);
%
% See also: utils.getUserStatsDir, utils.loadUserStats, utils.saveUserStats,
% utils.dlgs.chooseUserStatsLocation

arguments (Output)
    candidates (1,:) struct
end

candidates = struct('label', {}, 'folder', {}, 'note', {}, 'syncs', {});

% ------------ 1. explicit override via environment variable ------------
% Listed even when the folder does not exist yet: an administrator may point
% it at a share that MIB is expected to populate on first use.
overrideDir = strtrim(getenv('MIB_USER_STATS'));
if ~isempty(overrideDir)
    candidates(end+1) = struct( ...
        'label',  'Preconfigured location', ...
        'folder', overrideDir, ...
        'note',   'Set by the MIB_USER_STATS environment variable', ...
        'syncs',  true);
end

% ------------ 2. OneDrive ------------
oneDriveRoot = i_findOneDriveRoot();
if ~isempty(oneDriveRoot)
    % Keep MIB out of the top of the user's OneDrive. "Apps" is the folder
    % OneDrive designates for third-party application data and is the right
    % home for settings; "Documents" is the fallback because it is created by
    % Known Folder Move and is present on nearly every account. Neither is
    % guaranteed, so the root remains the last resort.
    oneDriveParent = oneDriveRoot;
    preferredSubFolders = {'Apps', 'Documents'};
    for subFolderId = 1:numel(preferredSubFolders)
        subFolderPath = fullfile(oneDriveRoot, preferredSubFolders{subFolderId});
        if isfolder(subFolderPath)
            oneDriveParent = subFolderPath;
            break;
        end
    end

    candidates(end+1) = struct( ...
        'label',  'OneDrive', ...
        'folder', fullfile(oneDriveParent, 'MIB'), ...
        'note',   'Follows you to any computer where you sign in to OneDrive', ...
        'syncs',  true);
end

% ------------ 3. AD network home directory ------------
% The only place where this function may touch the network - see the warning
% in the help above.
if ispc
    homeShare = strtrim(getenv('HOMESHARE'));
    if ~isempty(homeShare)
        reachable = false;
        try
            reachable = isfolder(homeShare);
        catch
        end
        if reachable
            candidates(end+1) = struct( ...
                'label',  'Network home directory', ...
                'folder', fullfile(homeShare, 'MIB'), ...
                'note',   'Follows you across university computers, needs the network', ...
                'syncs',  true);
        end
    end
end

% ------------ 4. this computer only ------------
localDir = utils.getUserStatsDir();
if isempty(localDir)
    localDir = utils.getPrefDir();
end
candidates(end+1) = struct( ...
    'label',  'This computer only', ...
    'folder', localDir, ...
    'note',   'Statistics stay on this machine and are not shared', ...
    'syncs',  false);

end

% =====================================================================

function oneDriveRoot = i_findOneDriveRoot()
% Locate the OneDrive root folder, preferring the work/school account.
% Returns '' when OneDrive is not configured or the folder is missing.

oneDriveRoot = '';
if ~ispc; return; end

% Environment variables first - set by the OneDrive client for the session
envCandidates = {'OneDriveCommercial', 'OneDrive', 'OneDriveConsumer'};
for i = 1:numel(envCandidates)
    candidateRoot = strtrim(getenv(envCandidates{i}));
    if ~isempty(candidateRoot) && isfolder(candidateRoot)
        oneDriveRoot = candidateRoot;
        return;
    end
end

% Registry fallback for sessions where the client has not run yet
accountKeys = {'Business1', 'Business2', 'Personal'};
for i = 1:numel(accountKeys)
    try
        candidateRoot = winqueryreg('HKEY_CURRENT_USER', ...
            ['Software\Microsoft\OneDrive\Accounts\' accountKeys{i}], 'UserFolder');
    catch
        continue;   % account slot not present
    end
    candidateRoot = strtrim(candidateRoot);
    if ~isempty(candidateRoot) && isfolder(candidateRoot)
        oneDriveRoot = candidateRoot;
        return;
    end
end

end
