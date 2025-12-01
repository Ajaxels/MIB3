function brushPanel_Callback(obj, hWidget, hData)
% brushPanel_Callback(obj, hWidget, hData)
% Callbacks for widgets in the Segmentation panel->Brush/3D ball/Spot tool
%
% Parameters:
% hWidget: handle to the pressed widget
% hWidget.Tag -> identifier the widget, used when the same operation
% is called from menu, when empty or missing hWidget.Tag is used as an identifier
% 'brushRadius' -> change of the brush size
% 'eraserFactor' -> change of the eraser magnifier factor
% 'interpolationSettings' -> set the interpolation settings
% 'brushUseClustering' -> selection of the clustering mode
% 'clustersPar1' -> clustering mode parameter 1:
% 'clustersPar2' -> clustering mode parameter 2:
%
% hData: handle to supporting data class

arguments (Input)
    obj controllers.MibSegmentationController
    hWidget {mustBeA(hWidget, {'matlab.ui.control.Button', 'matlab.ui.control.CheckBox', 'matlab.ui.control.Spinner', 'matlab.ui.container.ButtonGroup', 'matlab.ui.control.NumericEditField'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData', 'matlab.ui.eventdata.SelectionChangedData'})}
end

mode = hWidget.Tag;

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSegmentationController.brushPanel_Callback: "obj.view.handles.panels.segmentation.handles.%s" -> changed/pressed\n', mode);
end

switch mode
    case 'brushRadius' % change of the brush size
        %fprintf('Clicked on a widget of the segmentation panel->Brush/3D ball/Spot tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'eraserFactor' % change of the eraser magnifier factor
        %fprintf('Clicked on a widget of the segmentation panel->Brush/3D ball/Spot tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'interpolationSettings' % set the interpolation settings
        %fprintf('Clicked on a widget of the segmentation panel->Brush/3D ball/Spot tool (obj.handles.panels.segmentation): %s\n', mode);
    case 'brushUseClustering' % selection of the clustering mode
        switch hWidget.SelectedObject.Text
            case 'No clusters'

            case 'Watershed'

            case 'SLIC'

        end
        %fprintf('Clicked on a widget of the segmentation panel->Brush/3D ball/Spot tool (obj.handles.panels.segmentation): %s -> %s\n', mode, hWidget.SelectedObject.Text);
    case 'clustersPar1' % clustering mode paramter 1:
        %fprintf('Clicked on a widget of the segmentation panel->Brush/3D ball/Spot tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'clustersPar2' % clustering mode parameter 2:
        %fprintf('Clicked on a widget of the segmentation panel->Brush/3D ball/Spot tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
end

end