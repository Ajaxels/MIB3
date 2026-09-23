function result = deleteSlice(obj, sliceNumbers, orient, options)
% DELETESLICE - Delete specified slice(s) from the dataset across all layers.
%
% Syntax:
%   .. code-block:: matlab
%
%       result = obj.deleteSlice(sliceNumbers, orient)
%       result = obj.deleteSlice(sliceNumbers, orient, options)
%
% Orchestrates deletion of slices from the primary image, labels (model),
% mask, and selection layers, then shifts annotation positions and updates
% dimension-related properties.
%
% Input Arguments:
%   - **sliceNumbers** - index or index vector of slices to delete
%   - **orient** - *(optional)* dimension to operate on:
%     ``1`` = height (y), ``2`` = width (x), ``3`` = depth (z),
%     ``5`` = time (t). Default: ``obj.orientation``
%   - **options** - *(optional)* struct with fields:
%
%     - ``.showWaitbar`` - logical; **true** (default) shows a progress waitbar
%     - ``.ParentFigure`` - parent figure handle for the waitbar
%
% Output Arguments:
%   - **result** - ``1`` on success, ``0`` on failure
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     result = obj.mibModel.I{id}.deleteSlice(5, 3);  % delete z-slice 5
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     result = obj.mibModel.I{id}.deleteSlice([2,5,8], 3);  % delete multiple z-slices
%
%   **Example 3**
%
%   .. code-block:: matlab
%
%
%     result = obj.mibModel.I{id}.deleteSlice(1, 5);  % delete time-frame 1
%

% Updates
%

if nargin < 4; options = struct; end
if nargin < 3 || isempty(orient); orient = obj.orientation; end
if ~isfield(options, 'showWaitbar');  options.showWaitbar = true;  end
if ~isfield(options, 'ParentFigure'); options.ParentFigure = [];   end

result = 0;

if options.showWaitbar
    wb = uiprogressdlg(options.ParentFigure, 'Title', 'Deleting slice(s)...', ...
        'Message', sprintf('Deleting slice(s): %s\nPlease wait...', num2str(sliceNumbers)));
end

result = obj.image.deleteSlice(sliceNumbers, orient);
if result == 0
    if options.showWaitbar; delete(wb); end
    return;
end
if options.showWaitbar; wb.Value = 0.3; end

if obj.datasetType(1) ~= 'V'
    if obj.labels.maxMaterials == 63   % labels63: model+mask+selection packed together
        if obj.labels.exists   % any of model, mask or selection may be in use
            obj.labels.deleteSlice(sliceNumbers, orient);
        end
    else   % separate model / mask / selection layers
        if obj.modelExist
            obj.labels.deleteSlice(sliceNumbers, orient);
        end
        if options.showWaitbar; wb.Value = 0.5; end
        if obj.maskExist
            obj.mask.deleteSlice(sliceNumbers, orient);
        end
        if options.showWaitbar; wb.Value = 0.7; end
        if obj.selection.exists
            obj.selection.deleteSlice(sliceNumbers, orient);
        end
    end
end
if options.showWaitbar; wb.Value = 0.8; end

% shift annotations: labelPositions = [z, x, y, t]
[labelsList, labelValues, labelPositions, ~] = obj.annotations.getLabels();
if ~isempty(labelsList)
    slicesSorted = sort(sliceNumbers, 'descend');
    for sliceId = 1:numel(slicesSorted)
        currSlice = slicesSorted(sliceId);
        switch orient
            case 3  % depth (z) - labelPositions(:,1) = z
                labelPositions(labelPositions(:,1) >= currSlice, 1) = ...
                    labelPositions(labelPositions(:,1) >= currSlice, 1) - 1;
            case 1  % height (y) - labelPositions(:,3) = y
                labelPositions(labelPositions(:,3) >= currSlice, 3) = ...
                    labelPositions(labelPositions(:,3) >= currSlice, 3) - 1;
            case 2  % width (x) - labelPositions(:,2) = x
                labelPositions(labelPositions(:,2) >= currSlice, 2) = ...
                    labelPositions(labelPositions(:,2) >= currSlice, 2) - 1;
            case 5  % time (t) - labelPositions(:,4) = t
                labelPositions(labelPositions(:,4) >= currSlice, 4) = ...
                    labelPositions(labelPositions(:,4) >= currSlice, 4) - 1;
        end
    end
    obj.annotations.replaceLabels(labelsList, labelPositions, labelValues);
end

% sync dataset-level dimension cache
obj.dim_yxzct = obj.image.dim_yxzct;

% update slices (view range) and current position
obj.slices{3} = [min(obj.slices{3}(1), obj.image.depth), min(obj.slices{3}(2), obj.image.depth)];
obj.slices{5} = [min(obj.slices{5}(1), obj.image.time),  min(obj.slices{5}(2), obj.image.time)];
switch obj.orientation
    case 3   % YX
        obj.slices{1} = [1, obj.image.height];
        obj.slices{2} = [1, obj.image.width];
    case 1   % XZ
        obj.slices{2} = [1, obj.image.width];
        obj.slices{3} = [min(obj.slices{3}(1), obj.image.depth), min(obj.slices{3}(2), obj.image.depth)];
    case 2   % YZ
        obj.slices{1} = [1, obj.image.height];
        obj.slices{3} = [min(obj.slices{3}(1), obj.image.depth), min(obj.slices{3}(2), obj.image.depth)];
end

obj.current_yxz(1) = min(obj.current_yxz(1), obj.image.height);
obj.current_yxz(2) = min(obj.current_yxz(2), obj.image.width);
obj.current_yxz(3) = min(obj.current_yxz(3), obj.image.depth);

if orient == 3
    obj.image.boundingBox(6) = obj.image.boundingBox(5) + (obj.image.depth - 1) * obj.image.pixSize.z;
end

obj.image.actionLog{end+1} = sprintf('Delete slice(s): %s, orient: %d', num2str(sliceNumbers), orient);

if options.showWaitbar; wb.Value = 1; delete(wb); end
result = 1;
end
