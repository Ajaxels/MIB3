function segmentationPanel_Callbacks(obj, hWidget, hData, mode)
% function segmentationPanel_Callbacks(obj, hWidget, hData, mode)
% callbacks for widgets of some the Segmentation panel obj.handles.panels.segmentation
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting data class
% mode: char, optional identifier the widget, used when the same operation
% is called from menu, when empty or missing hWidget.Tag is used as an
% identifier
% 'createModel' -> create a new segmentation model
% 'loadModel' -> load model from a file
% 'addMaterial' -> add material to the model
% 'removeMaterial' -> remove material from the model
% 'colorWheel' -> restore default color scheme or generate random colors for 65535+ models
% 'viewSettings' -> view visualization settings for model/mask visualization
%

arguments (Input)
    obj controllers.MibController
    hWidget {mustBeA(hWidget, {'matlab.ui.control.Button', 'matlab.ui.control.CheckBox'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData'})}
    mode char = ''
end

if isempty(mode); mode = hWidget.Tag; end

switch mode
    case 'createModel'
        fprintf('Clicked on a widget of the segmentation panel (obj.handles.panels.segmentation): %s\n', mode);
    case 'loadModel'
        fprintf('Clicked on a widget of the segmentation panel (obj.handles.panels.segmentation): %s\n', mode);
    case 'addMaterial'
        fprintf('Clicked on a widget of the segmentation panel (obj.handles.panels.segmentation): %s\n', mode);
    case 'removeMaterial'
        fprintf('Clicked on a widget of the segmentation panel (obj.handles.panels.segmentation): %s\n', mode);
    case 'colorWheel'
        fprintf('Clicked on a widget of the segmentation panel (obj.handles.panels.segmentation): %s\n', mode);
    case 'viewSettings'
        fprintf('Clicked on a widget of the segmentation panel (obj.handles.panels.segmentation): %s\n', mode);
end
end