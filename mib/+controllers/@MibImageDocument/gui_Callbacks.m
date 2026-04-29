function gui_Callbacks(obj, hWidget, hData, mode)
% GUI_CALLBACKS - callbacks for widgets of the Image View documents obj.cImageDoc{setId}.
%
% Syntax:
%   function gui_Callbacks(obj, hWidget, hData, mode)
%
% Input Arguments:
%   - **hWidget** — handle to the pressed widget
%   - **hData** — handle to supporting data class
%   - **mode** — char, optional identifier the widget, used when the same operation
%     is called from menu, when empty or missing hWidget.Tag is used as an identifier
%     'lastSlice' go to the last slice of the dataset
%     'nextSlice' go to the next slice
%     'sliceNumberSlider' change the slice number using a slider
%     'prevSlice' go to the previous slice
%     'firstSlice' go to the first slice
%     'sliceNumber' edit the current slice number
%     'frameNumber' edit the current time frame
%     'firstFrame' go to the first time frame
%     'prevFrame' go to the previous frame
%     'frameNumberSlider' chenge time frames using a slider
%     'nextFrame' go to the next frame
%     'lastFrame' go to the last frame
%

arguments (Input)
    obj controllers.MibImageDocument
    hWidget {mustBeA(hWidget, {'matlab.ui.control.Button', 'matlab.ui.control.NumericEditField', 'matlab.ui.control.Slider'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData', 'matlab.ui.eventdata.ValueChangingData'})}
    mode char = ''
end

if isempty(mode); mode = hWidget.Tag; end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibImageDocument.gui_Callbacks: "obj.cImageDoc{%d}.handles.%s" -> changed/pressed (obj.mibModel.Sets.selectedSet)\n', obj.mibModel.Sets.selectedSet, mode);
    % see also sliceNumber_Callback and sliceNumberSlider_Callback
end

switch mode
    case 'lastSlice'
        obj.sliceNumber_Callback(0);
    case 'nextSlice'
        currentSlice = obj.handles.sliceNumber.Value;
        nextSlice = min([currentSlice+1, round(obj.handles.sliceNumber.Limits(2))]);
        obj.sliceNumber_Callback(nextSlice);
    case 'sliceNumberSlider'
        isZarrVirtual = obj.mibModel.I{obj.mibModel.id}.datasetType(1) == 'V' && ...
            ~isempty(obj.mibModel.I{obj.mibModel.id}.image.pyramid.levelNames);
        if isZarrVirtual
            % Zarr: update numeric display immediately, defer disk read
            % until the user pauses dragging for 150 ms.
            obj.handles.sliceNumber.Value = round(hData.Value);
            if ~isempty(obj.sliderDebounceTimer) && isvalid(obj.sliderDebounceTimer)
                stop(obj.sliderDebounceTimer);
                delete(obj.sliderDebounceTimer);
            end
            sliderVal = hData.Value;
            obj.sliderDebounceTimer = timer( ...
                'ExecutionMode', 'singleShot', ...
                'StartDelay',    0.1, ...
                'TimerFcn',      @(~,~) obj.sliceNumberSlider_Callback(sliderVal));
            start(obj.sliderDebounceTimer);
        else
            obj.sliceNumberSlider_Callback(hData.Value);
        end
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
        isZarrVirtual = obj.mibModel.I{obj.mibModel.id}.datasetType(1) == 'V' && ...
            ~isempty(obj.mibModel.I{obj.mibModel.id}.image.pyramid.levelNames);
        if isZarrVirtual
            obj.handles.frameNumber.Value = round(hData.Value);
            if ~isempty(obj.sliderDebounceTimer) && isvalid(obj.sliderDebounceTimer)
                stop(obj.sliderDebounceTimer);
                delete(obj.sliderDebounceTimer);
            end
            sliderVal = hData.Value;
            obj.sliderDebounceTimer = timer( ...
                'ExecutionMode', 'singleShot', ...
                'StartDelay',    0.1, ...
                'TimerFcn',      @(~,~) obj.frameNumberSlider_Callback(sliderVal));
            start(obj.sliderDebounceTimer);
        else
            obj.frameNumberSlider_Callback(hData.Value);
        end
    case 'nextFrame'
        currentFrame = obj.handles.frameNumber.Value;
        nextFrame = min([currentFrame+1, round(obj.handles.frameNumber.Limits(2))]);
        obj.frameNumber_Callback(nextFrame);
    case 'lastFrame'
        obj.frameNumber_Callback(0);
end

end
