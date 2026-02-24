function gui_Callbacks(obj, hWidget, hData, mode)
% function gui_Callbacks(obj, hWidget, hData, mode)
% callbacks for widgets of the Image View documents obj.cImageDoc{setId} 
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting data class
% mode: char, optional identifier the widget, used when the same operation
% is called from menu, when empty or missing hWidget.Tag is used as an identifier
% 'lastSlice' -> go to the last slice of the dataset
% 'nextSlice' -> go to the next slice
% 'sliceNumberSlider' -> change the slice number using a slider
% 'prevSlice' -> go to the previous slice
% 'firstSlice' -> go to the first slice
% 'sliceNumber' -> edit the current slice number
% 'frameNumber' -> edit the current time frame
% 'firstFrame' -> go to the first time frame
% 'prevFrame' -> go to the previous frame
% 'frameNumberSlider' -> chenge time frames using a slider
% 'nextFrame' -> go to the next frame
% 'lastFrame' -> go to the last frame

arguments (Input)
    obj controllers.MibImageDocument
    hWidget {mustBeA(hWidget, {'matlab.ui.control.Button', 'matlab.ui.control.NumericEditField', 'matlab.ui.control.Slider'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData', 'matlab.ui.eventdata.ValueChangingData'})}
    mode char = ''
end

if isempty(mode); mode = hWidget.Tag; end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibImageDocument.gui_Callbacks: "obj.cImageDoc{%d}.handles.%s" -> changed/pressed (obj.mibModel.Sets.selectedSet)\n', obj.mibModel.Sets.selectedSet, mode);
end

switch mode
    case 'lastSlice'
        obj.sliceNumber_Callback(0);
    case 'nextSlice'
        currentSlice = obj.handles.sliceNumber.Value;
        nextSlice = min([currentSlice+1, round(obj.handles.sliceNumber.Limits(2))]);
        obj.sliceNumber_Callback(nextSlice);
    case 'sliceNumberSlider'
        % use hData.Value for interactive update
        obj.sliceNumberSlider_Callback(hData.Value);
    case 'prevSlice'
        currentSlice = obj.handles.sliceNumber.Value;
        nextSlice = max([currentSlice-1, 1]);
        obj.sliceNumber_Callback(nextSlice);
    case 'firstSlice'
        obj.sliceNumber_Callback(1);
    case 'sliceNumber'
        obj.sliceNumber_Callback(hWidget.Value);
    case 'frameNumber'
        obj.frameNumber_Callback();
    case 'firstFrame'
        obj.frameNumber_Callback(1);
    case 'prevFrame'
        currentFrame = obj.handles.frameNumber.Value;
        nextFrame = max([currentFrame-1, 1]);
        obj.frameNumber_Callback(nextFrame);
    case 'frameNumberSlider'
        % use hData.Value for interactive update
        obj.frameNumberSlider_Callback(hData.Value);
        %obj.handles.frameNumber.Value = hData.Value;
    case 'nextFrame'
        currentFrame = obj.handles.frameNumber.Value;
        nextFrame = min([currentFrame+1, round(obj.handles.frameNumber.Limits(2))]);
        obj.frameNumber_Callback(nextFrame);
    case 'lastFrame'
        obj.frameNumber_Callback(0);
end

end