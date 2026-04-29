function clearLayer(obj, layer, y, x, z, t, blockModeSwitch)
% CLEARLAYER - Clear the layer, a wrapper function that is using.
%
% Syntax:
%   function clearLayer(obj, layer, y, x, z, t, blockModeSwitch)
%
% - obj.labels.clearLayer, for core.MibLabels63
% - obj.(layer).clearLayer, for other types
%
% Input Arguments:
%   - **layer** — a string with the target layer:
%
%     - ``[]`` or ``'selection'`` — *(default)* clear the selection layer
%     - ``'mask'`` — clear the mask layer
%     - ``'labels'`` — clear the labels layer
%     - ``'everything'`` — clear selection, mask, labels layers (``core.MibLabels63`` class only)
%     - ``'image'`` — clear the image layer
%
%   - **y** — *(optional)*, a vector of y-values, can be []:
%
%     - ``[]`` — *(default)* clear complete dataset (``'4D'`` mode)
%     - ``[minY, maxY]`` — vector of Y-min, Y-max values
%     - ``'2D'``, ``'3D'``, ``'4D'`` — char string specifying the clear mode
%
%   - **x** — *(optional)*, can be ``[]``, vector of X-min and X-max values ``[minX, maxX]``
%   - **z** — *(optional)* vector of Z-min, Z-max, for example ``[minZ, maxZ]``
%   - **t** — *(optional)* vector of T-min, T-max values, for example ``[minT, maxT]``
%   - **blockModeSwitch** — [*optional,* logical] enable/disable the block mode:
%
%     - ``[]`` — use the currently selected value ``obj.blockModeSwitch`` *(default)*
%     - ``true`` — enable block mode, clear only the shown area of the dataset
%     - ``false`` — disable block mode, clear the full dataset
%
% Output Arguments:
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.I{obj.mibModel.id}.clearLayer('selection');% call from mibController, clear the Selection layer completely
%

if nargin < 7; blockModeSwitch = obj.blockModeSwitch; end
if nargin < 6; t = []; end
if nargin < 5; z = []; end
if nargin < 4; x = []; end
if nargin < 3; y = '4D'; end
if nargin < 2; layer = 'selection'; end

% find the currently visible limits for block mode
if blockModeSwitch
    x = ceil(obj.axesX);
    y = ceil(obj.axesY);
end

% Resolve string modes ('2D', '3D', '4D') to numeric coordinate ranges
% here in MibDataset where obj.slices and obj.orientation are available.
% Lower-level clearLayer (MibImage, MibLabels) only receives numeric coords.
if ischar(y)
    switch y
        case '2D'
            % current slice only
            zCur = obj.slices{obj.orientation}(1);
            tCur = obj.slices{5}(1);
            z = [zCur, zCur];
            t = [tCur, tCur];
        case '3D'
            % full z-stack at the current time point
            tCur = obj.slices{5}(1);
            t = [tCur, tCur];
            z = [];     % full z range
        case '4D'
            z = [];     % full z and t range
            t = [];
    end
    y = [];     % full y range in all modes
    x = [];     % full x range in all modes
end

if isa(obj.labels, 'core.MibLabels63') && ~strcmp(layer, 'image')
    obj.labels.clearLayer(layer, y, x, z, t);
else
    obj.(layer).clearLayer([], y, x, z, t);
end
