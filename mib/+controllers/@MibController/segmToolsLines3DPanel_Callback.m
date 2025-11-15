function segmToolsLines3DPanel_Callback(obj, hWidget, hData, mode)
% segmToolsLines3DPanel_Callback(obj, hWidget, hData, mode)
% Callbacks for widgets in the Segmentation panel->3D lines tool
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting data class
% mode: char, optional identifier the widget, used when the same operation
% is called from menu, when empty or missing hWidget.Tag is used as an identifier
% 'linesTableView' -> open a dialog with tables showing line edges and vertices
% 'linesShowLines' -> show or hide the 3D lines
% 'linesClick' -> define the default operation on mouse click
% 'linesShiftClick' -> define the default operation on Shift+mouse click
% 'linesCtrlClick' -> define the default operation on Ctrl+mouse click
% 'linesAltClick' -> define the default operation on Alt+mouse click
%

arguments (Input)
    obj controllers.MibController
    hWidget {mustBeA(hWidget, {'matlab.ui.control.Button', 'matlab.ui.control.CheckBox', 'matlab.ui.control.DropDown'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData'})}
    mode char = ''
end

if isempty(mode); mode = hWidget.Tag; end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibController.segmToolsLines3DPanel_Callback: "obj.view.handles.panels.segmentation.handles.%s" -> changed/pressed\n', mode);
end

switch mode
    case 'linesTableView' % open a dialog with tables showing line edges and vertices
        %fprintf('Clicked on a widget of the segmentation panel->3D lines tool (obj.handles.panels.segmentation): %s\n', mode);
    case 'linesShowLines' % show or hide the 3D lines
        %fprintf('Clicked on a widget of the segmentation panel->3D lines tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'linesClick' % define the default operation on mouse click
        %fprintf('Clicked on a widget of the segmentation panel->3D lines tool (obj.handles.panels.segmentation): %s -> %s\n', mode, hWidget.Value);
    case 'linesShiftClick' % define the default operation on Shift+mouse click
        %fprintf('Clicked on a widget of the segmentation panel->3D lines tool (obj.handles.panels.segmentation): %s -> %s\n', mode, hWidget.Value);
    case 'linesCtrlClick' % define the default operation on Ctrl+mouse click
        %fprintf('Clicked on a widget of the segmentation panel->3D lines tool (obj.handles.panels.segmentation): %s -> %s\n', mode, hWidget.Value);
    case 'linesAltClick' % define the default operation on Alt+mouse click
        %fprintf('Clicked on a widget of the segmentation panel->3D lines tool (obj.handles.panels.segmentation): %s -> %s\n', mode, hWidget.Value);
end

end
