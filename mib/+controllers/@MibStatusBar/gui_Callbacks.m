function gui_Callbacks(obj, hWidget, hData)
% function gui_Callbacks(obj, hWidget, hData)
% callbacks for widgets of some the Status bar obj.handles.status
%
% Parameters:
% hWidget: handle to the pressed widget
% hWidget.tag -> char, identifier the widget
%
% hData: handle to supporting data class

arguments (Input)
    obj controllers.MibStatusBar
    hWidget {mustBeA(hWidget, {'matlab.ui.internal.toolstrip.base.Action'})}
    hData {mustBeA(hData, {'matlab.ui.internal.toolstrip.base.ToolstripEventData'})}
end

mode = hWidget.Description;

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibStatusBar.gui_Callbacks: "obj.view.handles.status -> %s"\n', mode);
end

switch mode
    case 'Use the system directory selection dialog to define the working directory'
        newPath = uigetdir(obj.handles.currentDirectory.Value, 'Choose Directory');
        if newPath == 0; return; end

    case 'Enter the working directory'
        % update obj.mibModel.myPath variable
        currentPath = obj.handles.currentDirectory.Value;
        % get fileparts to clip filename from the path keeping only the
        % directory name
        [filepath, ~, fext] = fileparts(currentPath);
        if ~isempty(fext)
            currentPath = filepath; 
        end

    case 'Copy the current working directory to clipboard'
        clipboard('copy', obj.handles.currentDirectory.Value);
    case 'Open the current working directory in a system file browser'
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
    case 'Define the zoom level'
end

end