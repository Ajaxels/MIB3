function gui_Callbacks(obj, hWidget, hData)
% GUI_CALLBACKS - callbacks for widgets of some the Fiji Connect panel obj.view.handles.panels.roi (obj.cRoi.gui).
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.gui_Callbacks(hWidget, hData)
%
% Input Arguments:
%   - **hWidget** — handle to the pressed widget
%   - **hData** — handle to supporting data class
%

% mode: char, optional identifier the widget, used when the same operation
% is called from menu, when empty or missing hWidget.Tag is used as an
% identifier
% 'startFijiButton' -> start Fiji.app
% 'stopFijiButton' -> stop Fiji.app
% 'exportButton' -> Export dataset to Fiji
% 'importButton' -> Import dataset from Fiji
% 'selectFileButton' -> select file with a list of macros
% 'runButton' -> run the macro command or execute the file
% 'helpButton' -> show help

arguments (Input)
    obj controllers.MibFijiConnect
    hWidget {mustBeA(hWidget, {'matlab.ui.control.Button', 'matlab.ui.control.CheckBox', 'matlab.ui.control.DropDown', 'matlab.ui.control.EditField', 'matlab.ui.control.ListBox', 'matlab.ui.control.Spinner'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData'})}
    %mode char = ''
end

% mode = '';
% if isempty(mode); mode = hWidget.Tag; end

mode = hWidget.Tag;

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibFijiConnect.gui_Callbacks: "obj.handles.%s"-> pressed/changed\n', mode);
end

%dataset = obj.mibModel.I{obj.mibModel.id};
switch mode
    case 'startFijiButton' %
        utils.fiji.startFiji();
    case 'stopFijiButton' %
        utils.fiji.stopFiji();
    case 'exportButton' %
        obj.exportToFiji();
    case 'importButton' %
        obj.importFromFiji();
    case 'selectFileButton' %
        [filename, filePath] = uigetfile( ...
            {'*.txt', 'Text file (*.txt)'; '*.*', 'All Files (*.*)'}, ...
            'Select file...', obj.mibModel.mibPath);
        if isequal(filename, 0); return; end
        obj.handles.macroText.Value = fullfile(filePath, filename);

    case 'runButton' %
        obj.runMacro();
        
    case 'helpButton' %
        helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'panels', 'fijiconnect', 'index.html');
        if isfile(helpFilPath)
            web(helpFilPath, '-browser');
        else
            web('http://mib.helsinki.fi/help/main3/user-interface/panels/fijiconnect/index.html', '-browser');
        end

end

end
