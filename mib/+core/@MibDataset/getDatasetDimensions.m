function varargout = getDatasetDimensions(obj, type, orient, options)
% GETDATASETDIMENSIONS - Get dimensions of the dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       varargout = obj.getDatasetDimensions(type, orient, options)
%
% Input Arguments:
%   - **type** — type of the dataset to retrieve dimensions, 'image' (**default),** 'model', 'mask', 'selection'
%   - **orient** — *(optional)*, orientation of the returned dimensions:
%
%     - ``[]`` — return dimensions in the current orientation *(default)*
%     - ``1`` — dimensions transposed to the zx configuration: [y,x,z,c,t] → [x,z,y,c,t]
%     - ``2`` — dimensions transposed to the zy configuration: [y,x,z,c,t] → [y,z,x,c,t]
%     - ``3`` — dimensions of the original yx configuration: [y,x,z,c,t]
%
%   - **options** — *(optional)*, a structure with extra parameters
%
%     - ``.blockModeSwitch`` — ``0`` return dimensions of the full dataset, ``1`` return dimensions of the shown part only
%     - ``.splitDims`` — logical:
%
%       - ``true`` — *(default)* split dimensions into individual output variables (height, width, depth, color, time)
%       - ``false`` — return a single array [height, width, depth, color, time]
%
% Output Arguments:
%   - **height** — height of the dataset
%   - **width** — width of the dataset
%   - **depth** — number of z-layers of the dataset
%   - **colors** — vector of colors of the dataset
%   - **time** — number of time points
%     or vector with all those numbers when options.splitDims == true
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     [height width depth color time] = obj.mibModel.I{obj.mibModel.id}.getDatasetDimensions('image')% get dimensions of the complete dataset
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     [height width depth color time] = obj.mibModel.I{obj.mibModel.id}.getDatasetDimensions('image', 1)% get dimensions of the transposed dataset
%
%
%   **Attention:** **not** **sensitive** to the shown ROI
%

% Updates
% 

if nargin < 4; options = struct(); end
if nargin < 3; orient = []; end
if nargin < 2; type = []; end

if ~isfield(options, 'blockModeSwitch'); options.blockModeSwitch = obj.blockModeSwitch; end
if ~isfield(options, 'splitDims'); options.splitDims = true; end

if isempty(orient); orient = obj.orientation; end
if isempty(type); type = 'image'; end
time = obj.image.time;

if ~options.blockModeSwitch     % get the full size dataset
    if strcmp(type, 'image')
        [height, width, depth, colors, time] = obj.image.getDatasetDimensions(orient);
    elseif isa(obj.labels, 'core.MibLabels63')
        [height, width, depth, colors, time] = obj.labels.getDatasetDimensions(orient);
    else
        [height, width, depth, colors, time] = obj.(type).getDatasetDimensions(orient);
    end
else        % get the shown block
    switch orient
        case 3  % yx configuration: [y,x,z,c,t]
            height = obj.slices{1}(2)-obj.slices{1}(1)+1;
            width = obj.slices{2}(2)-obj.slices{2}(1)+1;
            depth = obj.image.depth;
        case 2  % yz configuration: [y,x,z,c,t] -> [y,z,x,c,t]
            height = obj.slices{1}(2)-obj.slices{1}(1)+1;
            width = obj.slices{3}(2)-obj.slices{3}(1)+1;
            depth = obj.width;
        case 1  % xz configuration: [y,x,z,c,t] -> [x,z,y,c,t]
            height = obj.slices{2}(2)-obj.slices{2}(1)+1;
            width = obj.slices{3}(2)-obj.slices{3}(1)+1;
            depth = obj.height;
    end
    if strcmp(type, 'image')
        colors = numel(obj.slices{4});
    else
        colors = 1;
    end
end

% Return based on outputMode
if options.splitDims
    varargout{1} = height;
    varargout{2} = width;
    varargout{3} = depth;
    varargout{4} = colors;
    varargout{5} = time;
else
    varargout{1} = [height, width, depth, colors, time];
end

end
