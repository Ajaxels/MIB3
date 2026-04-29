function [labelsList, labelValues, labelPositions, indices] = getSliceLabels(obj, sliceNumber, timePoint, options)
% GETSLICELABELS - [labelsList, labelValues, labelPositions, indices] = getSliceLabels(obj, sliceNumber, timePoint, options).
%
% Syntax:
%   function [labelsList, labelValues, labelPositions, indices] = getSliceLabels(obj, sliceNumber, timePoint, options)
%
% Get list of labels (mibImage.annotations) shown at the specified slice
%
% Input Arguments:
%   - **sliceNumber** — *(optional)*, a slice number to get labels
%   - **timePoint** — *(optional)*, a time point to get the labels
%   - **options** — *(optional)*, structure with additional parameters:
%
%     - ``.blockModeSwitch`` — *(optional)*, optionally return labels that are seen only in the current view
%     - ``.shiftCoordinates`` — *(optional)*, shift coordinates so that they are corrected relative to the crop introduces by blockModeSwitch
%
% Output Arguments:
%   - **labelsList** — a cell array with labels
%   - **labelPositions** — a matrix with coordinates of the labels [labelIndex, z x y]
%   - **indices** — indices of the labels
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     [labelsList, labelValues, labelPositions, indices] = obj.mibModel.I{obj.mibModel.id}.getSliceLabels(15);% call from mibController; get all labels from the slice 15
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     [labelsList, labelValues, labelPositions, indices] = obj.mibModel.I{obj.mibModel.id}.getSliceLabels();% call from mibController;  get all labels from the currently shown slice
%

if nargin < 4; options = struct(); end
if nargin < 3; timePoint = obj.slices{5}(1); end
if nargin < 2; sliceNumber = obj.slices{obj.orientation}(1); end

if obj.orientation == 3   % xy
    [labelsList, labelValues, labelPositions, indices] = obj.annotations.getLabels(sliceNumber, NaN, NaN, timePoint);
elseif obj.orientation == 1   % zx
    [labelsList, labelValues, labelPositions, indices] = obj.annotations.getLabels(NaN, NaN, sliceNumber, timePoint);
elseif obj.orientation == 2   % zy
    [labelsList, labelValues, labelPositions, indices] = obj.annotations.getLabels(NaN, sliceNumber, NaN, timePoint);
end

% additionally remove points that are not visible in the current view 
if isfield(options, 'blockModeSwitch') && options.blockModeSwitch
    if obj.orientation == 3     % get ids of the correct vectors in the matrix, depending on orientation
        xId = 2;
        yId = 3;
    elseif obj.orientation == 1
        xId = 1;
        yId = 2;
    elseif obj.orientation == 2
        xId = 1;
        yId = 3;
    end
    % filter points to return only the points visible in the view
    pntIndices = labelPositions(:,xId) >= obj.axesX(1) & labelPositions(:,xId) <= obj.axesX(2) & ...
        labelPositions(:,yId) >= obj.axesY(1) & labelPositions(:,yId) <= obj.axesY(2);

    % trim the list
    labelsList = labelsList(pntIndices);
    labelValues = labelValues(pntIndices);
    labelPositions = labelPositions(pntIndices, :);
    indices = indices(pntIndices);

    resizeSwitch = false;
    magnificationFactor = 1;
    if isfield(options, 'shiftCoordinates') && options.shiftCoordinates
        if resizeSwitch == 0     % this needed for snapshots
            labelPositions(:,xId) = ceil((labelPositions(:,xId) - max([0 floor(obj.axesX(1))])) );     % - .999/obj.magFactor subtract 1 pixel to put a marker to the left-upper corner of the pixel
            labelPositions(:,yId) = ceil((labelPositions(:,yId) - max([0 floor(obj.axesY(1))])) );
        else
            labelPositions(:,xId) = ceil((labelPositions(:,xId) - max([0 floor(obj.axesX(1))])) / magnificationFactor);% - .999/obj.magFactor);     % - .999/obj.magFactor subtract 1 pixel to put a marker to the left-upper corner of the pixel
            labelPositions(:,yId) = ceil((labelPositions(:,yId) - max([0 floor(obj.axesY(1))])) / magnificationFactor);% - .999/obj.magFactor);
        end
    end
end
