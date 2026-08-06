function dragPanel_Callback(obj, hWidget, hData)
% DRAGPANEL_CALLBACK - Callback for drag-and-drop materials tool widgets.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.dragPanel_Callback(hWidget, hData)
%
% Handles callbacks for drag-and-drop material movement tool widgets in the Segmentation panel.
% Supports layer selection, offset configuration, and directional material shifting.
%
% Input Arguments:
%   - **hWidget** - [matlab.ui.control.Button | matlab.ui.control.NumericEditField | matlab.ui.control.DropDown] pressed widget; operation identified via ``hWidget.Tag``:
%
%     - ``'dragLayer'`` - select target layer for drag-and-drop operation
%     - ``'dragValue'`` - set pixel offset for material shifting
%     - ``'dragUp'`` - shift layer upward (negative Y direction)
%     - ``'dragRight'`` - shift layer rightward (positive X direction)
%     - ``'dragLeft'`` - shift layer leftward (negative X direction)
%     - ``'dragDown'`` - shift layer downward (positive Y direction)
%
%   - **hData** - [matlab.ui.eventdata.ButtonPushedData | matlab.ui.eventdata.ValueChangedData] event data from widget
%
% Output Arguments:
%   None
%

arguments (Input)
    obj controllers.MibSegmentation
    hWidget {mustBeA(hWidget, {'matlab.ui.control.Button', 'matlab.ui.control.NumericEditField' 'matlab.ui.control.DropDown'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData'})}
end

mode = hWidget.Tag;

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSegmentation.dragPanel_Callback: "obj.view.handles.panels.segmentation.handles.%s" -> changed/pressed\n', mode);
end

switch mode
    case 'dragLayer' % select MIB layout to apply the drag-and-drop operation
        %fprintf('Clicked on a widget of the segmentation panel->Drag-and-drop materials tool (obj.handles.panels.segmentation): %s -> %s\n', mode, hWidget.Value);
    case 'dragValue' % define the value for shifting materials
        %fprintf('Clicked on a widget of the segmentation panel->Drag-and-drop materials tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'dragUp' % shift the layer towards up-direction
        stepVal = obj.handles.dragValue.Value;
        dragMode = '2D, Slice';
        if obj.mibModel.applySegmentationIn3D; dragMode = '3D, Stack'; end
        obj.mibModel.backup(obj.handles.dragLayer.Value, obj.mibModel.applySegmentationIn3D);
        obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.gui_WindowButtonUpDragAndDropFcn(dragMode, 0, -stepVal);
    case 'dragRight' % shift the layer towards right-direction
        stepVal = obj.handles.dragValue.Value;
        dragMode = '2D, Slice';
        if obj.mibModel.applySegmentationIn3D; dragMode = '3D, Stack'; end
        obj.mibModel.backup(obj.handles.dragLayer.Value, obj.mibModel.applySegmentationIn3D);
        obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.gui_WindowButtonUpDragAndDropFcn(dragMode, stepVal, 0);
    case 'dragLeft' % shift the layer towards left-direction
        stepVal = obj.handles.dragValue.Value;
        dragMode = '2D, Slice';
        if obj.mibModel.applySegmentationIn3D; dragMode = '3D, Stack'; end
        obj.mibModel.backup(obj.handles.dragLayer.Value, obj.mibModel.applySegmentationIn3D);
        obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.gui_WindowButtonUpDragAndDropFcn(dragMode, -stepVal, 0);
    case 'dragDown' % shift the layer towards down-direction
        stepVal = obj.handles.dragValue.Value;
        dragMode = '2D, Slice';
        if obj.mibModel.applySegmentationIn3D; dragMode = '3D, Stack'; end
        obj.mibModel.backup(obj.handles.dragLayer.Value, obj.mibModel.applySegmentationIn3D);
        obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.gui_WindowButtonUpDragAndDropFcn(dragMode, 0, stepVal);
end

end
