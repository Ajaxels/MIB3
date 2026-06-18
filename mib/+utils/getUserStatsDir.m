function statsDir = getUserStatsDir()
% GETUSERSTATSDIR - Get the roaming directory for MIB user statistics.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      statsDir = getUserStatsDir()
%
% Returns the OS-appropriate roaming directory where ``mib_user.mat``
% (user Tiers/statistics) should be stored.  Using a roaming location
% means the file is automatically synced across workstations on
% Windows domain environments.
%
% Platform-specific locations:
%
% - Windows: ``%APPDATA%\MathWorks\MIB\``  (C:\\Users\\<user>\\AppData\\Roaming\\MathWorks\\MIB)
% - macOS:   ``~/Library/Application Support/MIB/``
% - Linux:   ``$XDG_DATA_HOME/MIB/`` or ``~/.local/share/MIB/``
%
% On failure (environment variable unset, directory cannot be created)
% the function returns an empty string ``''`` and the caller should fall
% back to ``utils.getPrefDir()``.
%
% Output Arguments:
%   - **statsDir** — [char] full path to the MIB user-stats directory,
%     or ``''`` when the roaming location is unavailable
%
% Usage:
%
%   **Example 1** — retrieve the user-stats directory path
%
%   .. code-block:: matlab
%
%      statsDir = utils.getUserStatsDir();
%
% See also: utils.getPrefDir

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
