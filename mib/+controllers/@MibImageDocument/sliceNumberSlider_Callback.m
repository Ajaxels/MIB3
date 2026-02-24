function sliceNumberSlider_Callback(obj, sliderValue)
% function sliceNumberSlider_Callback(obj, sliderValue)
% Change the currently displayed slice using the slice-number slider.
%
% Syntax
%   sliceNumberSlider_Callback(obj)
%   sliceNumberSlider_Callback(obj, sliderValue)
%
% Description
%   This callback is triggered when the user changes the slice number slider in the
%   Image View panel. The function:
%   1) Reads the slider value (or uses the provided value),
%   2) Rounds it to an integer slice index (the slider maximum may be stored as a
%      float with +0.001),
%   3) Updates the current slice range in the model for the active dataset,
%      depending on dataset orientation (XZ / YZ / YX),
%   4) Refreshes the displayed image,
%   5) Notifies the rest of the app that the slice has changed.
%
%   For orientation == 3 ('YX'), if slice names are available, the title of the
%   Image View axes may be updated to include the slice/layer name.
%
% Inputs
%   obj         Controller instance (typically controllers.MibImageDocument) that
%               owns GUI handles and references the model/controller stack.
%   sliderValue (optional) Numeric value of the slider position. When omitted,
%               the value is read from obj.handles.sliceNumberSlider.Value. 
%
% Behavior / Side effects
%   - Updates GUI edit field: obj.handles.sliceNumber.Value = sliceNumber. 
%   - Updates model slice selection:
%       orientation == 1 (XZ): obj.mibModel.I{datasetId}.slices{1} = [N N] 
%       orientation == 2 (YZ): obj.mibModel.I{datasetId}.slices{2} = [N N]
%       orientation == 3 (YX): obj.mibModel.I{datasetId}.slices{3} = [N N] 
%   - Triggers redraw: obj.mibController.showImage().
%   - Emits event: notify(obj.mibModel, 'SliceChanged').
%   - In DeveloperMode, prints a diagnostic message to stdout. 
%
% Notes
%   - sliceNumber is computed as round(sliderValue) to avoid fractional slice
%     indices caused by slider numeric limits stored as floats. 
%   - Slice-name title update is only attempted when dataset.image.sliceName is
%     not empty; indices are clamped to the available number of names. 
%
% See also
%   showImage, notify

if nargin < 2; sliderValue = obj.handles.sliceNumberSlider.Value; end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibImageDocument.sliceNumberSlider_Callback: "obj.cImageDoc{%d}.handles.sliceNumberSlider" ->slices changed (obj.mibModel.Sets.selectedSet)\n', obj.mibModel.Sets.selectedSet);
end

sliceNumber = round(sliderValue); % the slider top limit is a float with +0.001, thus it needs to be rounded

datasetId = obj.mibModel.id;
dataset = obj.mibModel.I{datasetId};
obj.handles.sliceNumber.Value = sliceNumber;

if dataset.orientation == 1     %'XZ'
    obj.mibModel.I{datasetId}.slices{1} = [sliceNumber, sliceNumber];
elseif dataset.orientation == 2 %'YZ'
    obj.mibModel.I{datasetId}.slices{2} = [sliceNumber, sliceNumber];
elseif dataset.orientation == 3     %'YX'
    % update label text for the image view panel
    if ~isempty(dataset.image.sliceName)
        noSliceNames = numel(dataset.image.sliceName);
        layerNamePrevious = ...
            dataset.image.sliceName{min([dataset.slices{3}(1) noSliceNames])};
        layerNameNext = ...
            dataset.image.sliceName{min([sliceNumber noSliceNames])};

        if strcmp(layerNamePrevious, layerNameNext) % update label
            strVal1 = 'Image View    >>>>>    ';
            [~, fn, ext] = fileparts(dataset.image.filename);
            strVal2 = sprintf('%s%s    >>>>>    %s', fn, ext, layerNameNext);
            obj.handles.imViewAxes.Title.String = [strVal1 strVal2];    
        end
    end
    obj.mibModel.I{datasetId}.slices{3} = [sliceNumber, sliceNumber];
end

obj.mibController.showImage();
notify(obj.mibModel, 'SliceChanged');   % notify the controller about changed slice

end