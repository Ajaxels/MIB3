function gui_Callbacks(obj, mode)
% function gui_Callbacks(obj, mode)
% callbacks for widgets of some the Status bar obj.handles.status
%
% Parameters:
% hWidget: handle to the pressed widget
% hWidget.tag -> char, identifier the widget
% 
%
% hData: handle to supporting data class

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
end

end