function prefdir = getPrefDir()
% GETPREFDIR - Get directory where MIB preferences are stored.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      prefdir = getPrefDir()
%
% Platform-specific locations:
%
% - Windows: ``C:\Users\Username\Matlab``
% - macOS:   ``/Users/username/Matlab``
% - Linux:   ``/home/username/Matlab``
%
% Output Arguments:
%   - **prefdir** — [char] full path to the MIB preferences directory
%
% Usage:
%
%   **Example 1** — retrieve the preferences directory path
%
%   .. code-block:: matlab
%
%      prefdir = utils.getPrefDir();
%

arguments (Output)
    prefdir (1,:) char
end

if ispc
    userDir = getenv('USERPROFILE');
else    % Mac and Linux
    userDir = getenv('HOME');
end
prefdir = fullfile(userDir, 'Matlab');
if exist(prefdir, 'dir') == 0
    try
        mkdir(prefdir);
    catch err
        warndlg(sprintf('!!! Warning !!!\n\nThe directory for storing the preferences (%s) can not be created,\nsystem TEMP directory (%s) will be used instead!', prefdir, tempdir), 'Preference dir warning');
        prefdir = tempdir;
    end
end
