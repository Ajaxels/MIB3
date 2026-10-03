function gui_Callbacks(obj, hWidget, hData, mode)
% GUI_CALLBACKS - Callbacks for widgets of the Image View documents.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.gui_Callbacks(hWidget, hData)
%      obj.gui_Callbacks(hWidget, hData, mode)
%
% Input Arguments:
%   - **hWidget** - [handle] pressed widget (Button, NumericEditField, or Slider)
%   - **hData** - [handle] supporting event data class
%   - **mode** *(optional)* - [char] identifier for the operation; when empty, ``hWidget.Tag`` is used.
%     Common modes:
%
%     - ``'firstSlice'`` - go to the first slice of the dataset
%     - ``'prevSlice'`` - go to the previous slice
%     - ``'sliceNumber'`` - edit the current slice number
%     - ``'sliceNumberSlider'`` - change the slice number using a slider
%     - ``'nextSlice'`` - go to the next slice
%     - ``'lastSlice'`` - go to the last slice
%     - ``'firstFrame'`` - go to the first time frame
%     - ``'prevFrame'`` - go to the previous frame
%     - ``'frameNumber'`` - edit the current time frame
%     - ``'frameNumberSlider'`` - change time frames using a slider
%     - ``'nextFrame'`` - go to the next frame
%     - ``'lastFrame'`` - go to the last frame
%
% **Important note:**
%   In split-panel mode the active set is switched to this document's set
%   (``setOfDatasetsIndex``, via ``cActiveDataset.setsOps_Callbacks``) before the
%   widget is handled. The slice/frame callbacks act on ``mibModel.id``; without the
%   switch, a slider of one document would change the slice of the dataset shown in
%   the other document and its ``SliceChanged`` listener would fail on the slider limits.
%

arguments (Input)
    obj controllers.MibImageDocument
    hWidget {mustBeA(hWidget, {'matlab.ui.control.Button', 'matlab.ui.control.NumericEditField', 'matlab.ui.control.Slider'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData', 'matlab.ui.eventdata.ValueChangingData'})}
    mode char = ''
end

if isempty(mode); mode = hWidget.Tag; end

if obj.mibModel.preferences.System.DeveloperMode
    if ~strcmp(mode, 'sliceNumberSlider')
        fprintf('controllers.MibImageDocument.gui_Callbacks: "obj.cImageDoc{%d}.handles.%s" -> changed/pressed (obj.mibModel.Sets.selectedSet)\n', obj.mibModel.Sets.selectedSet, mode);
    end
    % see also sliceNumber_Callback and sliceNumberSlider_Callback
end

% Split-panel guard: the widgets act on mibModel.id, which belongs to the active set;
% a click on a slider or button of another document does not pass through
% gui_WindowButtonDownFcn (outside the axes), so switch to this document's set here
if obj.mibModel.Sets.selectedSet ~= obj.setOfDatasetsIndex
    setName = obj.mibModel.Sets.names{obj.setOfDatasetsIndex};
    obj.mibController.view.handles.panels.activeDataset.handles.sets.Value = setName;
    obj.mibController.cActiveDataset.setsOps_Callbacks([], [], 'sets');
end

switch mode
    case 'lastSlice'
        obj.sliceNumber_Callback(0);
    case 'nextSlice'
        currentSlice = obj.handles.sliceNumber.Value;
        nextSlice = min([currentSlice+1, round(obj.handles.sliceNumber.Limits(2))]);
        obj.sliceNumber_Callback(nextSlice);
    case 'sliceNumberSlider'        % live ValueChanging while dragging
        obj.sliderDragCallback('slice', hData.Value, false);
    case 'sliceNumberSliderFinal'   % ValueChanged on release
        obj.sliderDragCallback('slice', hData.Value, true);
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
    case 'frameNumberSlider'        % live ValueChanging while dragging
        obj.sliderDragCallback('frame', hData.Value, false);
    case 'frameNumberSliderFinal'   % ValueChanged on release
        obj.sliderDragCallback('frame', hData.Value, true);
    case 'nextFrame'
        currentFrame = obj.handles.frameNumber.Value;
        nextFrame = min([currentFrame+1, round(obj.handles.frameNumber.Limits(2))]);
        obj.frameNumber_Callback(nextFrame);
    case 'lastFrame'
        obj.frameNumber_Callback(0);
end

end
