function prefdir = getPrefDir()
% function prefdir = getPrefDir()
% get directory where MIB preferences are stored
% on Windows it is C:\Users\Username\Matlab
% on Mac it is /Users/username/Matlab
% on Linux it is /home/username/Matlab
%
% Parameters:
%
%
% Return values:
% prefdir: сhar with location of MIB preferences

%|
% @b Examples:
% @code
% prefdir = utils.getPrefDir(); // call from the main controller class
% @endcode
%
% Updates
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
