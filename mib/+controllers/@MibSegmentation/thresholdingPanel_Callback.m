function thresholdingPanel_Callback(obj, hWidget, hData)
% thresholdingPanel_Callback(obj, hWidget, hData)
% Callbacks for widgets in the Segmentation panel->Black and white thresholding tool
%
% Parameters:
% hWidget: handle to the pressed widget
% hWidget.Tag -> identifier the widget, used when the same operation is called from menu
% 'thresholdAdaptive' -> turn on the adaptive thresholding
% 'thresholdType' -> choose the thresholding type
% 'thresholdInvert' -> invert image for thresholding using the adaptive mode
% 'threshold3D' -> apply thresholding in 3D
% 'threshold4D' -> apply threhsolding in 4D
% 'thresholdLow' -> define the low threshold value using the slider
% 'thresholdHigh' -> define the low threshold value using the slider
% 'thresholdLowValue' -> define the low threshold value using the numeric edit field
% 'thresholdHighValue' -> define the high threshold value using the numeric edit field
% 'threshold' -> apply the thresholding operation
%
% hData: handle to supporting data class

arguments (Input)
    obj controllers.MibSegmentation
    hWidget {mustBeA(hWidget, {'matlab.ui.control.Button', 'matlab.ui.control.CheckBox', 'matlab.ui.control.Spinner', 'matlab.ui.container.ButtonGroup', 'matlab.ui.control.NumericEditField' 'matlab.ui.control.DropDown', 'matlab.ui.control.Slider'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData', 'matlab.ui.eventdata.SelectionChangedData', 'matlab.ui.eventdata.ValueChangingData'})}
end

mode = hWidget.Tag;

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSegmentation.thresholdingPanel_Callback: "obj.view.handles.panels.segmentation.handles.%s" -> changed/pressed\n', mode);
end

switch mode
    case 'thresholdAdaptive' % turn on the adaptive thresholding
        %fprintf('Clicked on a widget of the segmentation panel->Thresolding tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
        if hWidget.Value
            obj.view.handles.panels.segmentation.handles.thresholdType.Enable = 'on';
            obj.view.handles.panels.segmentation.handles.thresholdInvert.Enable = 'on';
        else
            obj.view.handles.panels.segmentation.handles.thresholdType.Enable = 'off';
            obj.view.handles.panels.segmentation.handles.thresholdInvert.Enable = 'off';
        end

    case 'thresholdType' % choose the thresholding type
        %fprintf('Clicked on a widget of the segmentation panel->Thresolding tool (obj.handles.panels.segmentation): %s -> %s\n', mode, hWidget.Value);
    case 'thresholdInvert' % invert image for thresholding using the adaptive mode
        %fprintf('Clicked on a widget of the segmentation panel->Thresolding tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'threshold3D' % apply threhsolding in 3D
        %fprintf('Clicked on a widget of the segmentation panel->Thresolding tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'threshold4D' % apply threhsolding in 4D
        %fprintf('Clicked on a widget of the segmentation panel->Thresolding tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'thresholdLow' % define the low threshold value using the slider
        %fprintf('Clicked on a widget of the segmentation panel->Thresolding tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'thresholdHigh' % define the high threshold value using the slider
        %fprintf('Clicked on a widget of the segmentation panel->Thresolding tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'thresholdLowValue' % define the low threshold value using the numeric edit field
        %fprintf('Clicked on a widget of the segmentation panel->Thresolding tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'thresholdHighValue' % define the high threshold value using the numeric edit field
        %fprintf('Clicked on a widget of the segmentation panel->Thresolding tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'threshold' % apply the thresholding operation
        %fprintf('Clicked on a widget of the segmentation panel->Thresolding tool (obj.handles.panels.segmentation): %s\n', mode);
end

end
