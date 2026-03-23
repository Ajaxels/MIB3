function clearLayer(obj, layerName, y, x, z, t)
% function clearLayer(obj, layerName, y, x, z, t)
% Clear the layer using numeric coordinate ranges.
%
% String mode resolution ('2D', '3D', '4D') and block-mode coordinate
% clamping are handled upstream in MibDataset.clearLayer, which has
% access to obj.slices and obj.orientation. This function only accepts
% numeric coordinate ranges or [] for full extent.
%
% Parameters:
% layerName: char with the target layer name, can be []
% @li [] -> 'selection'
% @li 'selection' -> clear the selection layer
% @li 'mask' -> clear the mask layer
% @li 'labels' -> clear the labels layer
% @li 'everything' -> clear selection, mask, labels layers for core.MibLabels63 class only
% @li 'image' -> clear the image layer
% y: [@em optional] numeric [minY, maxY] or [] for full height extent
% x: [@em optional] numeric [minX, maxX] or [] for full width extent
% z: [@em optional] numeric [minZ, maxZ] or [] for full depth extent
% t: [@em optional] numeric [minT, maxT] or [] for full time extent
% blockModeSwitch: [@em optional] unused; block mode is resolved in MibDataset.clearLayer
%
% Return values:
% 

%| 
% Examples:
% @code obj.mibModel.I{obj.mibModel.id}.selection.clearLayer(); // call from mibController, clear the Selection layer completely @endcode
% @code obj.mibModel.I{obj.mibModel.id}.selection.clearLayer([], 1:imageData.y, 1:imageData.x, 1:3); //  call from mibController, clear the Selection layer only in 3 first slices  @endcode

% @code obj.clearLayer('selection');      // clear the layer, call from the class @endcode
% @code dataset = obj.clearLayer('everything'); // clear the layer call from MibController, where type='image', 'label', 'mask', 'selection', 'everything'
% @code obj.clearLayer('selection', '3D', [], [], [], true);      // clear the selection layer in 3D in the currently visible area @endcode

% Updates
% 

if nargin < 6; t = []; end
if nargin < 5; z = []; end
if nargin < 4; x = []; end
if nargin < 3; y = []; end
if nargin < 2; layerName = 'selection'; end

if isempty(obj.data{1}); return; end    % selection is disabled

% update time
if isempty(t)
    getDataOptions.t = [1 obj.time];
elseif numel(t) == 2
    getDataOptions.t = [max([1 t(1)]) min([t(2) obj.time])];
else
    getDataOptions.t = [t(1) t(1)];
end
dt = diff(getDataOptions.t)+1;

% update depth
if isempty(z)
    getDataOptions.z = [1 obj.depth];
elseif numel(z) == 2
    getDataOptions.z = [max([1 z(1)]) min([z(2) obj.depth])];
else
    getDataOptions.z = [z(1) z(1)];
end
dz = diff(getDataOptions.z)+1;

% update width
if isempty(x)
    getDataOptions.x = [1 obj.width];
elseif numel(x) == 2
    getDataOptions.x = [max([1 x(1)]) min([x(2) obj.width])];
else
    getDataOptions.x = [x(1) x(1)];
end
dx = diff(getDataOptions.x)+1;

% update height
if isempty(y)
    getDataOptions.y = [1 obj.height];
elseif numel(y) == 2
    getDataOptions.y = [max([1 y(1)]) min([y(2) obj.height])];
else
    getDataOptions.y = [y(1) y(1)];
end
dy = diff(getDataOptions.y)+1;

% define color vector
c = 1:obj.colors;

if ~isa(obj, 'core.MibLabels63')
    if nargin < 3
        obj.data{1} = zeros([obj.height, obj.width, obj.depth, obj.colors, obj.time], obj.dataClass);
    else
        obj.data{1}(getDataOptions.y(1):getDataOptions.y(2), ...
                    getDataOptions.x(1):getDataOptions.x(2), ...
                    getDataOptions.z(1):getDataOptions.z(2), ...
                    c, ...
                    getDataOptions.t(1):getDataOptions.t(2)) = 0;
    end
else
    img = zeros([dy, dx, dz, numel(c), dt], obj.dataClass);
    obj.setData(img, layerName, [], [], getDataOptions);
end

end