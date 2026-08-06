function gui_Callbacks(obj, mode)
% GUI_CALLBACKS - Central callback dispatcher for status bar widgets.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.gui_Callbacks()
%      obj.gui_Callbacks(mode)
%
% Routes execution to the appropriate handler based on the widget tag (``mode``).
% When DeveloperMode is enabled, each call logs the triggered mode to console for debugging.
%
% Input Arguments:
%   - **obj** - [MibStatusBar] controller instance
%   - **mode** *(optional)* - [char] widget tag triggering callback (default: ``''`` no-op). Supported values:
%
%     - ``'selectWorkingDirectory'`` - open directory picker dialog, update ``mibModel.currentDirectory``, refresh file list
%     - ``'currentDirectory'`` - validate and apply manually typed path; keep parent folder if filename detected; revert if invalid
%     - ``'copyPath'`` - copy current directory path to system clipboard
%     - ``'openBrowser'`` - open current directory in native file browser:
%
%       - Windows - Windows Explorer
%       - macOS - Finder (via ``open``)
%       - Linux - Caja file manager (fallback: xterm); error dialog if path invalid
%
%     - ``'zoom'`` - reserved for zoom-related status bar actions
%
% **Example 1** - Open directory picker dialog:
%
%   .. code-block:: matlab
%
%      obj.gui_Callbacks('selectWorkingDirectory');
%
% **Example 2** - Apply typed path from currentDirectory field:
%
%   .. code-block:: matlab
%
%      obj.handles.currentDirectory.Value = 'C:\Data\experiment01';
%      obj.gui_Callbacks('currentDirectory');
%
% **Example 3** - Copy active directory path to clipboard:
%
%   .. code-block:: matlab
%
%      obj.gui_Callbacks('copyPath');
%
% **Example 4** - Open active directory in OS file browser:
%
%   .. code-block:: matlab
%
%      obj.gui_Callbacks('openBrowser');
%


arguments (Input)
    obj controllers.MibStatusBar
    mode char = ''
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibStatusBar.gui_Callbacks: "obj.view.handles.status -> %s"\n', mode);
end

switch mode
    case 'selectWorkingDirectory'
        newPath = uigetdir(obj.handles.currentDirectory.Value, 'Choose directory');
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
