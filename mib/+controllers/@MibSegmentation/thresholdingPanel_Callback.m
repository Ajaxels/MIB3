function thresholdingPanel_Callback(obj, hWidget, hData)
% THRESHOLDINGPANEL_CALLBACK - Callback for black and white thresholding tool widgets.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.thresholdingPanel_Callback(hWidget, hData)
%
% Handles callbacks for black and white thresholding segmentation tool widgets in the Segmentation panel.
% Supports adaptive and global thresholding modes, threshold value adjustment, and multi-dimensional processing.
%
% Input Arguments:
%   - **hWidget** - [matlab.ui.control.Button | matlab.ui.control.CheckBox | matlab.ui.control.Spinner | matlab.ui.container.ButtonGroup | matlab.ui.control.NumericEditField | matlab.ui.control.DropDown | matlab.ui.control.Slider] pressed widget; operation identified via ``hWidget.Tag``:
%
%     - ``'thresholdAdaptive'`` - enable/disable adaptive thresholding mode
%     - ``'thresholdType'`` - select thresholding algorithm (global, adaptive, etc.)
%     - ``'thresholdInvert'`` - invert image before thresholding in adaptive mode
%     - ``'threshold3D'`` - apply thresholding to all Z slices (3D mode)
%     - ``'threshold4D'`` - apply thresholding to all Z and T dimensions (4D mode)
%     - ``'thresholdLow'`` - adjust low threshold value using slider
%     - ``'thresholdHigh'`` - adjust high threshold value using slider
%     - ``'thresholdLowValue'`` - set low threshold value numerically
%     - ``'thresholdHighValue'`` - set high threshold value numerically
%     - ``'threshold'`` - execute the thresholding operation
%
%   - **hData** - [matlab.ui.eventdata.ButtonPushedData | matlab.ui.eventdata.ValueChangedData | matlab.ui.eventdata.ValueChangingData | matlab.ui.eventdata.SelectionChangedData] event data from widget
%
% Output Arguments:
%   None
%

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
        obj.refreshThresholdSliderUpdateMode();
    case 'threshold4D' % apply threhsolding in 4D
        %fprintf('Clicked on a widget of the segmentation panel->Thresolding tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
        obj.refreshThresholdSliderUpdateMode();

    case 'thresholdLow' % define the low threshold value using the slider
        % use hData.Value instead of obj.view.handles.panels.segmentation.handles.thresholdLowValue.Value
        % to make the update interactive; round to the configured step
        val = round(hData.Value / obj.thresholdSliderStep) * obj.thresholdSliderStep;
        obj.view.handles.panels.segmentation.handles.thresholdLowValue.Value = val;
        % interactive 2D thresholding on slider drag (skip backup/drawnow/batch)
        obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.segmentBlackWhiteThreshold();
    case 'thresholdHigh' % define the high threshold value using the slider
        % use hData.Value instead of obj.view.handles.panels.segmentation.handles.thresholdHighValue.Value
        % to make the update interactive; round to the configured step
        val = round(hData.Value / obj.thresholdSliderStep) * obj.thresholdSliderStep;
        obj.view.handles.panels.segmentation.handles.thresholdHighValue.Value = val;
        % interactive 2D thresholding on slider drag (skip backup/drawnow/batch)
        obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.segmentBlackWhiteThreshold();
    case 'thresholdLowValue' % define the low threshold value using the numeric edit field
        obj.view.handles.panels.segmentation.handles.thresholdLow.Value = hWidget.Value;
        % interactive 2D thresholding on value change (skip backup/drawnow/batch)
        obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.segmentBlackWhiteThreshold();
    case 'thresholdHighValue' % define the high threshold value using the numeric edit field
        obj.view.handles.panels.segmentation.handles.thresholdHigh.Value = hWidget.Value;
        % interactive 2D thresholding on value change (skip backup/drawnow/batch)
        obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.segmentBlackWhiteThreshold();
    case 'threshold' % apply the thresholding operation (uses 3D/4D if checkboxes are set)
        obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.segmentBlackWhiteThreshold();
end

end
