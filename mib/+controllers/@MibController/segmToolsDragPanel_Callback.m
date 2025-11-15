function segmToolsDragPanel_Callback(obj, hWidget, hData, mode)
% segmToolsDragPanel_Callback(obj, hWidget, hData, mode)
% Callbacks for widgets in the Segmentation panel->Drag-and-drop materials tool
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting data class
% mode: char, optional identifier the widget, used when the same operation
% is called from menu, when empty or missing hWidget.Tag is used as an identifier
% 'dragLayer' -> select MIB layout to apply the drag-and-drop operation
% 'dragValue' -> define the value for shifting materials
% 'dragUp' -> shift the layer towards up-direction
% 'dragRight' -> shift the layer towards right-direction
% 'dragLeft' -> shift the layer towards left-direction
% 'dragDown' -> shift the layer towards down-direction
%

arguments (Input)
    obj controllers.MibController
    hWidget {mustBeA(hWidget, {'matlab.ui.control.Button', 'matlab.ui.control.NumericEditField' 'matlab.ui.control.DropDown'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData'})}
    mode char = ''
end

if isempty(mode); mode = hWidget.Tag; end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibController.segmToolsDragPanel_Callback: "obj.view.handles.panels.segmentation.handles.%s" -> changed/pressed\n', mode);
end

switch mode
    case 'dragLayer' % select MIB layout to apply the drag-and-drop operation
        %fprintf('Clicked on a widget of the segmentation panel->Drag-and-drop materials tool (obj.handles.panels.segmentation): %s -> %s\n', mode, hWidget.Value);
    case 'dragValue' % define the value for shifting materials
        %fprintf('Clicked on a widget of the segmentation panel->Drag-and-drop materials tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'dragUp' % shift the layer towards up-direction
        %fprintf('Clicked on a widget of the segmentation panel->Drag-and-drop materials tool (obj.handles.panels.segmentation): %s\n', mode);
    case 'dragRight' % shift the layer towards right-direction
        %fprintf('Clicked on a widget of the segmentation panel->Drag-and-drop materials tool (obj.handles.panels.segmentation): %s\n', mode);
    case 'dragLeft' % shift the layer towards left-direction
        %fprintf('Clicked on a widget of the segmentation panel->Drag-and-drop materials tool (obj.handles.panels.segmentation): %s\n', mode);
    case 'dragDown' % shift the layer towards down-direction
        %fprintf('Clicked on a widget of the segmentation panel->Drag-and-drop materials tool (obj.handles.panels.segmentation): %s\n', mode);
end

end
