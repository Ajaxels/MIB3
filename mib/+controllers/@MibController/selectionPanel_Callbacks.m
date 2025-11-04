function selectionPanel_Callbacks(obj, hWidget, hData, mode)
% function selectionPanel_Callbacks(obj, hWidget, hData, mode)
% callbacks for widgets of some the Segmentation panel obj.handles.panels.segmentation
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting data class
% mode: char, optional identifier the widget, used when the same operation
% is called from menu, when empty or missing hWidget.Tag is used as an
% identifier
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


%

arguments (Input)
    obj controllers.MibController
    hWidget {mustBeA(hWidget, {'matlab.ui.control.Button', 'matlab.ui.control.CheckBox', 'matlab.ui.control.DropDown', 'matlab.ui.control.EditField', 'matlab.ui.control.Slider'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData', 'matlab.ui.eventdata.ValueChangingData'})}
    mode char = ''
end

if isempty(mode); mode = hWidget.Tag; end

switch mode
    case 'add' % add selection to material/mask
        fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s\n', mode);
    case 'subtract' % subtract selection from material/mask
        fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s\n', mode);
    case 'replace' % replace material/mask using the current selection
        fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s\n', mode);
    case 'clear' % clear selection
        fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s\n', mode);
    case 'fill' % fill selection
        fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s\n', mode);
    case 'colChannel' % select color channel
        fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s -> %s\n', mode, hWidget.Value);
    case 'apply3D' % apply segmentation tools in 3D
        fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s -> %d\n', mode, hWidget.Value);
    case 'autoFill' % auto-fill selection
        fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s -> %d\n', mode, hWidget.Value);
    case 'preset1' % apply preset 1 to the selected segmentation tool
        fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s\n', mode);
    case 'preset2' % apply preset 2 to the selected segmentation tool
        fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s\n', mode);
    case 'preset3' % apply preset 3 to the selected segmentation toolb
        fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s\n', mode);
    case 'erode' % edode selection
        fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s\n', mode);
    case 'dilate' % dilate selection
        fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s\n', mode);
    case 'strel' % set strel size for erosion/dilation
        fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s -> %s\n', mode, hWidget.Value);
    case 'difference' % enable the difference mode for the dilate/erode
        fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s -> %d\n', mode, hWidget.Value);
    case 'lutColors' % visualize image using LUT colors
        fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s -> %d\n', mode, hWidget.Value);
    case 'showModel' % show model
        fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s -> %d\n', mode, hWidget.Value);
    case 'showMask' % show mask
        fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s -> %d\n', mode, hWidget.Value);
    case 'showAnnotations' % show annotations
        fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s -> %d\n', mode, hWidget.Value);
    case 'hideImage' % hide image
        fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s -> %d\n', mode, hWidget.Value);
    case 'display' % start image view settings dialog
        fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s\n', mode);
    case 'onFly' % automatically adjust contrast and brightness
        fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s -> %d\n', mode, hWidget.Value);
    case 'modelTransparency' % define model transparency
        fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s -> %.3f\n', mode, hWidget.Value);
    case 'maskTransparency' % define mask transparency
        fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s -> %.3f\n', mode, hWidget.Value);
    case 'selectionTransparency' % define selection transparency
        fprintf('controller.selectionPanel_Callbacks: Clicked on a widget of the selection/view settings panel (obj.handles.panels.selection): %s -> %.3f\n', mode, hWidget.Value);
end
end