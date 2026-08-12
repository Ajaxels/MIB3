function gui_Callbacks(obj, hWidget, hData)
% GUI_CALLBACKS - callbacks for widgets of some the Segmentation panel obj.handles.panels.segmentation.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.gui_Callbacks(hWidget, hData)
%
% Input Arguments:
%   - **hWidget** - [Button|CheckBox|DropDown|EditField|Slider] pressed widget with ``.Tag`` property identifying the action:
%
%     - ``'add'`` - add selection to material/mask
%     - ``'subtract'`` - subtract selection from material/mask
%     - ``'replace'`` - replace material/mask using current selection
%     - ``'clear'`` - clear selection
%     - ``'fill'`` - fill selection
%     - ``'colChannel'`` - select color channel
%     - ``'applySegmentationIn3D'`` - apply segmentation tools in 3D
%     - ``'autoFillSelection'`` - auto-fill selection
%     - ``'preset1'`` - apply preset 1 to selected segmentation tool
%     - ``'preset2'`` - apply preset 2 to selected segmentation tool
%     - ``'preset3'`` - apply preset 3 to selected segmentation tool
%     - ``'erode'`` - erode selection
%     - ``'dilate'`` - dilate selection
%     - ``'strel'`` - set strel size for erosion/dilation
%     - ``'differenceSelection'`` - enable difference mode for dilate/erode
%     - ``'lutColors'`` - visualize image using LUT colors
%     - ``'showModel'`` - show model layer
%     - ``'showMask'`` - show mask layer
%     - ``'showAnnotations'`` - show annotations
%     - ``'hideImage'`` - hide image
%     - ``'display'`` - start image view settings dialog
%     - ``'onFly'`` - automatically adjust contrast and brightness
%     - ``'modelTransparency'`` - adjust model transparency
%     - ``'maskTransparency'`` - adjust mask transparency
%     - ``'selectionTransparency'`` - adjust selection transparency
%     - ``'help'`` - show help
%
%   - **hData** - [ValueChangedData|ValueChangingData|ButtonPushedData] event data from widget callback
%

arguments (Input)
    obj controllers.MibSelection
    hWidget {mustBeA(hWidget, {'matlab.ui.control.Button', 'matlab.ui.control.CheckBox', 'matlab.ui.control.DropDown', 'matlab.ui.control.EditField', 'matlab.ui.control.Slider'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData', 'matlab.ui.eventdata.ValueChangingData'})}
end

mode = hWidget.Tag;

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSelection.gui_Callbacks: "obj.view.handles.panels.selection.handles.%s" -> changed/pressed\n', mode);
end

% define options for checkboxes
checkboxOptions = {'Unchecked', 'Checked'};

switch mode
    case 'add' % add selection to material/mask
        obj.selectionActions('add');
    case 'subtract' % subtract selection from material/mask
        obj.selectionActions('subtract');
    case 'replace' % replace material/mask using the current selection
        obj.selectionActions('replace');
    case 'clear' % clear selection
        obj.clearSelection();
    case 'fill' % fill selection
        obj.fillSelection();
    case 'colChannel' % select color channel
        % get selected color channel as string, where 0 is all channels
        BatchOpt.ColorChannel = num2str(obj.handles.colChannel.ValueIndex-1);
        obj.selectionPanelCheckboxes(BatchOpt);

    case 'applySegmentationIn3D' % apply segmentation tools in 3D
        BatchOpt.Apply3D = checkboxOptions(obj.handles.applySegmentationIn3D.Value+1);
        obj.selectionPanelCheckboxes(BatchOpt);

    case 'autoFillSelection' % auto-fill selection
        BatchOpt.AutoFillSelection = checkboxOptions(obj.handles.autoFillSelection.Value+1);
        obj.selectionPanelCheckboxes(BatchOpt);

    case 'preset1' % apply preset 1 to the selected segmentation tool
        if any(strcmp(obj.UIFigure.CurrentModifier, 'shift')) %any(strcmp(obj.mibController.currentModifier, 'shift'))
            obj.updateSegmentationPreset(1);
        else
            obj.updateSettingsFromPreset(1);
        end
    case 'preset2' % apply preset 2 to the selected segmentation tool
        if any(strcmp(obj.UIFigure.CurrentModifier, 'shift'))
            obj.updateSegmentationPreset(2);
        else
            obj.updateSettingsFromPreset(2);
        end
    case 'preset3' % apply preset 3 to the selected segmentation tool
        if any(strcmp(obj.UIFigure.CurrentModifier, 'shift'))
            obj.updateSegmentationPreset(3);
        else
            obj.updateSettingsFromPreset(3);
        end

    case 'erode' % erode selection
        obj.erodeSelection();
        
    case 'dilate' % dilate selection
        obj.dilateSelection();

    case 'strel' % set strel size for erosion/dilation
        %fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s -> %s\n', mode, hWidget.Value);

    case 'differenceSelection' % enable the differenceSelection mode for the dilate/erode
        BatchOpt.DifferenceSelection = checkboxOptions(obj.handles.differenceSelection.Value+1);
        obj.selectionPanelCheckboxes(BatchOpt);

    case 'lutColors' % visualize image using LUT colors
        obj.mibModel.I{obj.mibModel.id}.useLUT = obj.handles.lutColors.Value;
        % ADD MORE FROM mibLutCheckbox_Callback in MIB2
        obj.lutTable_update_fromModel();
        notify(obj.mibModel, 'ShowImage');

    case 'showModel' % show model
        obj.mibModel.showModel = obj.handles.showModel.Value;
        notify(obj.mibModel, 'ShowImage');

    case 'showMask' % show mask
        obj.mibModel.showMask = obj.handles.showMask.Value;
        notify(obj.mibModel, 'ShowImage');

    case 'showAnnotations' % show annotations
        BatchOpt.ShowAnnotations = checkboxOptions(obj.handles.showAnnotations.Value+1);
        obj.selectionPanelCheckboxes(BatchOpt);

    case 'hideImage' % hide image
        BatchOpt.HideImage = checkboxOptions(obj.handles.hideImage.Value+1);
        obj.selectionPanelCheckboxes(BatchOpt);

    case 'display' % start image view settings dialog
        %obj.mibController.startController('controllers.DisplayAdjust');
        utils.startController(obj.mibController, 'controllers.DisplayAdjust');

    case 'onFly' % automatically adjust contrast and brightness
        BatchOpt.OnFly = checkboxOptions(obj.handles.onFly.Value+1);
        obj.selectionPanelCheckboxes(BatchOpt);

    case 'modelTransparency' % define model transparency
        obj.mibModel.preferences.Colors.ModelTransparency = hData.Value;
        notify(obj.mibModel, 'ShowImage');

    case 'maskTransparency' % define mask transparency
        obj.mibModel.preferences.Colors.MaskTransparency = hData.Value;
        notify(obj.mibModel, 'ShowImage');

    case 'selectionTransparency' % define selection transparency
        obj.mibModel.preferences.Colors.SelectionTransparency = hData.Value;
        notify(obj.mibModel, 'ShowImage');

    case 'help'        % help
        helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'panels', 'selection_imview', 'index.html');
        utils.openHelpPage(helpFilPath, 'http://mib.helsinki.fi/help/main3/user-interface/panels/selection_imview/index.html');
end
end
