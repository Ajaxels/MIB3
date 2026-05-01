function frameNumberSlider_Callback(obj, sliderValue)
% FRAMENUMBERSLIDER_CALLBACK - Change the currently displayed frame using the time-number slider.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.frameNumberSlider_Callback()
%      obj.frameNumberSlider_Callback(sliderValue)
%
% Handles user interaction with the frame number slider in the MIB image
% document view. Updates the model's active time-point (dimension 5) and
% triggers a view refresh.
%
% Input Arguments:
%   - **sliderValue** *(optional)* — [double] raw slider value to apply;
%     if omitted, reads from ``obj.handles.frameNumberSlider.Value``
%
% Output Arguments:
%   (none)
%
% **Important notes:**
%   - ``sliderValue`` is rounded to nearest integer (slider upper limit is float with +0.001 offset to avoid range errors)
%   - Updates ``obj.mibModel.I{id}.slices{5}`` as ``[frameNumber, frameNumber]`` (index 5 = time dimension)
%   - Fires ``'SliceChanged'`` event on ``mibModel`` to notify listeners
%   - In DeveloperMode, prints diagnostic message to command window
%
% **Example** — programmatically jump to frame 7:
%
%   .. code-block:: matlab
%
%      obj.cImageDoc{obj.mibModel.Sets.selectedSet}.frameNumberSlider_Callback(7);


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
