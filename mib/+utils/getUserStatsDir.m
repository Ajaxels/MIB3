function statsDir = getUserStatsDir()
% GETUSERSTATSDIR - Get the machine-local directory for MIB user statistics.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      statsDir = getUserStatsDir()
%
% Returns the OS-appropriate per-user application data directory where the
% statistics files (user Tiers) are kept when no shared folder was chosen.
%
% Platform-specific locations:
%
% - Windows: ``%APPDATA%\MathWorks\MIB\``  (C:\\Users\\<user>\\AppData\\Roaming\\MathWorks\\MIB)
% - macOS:   ``~/Library/Application Support/MIB/``
% - Linux:   ``$XDG_DATA_HOME/MIB/`` or ``~/.local/share/MIB/``
%
% .. warning::
%
%    Despite its name, ``AppData\Roaming`` is **machine-local**.  It is
%    uploaded at logoff only when an administrator set a roaming profile path
%    on the account object in Active Directory, which is uncommon; the
%    profile of an ordinary domain-joined workstation reports
%    ``RoamingConfigured = False`` and the folder never leaves the machine.
%    Two things make this easy to misread: domain group policy often defines
%    roaming-profile settings (``AddAdminGroupToRUP``, ``ExcludeProfileDirs``
%    and friends) for every account regardless of whether roaming is actually
%    enabled, and Entra "Enterprise State Roaming" sounds relevant but only
%    ever syncs Windows settings and Store-app data, never ``%APPDATA%``.
%    OneDrive's Known Folder Move likewise covers Desktop, Documents and
%    Pictures and explicitly excludes AppData.
%
%    Treat the returned folder as local to this computer.  For statistics
%    that follow the user between workstations, see
%    :func:`utils.getUserStatsCandidates`, which also offers OneDrive and the
%    AD network home directory.
%
% On failure (environment variable unset, directory cannot be created)
% the function returns an empty string ``''`` and the caller should fall
% back to ``utils.getPrefDir()``.
%
% Output Arguments:
%   - **statsDir** - [char] full path to the MIB user-stats directory,
%     or ``''`` when the location is unavailable
%
% Usage:
%
%   **Example 1** - retrieve the user-stats directory path
%
%   .. code-block:: matlab
%
%      statsDir = utils.getUserStatsDir();
%
% See also: utils.getPrefDir, utils.getUserStatsCandidates, utils.loadUserStats

arguments (Output)
    statsDir (1,:) char
end

statsDir = '';

try
    if ispc
        roamingRoot = getenv('APPDATA');
        if isempty(roamingRoot)
            return;
        end
    elseif ismac
        roamingRoot = fullfile(getenv('HOME'), 'Library', 'Application Support');
    else  % Linux / other Unix
        roamingRoot = getenv('XDG_DATA_HOME');
        if isempty(roamingRoot)
            roamingRoot = fullfile(getenv('HOME'), '.local', 'share');
        end
    end

    mibDir = fullfile(roamingRoot, 'MathWorks', 'MIB');
    if ~exist(mibDir, 'dir')
        mkdir(mibDir);
    end
    statsDir = mibDir;
catch
    statsDir = '';
end
