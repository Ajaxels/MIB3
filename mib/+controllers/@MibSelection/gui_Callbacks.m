function gui_Callbacks(obj, hWidget, hData)
% function gui_Callbacks(obj, hWidget, hData)
% callbacks for widgets of some the Segmentation panel obj.handles.panels.segmentation
%
% Parameters:
% hWidget: handle to the pressed widget
% hWidget.tag -> char, identifier the widget, used when the same operation
% is called from menu
% 'add' -> add selection to material/mask
% 'subtract' -> subtract selection from material/mask
% 'replace' -> replace material/mask using the current selection
% 'clear' -> clear selection
% 'fill' -> fill selection
% 'colChannel' -> select color channel
% 'applySegmentationIn3D' -> apply segmentation tools in 3D
% 'autoFillSelection' -> auto-fill selection
% 'preset1' -> apply preset 1 to the selected segmentation tool
% 'preset2' -> apply preset 2 to the selected segmentation tool
% 'preset3' -> apply preset 3 to the selected segmentation tool
% 'erode' -> edode selection
% 'dilate' -> dilate selection
% 'strel' -> set strel size for erosion/dilation
% 'differenceSelection' -> enable the differenceSelection mode for the dilate/erode
% 'lutColors' -> visualize image using LUT colors
% 'showModel' -> show model
% 'showMask' -> show mask
% 'showAnnotations' -> show annotations
% 'hideImage' -> hide image
% 'display' -> start image view settings dialog
% 'onFly' -> % automatically adjust contrast and brightness
% 'modelTransparency' -> define model transparency
% 'maskTransparency' -> define mask transparency
% 'selectionTransparency' -> define selection transparency
% 'help' -> show help
%
% hData: handle to supporting data class

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
        %fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s\n', mode);

    case 'preset2' % apply preset 2 to the selected segmentation tool
        %fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s\n', mode);

    case 'preset3' % apply preset 3 to the selected segmentation tool
        %fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s\n', mode);

    case 'erode' % erode selection
        obj.erodeSelection();
        
    case 'dilate' % dilate selection
        obj.dilateSelection();

    case 'strel' % set strel size for erosion/dilation
        %fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s -> %s\n', mode, hWidget.Value);

    case 'differenceSelection' % enable the differenceSelection mode for the dilate/erode
        % nothing is done yet
        % BatchOpt.Difference = checkboxOptions(obj.handles.differenceSelection.Value+1);
        % obj.selectionPanelCheckboxes(BatchOpt);

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
        %fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s\n', mode);

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

    case 'help'
        % help
end
end
