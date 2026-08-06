function lines3DPanel_Callback(obj, hWidget, hData)
% LINES3DPANEL_CALLBACK - Callback for 3D lines tool widgets.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.lines3DPanel_Callback(hWidget, hData)
%
% Handles callbacks for 3D line drawing and editing tool widgets in the Segmentation panel.
% Supports line visualization, table management, and mouse interaction mode configuration.
%
% Input Arguments:
%   - **hWidget** - [matlab.ui.control.Button | matlab.ui.control.CheckBox | matlab.ui.control.DropDown] pressed widget; operation identified via ``hWidget.Tag``:
%
%     - ``'linesTableView'`` - open line vertices and edges table dialog
%     - ``'linesShowLines'`` - toggle 3D lines visibility in image
%     - ``'linesClick'`` - set action for left-click (add node, delete, etc.)
%     - ``'linesShiftClick'`` - set action for Shift+left-click
%     - ``'linesCtrlClick'`` - set action for Ctrl+left-click
%     - ``'linesAltClick'`` - set action for Alt+left-click
%
%   - **hData** - [matlab.ui.eventdata.ButtonPushedData | matlab.ui.eventdata.ValueChangedData] event data from widget
%
% Output Arguments:
%   None
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
