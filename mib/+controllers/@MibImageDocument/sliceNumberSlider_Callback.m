function sliceNumberSlider_Callback(obj, sliderValue)
% SLICENUMBERSLIDER_CALLBACK - Change the currently displayed slice using the slice-number slider.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.sliceNumberSlider_Callback()
%      obj.sliceNumberSlider_Callback(sliderValue)
%
% Triggered when the user changes the slice number slider in the Image View panel. The function:
%   1. Reads the slider value (or uses provided value)
%   2. Rounds to integer slice index (slider maximum may be stored as float with +0.001)
%   3. Updates current slice range in model for active dataset by orientation
%   4. Refreshes displayed image
%   5. Notifies app that slice has changed
%
% For ``orientation == 3`` (YX), if slice names are available, the Image View axes title
% is updated to include the slice/layer name.
%
% Input Arguments:
%   - **sliderValue** *(optional)* - [numeric] slider position value;
%     if omitted, reads from ``obj.handles.sliceNumberSlider.Value``
%
% Output Arguments:
%   (none)
%
% **Side effects:**
%   - Updates GUI edit field: ``obj.handles.sliceNumber.Value = sliceNumber``
%   - Updates model slice selection by orientation:
%
%     - ``orientation == 1`` (XZ): ``obj.mibModel.I{datasetId}.slices{1} = [N, N]``
%     - ``orientation == 2`` (YZ): ``obj.mibModel.I{datasetId}.slices{2} = [N, N]``
%     - ``orientation == 3`` (YX): ``obj.mibModel.I{datasetId}.slices{3} = [N, N]``
%
%   - Triggers redraw: ``obj.mibController.showImage()``
%   - Emits event: ``notify(obj.mibModel, 'SliceChanged')``
%   - In DeveloperMode, prints diagnostic message to stdout
%
% **Important notes:**
%   - ``sliceNumber`` computed as ``round(sliderValue)`` to avoid fractional indices from float slider limits
%   - Slice-name title update only attempted when ``dataset.image.sliceName`` is not empty; indices clamped to available names
%
% See also:
%   ``showImage``, ``notify``

if nargin < 2; sliderValue = obj.handles.sliceNumberSlider.Value; end

% if obj.mibModel.preferences.System.DeveloperMode
%     fprintf('controllers.MibImageDocument.sliceNumberSlider_Callback: "obj.cImageDoc{%d}.handles.sliceNumberSlider" ->slices changed (obj.mibModel.Sets.selectedSet)\n', obj.mibModel.Sets.selectedSet);
% end

sliceNumber = round(sliderValue); % the slider top limit is a float with +0.001, thus it needs to be rounded

datasetId = obj.mibModel.id;
dataset = obj.mibModel.I{datasetId};
obj.handles.sliceNumber.Value = sliceNumber;

if dataset.orientation == 1     %'XZ'
    obj.mibModel.I{datasetId}.slices{1} = [sliceNumber, sliceNumber];
elseif dataset.orientation == 2 %'YZ'
    obj.mibModel.I{datasetId}.slices{2} = [sliceNumber, sliceNumber];
elseif dataset.orientation == 3     %'YX'
    obj.mibModel.I{datasetId}.slices{3} = [sliceNumber, sliceNumber];
end

notify(obj.mibModel, 'SliceChanged');   % notify the controller about changed slice

end
