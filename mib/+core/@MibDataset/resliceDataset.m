function result = resliceDataset(obj, sliceNumbers, orient, options)
% RESLICEDATASET - Keep only specified slices, removing all others from all layers.
%
% Syntax:
%   .. code-block:: matlab
%
%       result = obj.resliceDataset(sliceNumbers, orient)
%       result = obj.resliceDataset(sliceNumbers, orient, options)
%
% Orchestrates stride-reslicing of the primary image, labels (model), mask,
% and selection layers, then updates dimension-related properties.
%
% Input Arguments:
%   - **sliceNumbers** — index or index vector of slices to *keep*; all
%     other slices are removed
%   - **orient** — *(optional)* dimension to operate on:
%     ``1`` = height (y), ``2`` = width (x), ``3`` = depth (z),
%     ``5`` = time (t). Default: ``obj.orientation``
%   - **options** — *(optional)* struct with fields:
%
%     - ``.showWaitbar`` — logical; **true** (default) shows a progress waitbar
%     - ``.ParentFigure`` — parent figure handle for the waitbar
%
% Output Arguments:
%   - **result** — ``1`` on success, ``0`` on failure
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     result = obj.mibModel.I{id}.resliceDataset(1:2:end, 3);  % keep every other z-slice
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     result = obj.mibModel.I{id}.resliceDataset([1,5,10,20], 3);  % keep 4 specific z-slices
%

% Updates
%

if nargin < 4; options = struct; end
if nargin < 3 || isempty(orient); orient = obj.orientation; end
if ~isfield(options, 'showWaitbar');  options.showWaitbar = true;  end
if ~isfield(options, 'ParentFigure'); options.ParentFigure = [];   end

result = 0;

if options.showWaitbar
    wb = uiprogressdlg(options.ParentFigure, 'Title', 'Reslicing dataset...', ...
        'Message', 'Reslicing the dataset...\nPlease wait...');
end

result = obj.image.resliceDataset(sliceNumbers, orient);
if result == 0
    if options.showWaitbar; delete(wb); end
    return;
end
if options.showWaitbar; wb.Value = 0.3; end

if obj.datasetType(1) ~= 'V'
    if obj.labels.maxMaterials == 63   % labels63: model+mask+selection packed together
        if obj.modelExist
            obj.labels.resliceDataset(sliceNumbers, orient);
        end
    else   % separate model / mask / selection layers
        if obj.modelExist
            obj.labels.resliceDataset(sliceNumbers, orient);
        end
        if options.showWaitbar; wb.Value = 0.5; end
        if obj.maskExist
            obj.mask.resliceDataset(sliceNumbers, orient);
        end
        if options.showWaitbar; wb.Value = 0.7; end
        if obj.selection.exists
            obj.selection.resliceDataset(sliceNumbers, orient);
        end
    end
end
if options.showWaitbar; wb.Value = 0.8; end

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

obj.image.actionLog{end+1} = sprintf('Reslice dataset: %s slices kept, orient: %d', ...
    num2str(numel(sliceNumbers)), orient);

if options.showWaitbar; wb.Value = 1; delete(wb); end
result = 1;
end
