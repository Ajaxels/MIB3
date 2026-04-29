function lines3DPanel_Callback(obj, hWidget, hData)
% LINES3DPANEL_CALLBACK - lines3DPanel_Callback(obj, hWidget, hData).
%
% Syntax:
%   function lines3DPanel_Callback(obj, hWidget, hData)
%
% Callbacks for widgets in the Segmentation panel->3D lines tool
%
% Input Arguments:
%   - **hWidget** — handle to the pressed widget
%     hWidget.Tag identifier the widget, used when the same operation
%     is called from menu, when empty or missing hWidget.Tag is used as an identifier
%     'linesTableView' open a dialog with tables showing line edges and vertices
%     'linesShowLines' show or hide the 3D lines
%     'linesClick' define the default operation on mouse click
%     'linesShiftClick' define the default operation on Shift+mouse click
%     'linesCtrlClick' define the default operation on Ctrl+mouse click
%     'linesAltClick' define the default operation on Alt+mouse click
%
%   - **hData** — handle to supporting data class
%

arguments (Input)
    obj controllers.MibSegmentation
    hWidget {mustBeA(hWidget, {'matlab.ui.control.Button', 'matlab.ui.control.CheckBox', 'matlab.ui.control.DropDown'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData'})}
end

mode = hWidget.Tag;

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSegmentation.lines3DPanel_Callback: "obj.view.handles.panels.segmentation.handles.%s" -> changed/pressed\n', mode);
end

switch mode
    case 'linesTableView' % open a dialog with tables showing line edges and vertices
        obj.mibController.startController('controllers.Lines3dDialog');
    case 'linesShowLines' % show or hide the 3D lines
        obj.mibModel.showLines3D = hWidget.Value;
        notify(obj.mibModel, 'ShowImage');
        focus(obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.figureDoc.Figure);  % remove focus from hObject
    case 'linesClick' % define the default operation on mouse click
        focus(obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.figureDoc.Figure);  % remove focus from hObject
    case 'linesShiftClick' % define the default operation on Shift+mouse click
        focus(obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.figureDoc.Figure);  % remove focus from hObject
    case 'linesCtrlClick' % define the default operation on Ctrl+mouse click
        focus(obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.figureDoc.Figure);  % remove focus from hObject
    case 'linesAltClick' % define the default operation on Alt+mouse click
        focus(obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.figureDoc.Figure);  % remove focus from hObject
end
end
