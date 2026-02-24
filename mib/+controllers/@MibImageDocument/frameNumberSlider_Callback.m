function frameNumberSlider_Callback(obj, sliderValue)
% function frameNumberSlider_Callback(obj, sliderValue)
% Change the currently displayed frame using the time-number slider
%
% Handles user interaction with the frame number slider in the MIB image
% document view. Updates the model's active time-point (dimension 5) and
% triggers a view refresh.
%
% Syntax:
%   obj.frameNumberSlider_Callback()
%   obj.frameNumberSlider_Callback(sliderValue)
%
% Inputs:
%   obj        - MibImageDocument controller instance (handle)
%   sliderValue - (optional) double. The raw slider value to apply.
%                 If omitted, reads the current value from
%                 obj.handles.frameNumberSlider.Value.
%
% Notes:
%   - sliderValue is rounded to the nearest integer because the slider's
%     upper limit is set as a float (+0.001 offset) to avoid out-of-range
%     errors in MATLAB's uicontrol/slider widget.
%   - Updates obj.mibModel.I{id}.slices{5} as [frameNumber, frameNumber],
%     where index 5 corresponds to the time (T) dimension.
%   - Fires the 'SliceChanged' event on mibModel to notify any listeners
%     (e.g., other panels or overlays that depend on the current frame).
%   - In DeveloperMode, prints a diagnostic message to the command window
%     indicating which image set triggered the callback.
%
% MVC Role:
%   Controller (MibImageDocument) — mediates between the slider UI handle
%   (View) and the image dataset model (mibModel).
%
% Example:
%   % Programmatically jump to frame 7:
%   obj.cImageDoc{obj.mibModel.Sets.selectedSet}.frameNumberSlider_Callback(7);


if nargin < 2; sliderValue = obj.handles.frameNumberSlider.Value; end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibImageDocument.frameNumberSlider_Callback: "obj.cImageDoc{%d}.handles.frameNumberSlider" ->slices changed (obj.mibModel.Sets.selectedSet)\n', obj.mibModel.Sets.selectedSet);
end

frameNumber = round(sliderValue); % the slider top limit is a float with +0.001, thus it needs to be rounded

% update frame editbox
obj.handles.frameNumber.Value = frameNumber;

obj.mibModel.I{obj.mibModel.id}.slices{5} = [frameNumber, frameNumber];
notify(obj.mibModel, 'SliceChanged');   % notify the controller about changed slice
obj.mibController.showImage();
end