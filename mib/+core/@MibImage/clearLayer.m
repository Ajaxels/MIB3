function clearLayer(obj, layerName, y, x, z, t, magFactor)
% CLEARLAYER - Clear the layer using numeric coordinate ranges.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.clearLayer(layerName, y, x, z, t)
%
% String mode resolution ('2D', '3D', '4D') and block-mode coordinate
% clamping are handled upstream in MibDataset.clearLayer, which has
% access to obj.slices and obj.orientation. This function only accepts
% numeric coordinate ranges or [] for full extent.
%
% Input Arguments:
%   - **layerName** — char with the target layer name; default ``'selection'``:
%
%     - ``'selection'`` — clear the selection layer
%     - ``'mask'`` — clear the mask layer
%     - ``'labels'`` — clear the labels layer
%     - ``'everything'`` — clear selection, mask, and labels layers (``core.MibLabels63`` only)
%     - ``'image'`` — clear the image layer
%   - **y** — *(optional)* numeric [minY, maxY] or [] for full height extent
%   - **x** — *(optional)* numeric [minX, maxX] or [] for full width extent
%   - **z** — *(optional)* numeric [minZ, maxZ] or [] for full depth extent
%   - **t** — *(optional)* numeric [minT, maxT] or [] for full time extent
%   - **blockModeSwitch** — *(optional)* unused; block mode is resolved in MibDataset.clearLayer
%
% Output Arguments:
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.I{obj.mibModel.id}.selection.clearLayer();% call from mibController, clear the Selection layer completely
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.I{obj.mibModel.id}.selection.clearLayer([], 1:imageData.y, 1:imageData.x, 1:3);% call from mibController, clear the Selection layer only in 3 first slices
%

% @code obj.clearLayer('selection');% clear the layer, call from the class @endcode
% @code dataset = obj.clearLayer('everything');% clear the layer call from MibController, where type='image', 'label', 'mask', 'selection', 'everything'
% @code obj.clearLayer('selection', '3D', [], [], [], true);% clear the selection layer in 3D in the currently visible area @endcode

% Updates
% 

if nargin < 7; magFactor = []; end
if nargin < 6; t = []; end
if nargin < 5; z = []; end
if nargin < 4; x = []; end
if nargin < 3; y = []; end
if nargin < 2; layerName = 'selection'; end

if ~obj.exists; return; end    % layer is disabled/uninitialized

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
        obj.data = zeros([obj.height, obj.width, obj.depth, obj.colors, obj.time], obj.dataClass);
    else
        obj.data(getDataOptions.y(1):getDataOptions.y(2), ...
                    getDataOptions.x(1):getDataOptions.x(2), ...
                    getDataOptions.z(1):getDataOptions.z(2), ...
                    c, ...
                    getDataOptions.t(1):getDataOptions.t(2)) = 0;
    end
else
    % For a disk-backed BigData model, clear at the displayed pyramid level: pass
    % magFactor so setData63 writes to the SAME level shown (not full resolution),
    % and size the zero block at the display resolution so we never allocate a
    % full-res block. Standard (in-memory) MibLabels63 ignores magFactor and uses
    % the full-resolution block as before.
    if isa(obj, 'core.MibBigDataLabels') && ~isempty(magFactor) && magFactor ~= 1
        getDataOptions.magFactor = magFactor;
        img = zeros([max(1, round(dy/magFactor)), max(1, round(dx/magFactor)), dz, numel(c), dt], obj.dataClass);
    else
        img = zeros([dy, dx, dz, numel(c), dt], obj.dataClass);
    end
    obj.setData(img, layerName, [], [], getDataOptions);
end

end
