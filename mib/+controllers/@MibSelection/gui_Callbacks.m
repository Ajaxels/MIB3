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
% 'apply3D' -> apply segmentation tools in 3D
% 'autoFill' -> auto-fill selection
% 'preset1' -> apply preset 1 to the selected segmentation tool
% 'preset2' -> apply preset 2 to the selected segmentation tool
% 'preset3' -> apply preset 3 to the selected segmentation tool
% 'erode' -> edode selection
% 'dilate' -> dilate selection
% 'strel' -> set strel size for erosion/dilation
% 'difference' -> enable the difference mode for the dilate/erode
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

switch mode
    case 'add' % add selection to material/mask
        %fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s\n', mode);
    case 'subtract' % subtract selection from material/mask
        %fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s\n', mode);
    case 'replace' % replace material/mask using the current selection
        %fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s\n', mode);
    case 'clear' % clear selection
        %fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s\n', mode);
    case 'fill' % fill selection
        %fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s\n', mode);
    case 'colChannel' % select color channel
        %fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s -> %s\n', mode, hWidget.Value);
    case 'apply3D' % apply segmentation tools in 3D
        %fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s -> %d\n', mode, hWidget.Value);
    case 'autoFill' % auto-fill selection
        %fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s -> %d\n', mode, hWidget.Value);
    case 'preset1' % apply preset 1 to the selected segmentation tool
        %fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s\n', mode);
    case 'preset2' % apply preset 2 to the selected segmentation tool
        %fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s\n', mode);
    case 'preset3' % apply preset 3 to the selected segmentation tool
        %fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s\n', mode);
    case 'erode' % edode selection
        %fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s\n', mode);
    case 'dilate' % dilate selection
        %fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s\n', mode);
    case 'strel' % set strel size for erosion/dilation
        %fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s -> %s\n', mode, hWidget.Value);
    case 'difference' % enable the difference mode for the dilate/erode
        %fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s -> %d\n', mode, hWidget.Value);
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
        obj.mibModel.showAnnotations = obj.handles.showAnnotations.Value;
        notify(obj.mibModel, 'ShowImage');
    case 'hideImage' % hide image
        obj.mibModel.hideImage = obj.handles.hideImage.Value;
        notify(obj.mibModel, 'ShowImage');
    case 'display' % start image view settings dialog
        %fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s\n', mode);
    case 'onFly' % automatically adjust contrast and brightness
        obj.mibModel.onFlyImageStretch = obj.handles.onFly.Value;
        notify(obj.mibModel, 'ShowImage');
    case 'modelTransparency' % define model transparency
        obj.mibModel.preferences.Colors.ModelTransparency = obj.handles.modelTransparency.Value;
        notify(obj.mibModel, 'ShowImage');
    case 'maskTransparency' % define mask transparency
        obj.mibModel.preferences.Colors.MaskTransparency = obj.handles.maskTransparency.Value;
        notify(obj.mibModel, 'ShowImage');
    case 'selectionTransparency' % define selection transparency
        obj.mibModel.preferences.Colors.SelectionTransparency = obj.handles.selectionTransparency.Value;
        notify(obj.mibModel, 'ShowImage');
    case 'help'
        % help
end
end
