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
    obj controllers.MibController
    hWidget {mustBeA(hWidget, {'matlab.ui.control.Button', 'matlab.ui.control.NumericEditField', 'matlab.ui.control.Slider'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData', 'matlab.ui.eventdata.ValueChangingData'})}
    mode char = ''
end

if isempty(mode); mode = hWidget.Tag; end

if obj.mibModel.preferences.System.DeveloperMode
    %setNumber =
    fprintf('controllers.MibController.imViewPanel_Callbacks: "obj.view.handles.imView{%d}.handles.%s" -> changed/pressed (obj.mibModel.Sets.selectedSet)\n', obj.mibModel.Sets.selectedSet, mode);
end

switch mode
    case 'lastSlice'
    case 'nextSlice'
    case 'sliceNumberSlider'
        % use hData.Value for interactive update
        sliceNumber = round(hData.Value); % the slider top limit is a float with +0.001, thus it needs to be rounded
        obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.sliceNumber.Value = sliceNumber;
        obj.mibModel.I{obj.mibModel.id}.slices{3} = [sliceNumber sliceNumber];
        obj.showImage();
    case 'prevSlice'
    case 'firstSlice'
    case 'sliceNumber'
    case 'frameNumber'
    case 'firstFrame'
    case 'prevFrame'
    case 'frameNumberSlider'
        % use hData.Value for interactive update
        obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.frameNumber.Value = hData.Value;
    case 'nextFrame'
    case 'lastFrame'
end

end