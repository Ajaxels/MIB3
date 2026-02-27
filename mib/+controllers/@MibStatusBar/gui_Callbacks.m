function gui_Callbacks(obj, mode)
% function gui_Callbacks(obj, mode)
% callbacks for widgets of some the Status bar obj.handles.status
%
% Syntax:
%   obj.gui_Callbacks();
%   obj.gui_Callbacks(mode);
%
% Description:
%   Central callback dispatcher for all interactive widgets in the
%   MibStatusBar status bar panel. Routes execution to the appropriate
%   handler based on the 'mode' string, which corresponds to the tag of
%   the triggered widget.
%
%   When DeveloperMode is enabled in preferences, each call logs the
%   triggered mode to the MATLAB console for debugging.
%
% Parameters:
%   obj  - [controllers.MibStatusBar] Handle to the MibStatusBar controller
%   mode - [char, optional] Tag of the widget that triggered the callback.
%          Default: '' (no-op). Supported values:
%
%     'selectWorkingDirectory' - Opens a directory picker dialog. Updates
%                                mibModel.currentDirectory and refreshes
%                                the file list in the directory contents panel.
%
%     'currentDirectory'       - Validates and applies a manually typed path
%                                in the currentDirectory field. If the path
%                                includes a filename (detected by file extension),
%                                only the parent folder is kept. Resets to the
%                                previous path if the directory does not exist.
%
%     'copyPath'               - Copies the current directory path string
%                                to the system clipboard.
%
%     'openBrowser'            - Opens the current directory in the native
%                                file browser:
%                                  Windows : Windows Explorer
%                                  macOS   : Finder (via 'open')
%                                  Linux   : Caja file manager, falling back
%                                            to xterm if Caja is unavailable.
%                                Shows an error dialog if the path is invalid.
%
%     'zoom'                   - Reserved for zoom-related status bar actions
%                                
%
% Example 1 - Open a directory picker dialog:
%   obj.gui_Callbacks('selectWorkingDirectory');
%
% Example 2 - Apply a typed path from the currentDirectory field:
%   obj.handles.currentDirectory.Value = 'C:\Data\experiment01';
%   obj.gui_Callbacks('currentDirectory');
%
% Example 3 - Copy the active directory path to the clipboard:
%   obj.gui_Callbacks('copyPath');
%
% Example 4 - Open the active directory in the OS file browser:
%   obj.gui_Callbacks('openBrowser');


arguments (Input)
    obj controllers.MibStatusBar
    mode char = ''
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibStatusBar.gui_Callbacks: "obj.view.handles.status -> %s"\n', mode);
end

switch mode
    case 'selectWorkingDirectory'
        newPath = uigetdir(obj.handles.currentDirectory.Value, 'Choose Directory');
        if newPath == 0; return; end
        obj.mibModel.currentDirectory = newPath;
        obj.handles.currentDirectory.Value = newPath;
        obj.mibController.cDirContents.updateFileList_Callback();
    case 'currentDirectory'
        % update obj.mibModel.currentDirectory variable
        newPath = obj.handles.currentDirectory.Value;
        % get fileparts to clip filename from the path keeping only the
        % directory name
        [filepath, ~, fext] = fileparts(newPath);
        if ~isempty(fext)
            newPath = filepath; 
        end
        if ~isdir(newPath) %#ok<ISDIR>
            obj.handles.currentDirectory.Value = obj.mibModel.currentDirectory;
            return; 
        end
        obj.mibModel.currentDirectory = newPath;
        obj.mibController.cDirContents.updateFileList_Callback();
    case 'copyPath'
        clipboard('copy', obj.handles.currentDirectory.Value);
    case 'openBrowser'
        currentPath = obj.handles.currentDirectory.Value;
        if isdir(currentPath) %#ok<ISDIR>
            if ispc     % for pc
                system(sprintf('explorer.exe "%s"', currentPath));
            elseif ismac    % for linux
                system(sprintf('open %s &', currentPath));
            else    % for linux
                try 
                    unix(sprintf('caja %s &', currentPath));     % try Caja first
                catch err
                    unix(sprintf('xterm -e cd %s &', currentPath));
                end
            end
        else
            errordlg(sprintf('Wrong directory!\n\n%s', currentPath));
        end
    case 'zoom'
        obj.zoomEdit_Callback();
end

end