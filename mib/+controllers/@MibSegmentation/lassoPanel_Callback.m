function lassoPanel_Callback(obj, hWidget, hData)
% LASSOPANEL_CALLBACK - lassoPanel_Callback(obj, hWidget, hData).
%
% Syntax:
%   function lassoPanel_Callback(obj, hWidget, hData)
%
% Callbacks for widgets in the Segmentation panel->Lasso/Object picker tools
%
% Input Arguments:
%   - **hWidget** — handle to the pressed widget
%     hWidget.Tag - identifier the widget, used when the same operation is called from menu
%     'lassoType' define type of the lasso selection tool
%     'lassoMode' set the mode add/remove lasso-selection to/from the selection layer
%     'lassoManually' specify the lasso area manually
%     'lassoSelect' select the specified area
%     'lassoX1' define min-X value for the manual lasso placement
%     'lassoY1' define min-Y value for the manual lasso placement
%     'lassoWidth' define width value for the manual lasso placement
%     'lassoHeight' define height value for the manual lasso placement
%     'objectRecalculate' recalculate object properties for 3D selection
%
%   - **hData** — handle to supporting data class
%

arguments (Input)
    obj controllers.MibSegmentation
    hWidget {mustBeA(hWidget, {'matlab.ui.control.Button', 'matlab.ui.control.CheckBox', 'matlab.ui.control.NumericEditField' 'matlab.ui.control.DropDown'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData'})}
end

mode = hWidget.Tag;

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSegmentation.lassoPanel_Callback: "obj.view.handles.panels.segmentation.handles.%s" -> changed/pressed\n', mode);
end

switch mode
    case 'lassoType' % define type of the lasso selection tool
        % store the current selection of the widget as it is shared between few tools
        switch obj.handles.segmTool.Value
            case 'Lasso'
                hWidget.UserData.lassoTypeIndex = hWidget.ValueIndex;
            case 'Object picker'
                hWidget.UserData.objectPickerTypeIndex = hWidget.ValueIndex;
        end
    case 'lassoMode' % set the mode add/remove lasso-selection to/from the selection layer
        % store the current selection of the widget as it is shared between few tools
        switch obj.handles.segmTool.Value
            case 'Lasso'
                hWidget.UserData.lassoModeIndex = hWidget.ValueIndex;
            case 'Object picker'
                hWidget.UserData.objectPickerModeIndex = hWidget.ValueIndex;
        end
    case 'lassoManually' % specify the lasso area manually
        %fprintf('Clicked on a widget of the segmentation panel->Lasso/Object picker tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
        if obj.view.handles.panels.segmentation.handles.lassoManually.Value
            obj.view.handles.panels.segmentation.handles.lassoX1.Enable = 'on';
            obj.view.handles.panels.segmentation.handles.lassoY1.Enable = 'on';
            obj.view.handles.panels.segmentation.handles.lassoSelect.Enable = 'on';
            obj.view.handles.panels.segmentation.handles.lassoWidth.Enable = 'on';
            obj.view.handles.panels.segmentation.handles.lassoHeight.Enable = 'on';
        else
            obj.view.handles.panels.segmentation.handles.lassoX1.Enable = 'off';
            obj.view.handles.panels.segmentation.handles.lassoY1.Enable = 'off';
            obj.view.handles.panels.segmentation.handles.lassoSelect.Enable = 'off';
            obj.view.handles.panels.segmentation.handles.lassoWidth.Enable = 'off';
            obj.view.handles.panels.segmentation.handles.lassoHeight.Enable = 'off';
        end
    case 'lassoSelect' % select the specified area
        modifier = '';
        lassoMode = obj.handles.lassoMode.Value;
        if strcmp(lassoMode, 'Subtract')
            modifier = 'control';
        end
        obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.segmentationLassoManual(modifier);
    case 'lassoX1' % define min-X value for the manual lasso placement
        %fprintf('Clicked on a widget of the segmentation panel->Lasso/Object picker tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'lassoY1' % define min-X value for the manual lasso placement
        %fprintf('Clicked on a widget of the segmentation panel->Lasso/Object picker tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'lassoWidth' % define width value for the manual lasso placement
        %fprintf('Clicked on a widget of the segmentation panel->Lasso/Object picker tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'lassoHeight' % define height value for the manual lasso placement
        %fprintf('Clicked on a widget of the segmentation panel->Lasso/Object picker tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'objectRecalculate' % recalculate object properties for 3D selection
        obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.recalculateObjects();
end

end

