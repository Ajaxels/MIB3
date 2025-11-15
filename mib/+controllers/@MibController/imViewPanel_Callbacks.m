function imViewPanel_Callbacks(obj, hWidget, hData, mode)
% function imViewPanel_Callbacks(obj, hWidget, hData, mode)
% callbacks for widgets of the Image View panel obj.view.handles.imView{setNumber}.handles...
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting data class
% mode: char, optional identifier the widget, used when the same operation
% is called from menu, when empty or missing hWidget.Tag is used as an identifier
% 'lastSlice' -> go to the last slice of the dataset
% 'sliceNumberSlider' -> change the slice number using a slider
% 'firstSlice' -> go to the first slice
% 'sliceNumber' -> edit the current slice number
% 'frameNumber' -> edit the current time frame
% 'firstFrame' -> go to the first time frame
% 'frameNumberSlider' -> chenge time frames using a slider
% 'lastFrame' -> go to the last frame

arguments (Input)
    obj controllers.MibController
    hWidget {mustBeA(hWidget, {'matlab.ui.control.Button', 'matlab.ui.control.NumericEditField', 'matlab.ui.control.Slider'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData', 'matlab.ui.eventdata.ValueChangingData'})}
    mode char = ''
end

if isempty(mode); mode = hWidget.Tag; end

if obj.mibModel.preferences.System.DeveloperMode
    %setNumber =
    fprintf('controllers.MibController.imViewPanel_Callbacks: "obj.view.handles.imView{%d}.handles.%s" -> changed/pressed\n', obj.mibModel.Sets.selectedSet, mode);
end

switch mode
    case 'lastSlice'
    case 'sliceNumberSlider'
    case 'firstSlice'
    case 'sliceNumber'
    case 'frameNumber'
    case 'firstFrame'
    case 'frameNumberSlider'
    case 'lastFrame'
end

end