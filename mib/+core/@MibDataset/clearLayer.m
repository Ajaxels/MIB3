function clearLayer(obj, layer, y, x, z, t, blockModeSwitch)
% CLEARLAYER - Clear data from a layer (wrapper for layer-specific clear methods).
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.clearLayer(layer)
%      obj.clearLayer(layer, y, x, z, t)
%      obj.clearLayer(layer, y, x, z, t, blockModeSwitch)
%
% Routes to ``obj.labels.clearLayer`` for ``core.MibLabels63`` or ``obj.(layer).clearLayer`` for other types.
%
% Input Arguments:
%   - **layer** — [char] target layer to clear:
%
%     - ``'selection'`` or ``[]`` — clear the selection layer (default)
%     - ``'mask'`` — clear the mask layer
%     - ``'labels'`` — clear the labels layer
%     - ``'everything'`` — clear selection, mask, labels layers (``core.MibLabels63`` only)
%     - ``'image'`` — clear the image layer
%
%   - **y** *(optional)* — [numeric or char] y-coordinates or clear mode:
%
%     - ``[]`` — clear complete dataset in ``'4D'`` mode (default)
%     - ``[minY, maxY]`` — numeric vector of Y-min and Y-max
%     - ``'2D'`` — clear current slice only
%     - ``'3D'`` — clear full z-stack at current time
%     - ``'4D'`` — clear entire 4D dataset
%
%   - **x** *(optional)* — [numeric] X-min and X-max values ``[minX, maxX]``; ``[]`` for full range
%   - **z** *(optional)* — [numeric] Z-min and Z-max values ``[minZ, maxZ]``; ``[]`` for full range
%   - **t** *(optional)* — [numeric] T-min and T-max values ``[minT, maxT]``; ``[]`` for full range
%   - **blockModeSwitch** *(optional)* — [logical] enable/disable block mode:
%
%     - ``[]`` — use currently selected value ``obj.blockModeSwitch`` (default)
%     - ``true`` — enable block mode; clear only the shown area
%     - ``false`` — disable block mode; clear the full dataset
%
% Output Arguments:
%
% **Example 1** — Clear the selection layer completely:
%
%   .. code-block:: matlab
%
%      obj.clearLayer('selection');
%
% **Example 2** — Clear only the current 2D slice:
%
%   .. code-block:: matlab
%
%      obj.clearLayer('selection', '2D');
%
% **Example 3** — Clear with block mode enabled (visible area only):
%
%   .. code-block:: matlab
%
%      obj.clearLayer('selection', '4D', [], [], [], true);

if nargin < 7; blockModeSwitch = obj.blockModeSwitch; end
if nargin < 6; t = []; end
if nargin < 5; z = []; end
if nargin < 4; x = []; end
if nargin < 3; y = '4D'; end
if nargin < 2; layer = 'selection'; end

% capture string mode before block mode overwrites y
charMode = '';
if ischar(y); charMode = y; end

% find the currently visible limits for block mode
if blockModeSwitch
    x = ceil(obj.axesX);
    y = ceil(obj.axesY);
end

% Resolve string modes ('2D', '3D', '4D') to numeric coordinate ranges
% here in MibDataset where obj.slices and obj.orientation are available.
% Lower-level clearLayer (MibImage, MibLabels) only receives numeric coords.
if ~isempty(charMode)
    switch charMode
        case '2D'
            % current slice only — map slice index to the correct axis
            tCur = obj.slices{5}(1);
            t = [tCur, tCur];
            sliceCur = obj.slices{obj.orientation}(1);
            switch obj.orientation
                case 3  % XY: slice index is Z
                    z = [sliceCur, sliceCur];
                case 1  % ZX: slice index is Y
                    y = [sliceCur, sliceCur];
                case 2  % ZY: slice index is X
                    x = [sliceCur, sliceCur];
            end
        case '3D'
            % full z-stack at the current time point
            tCur = obj.slices{5}(1);
            t = [tCur, tCur];
            z = [];     % full z range
        case '4D'
            z = [];     % full z and t range
            t = [];
    end
    if ~blockModeSwitch
        y = [];     % full y range
        x = [];     % full x range
    end
    % if blockModeSwitch, x/y already set to visible axes limits above
end

if isa(obj.labels, 'core.MibLabels63') && ~strcmp(layer, 'image')
    % pass the current magnification so a disk-backed BigData model clears at the
    % displayed pyramid level (not full resolution); ignored by in-memory models.
    obj.labels.clearLayer(layer, y, x, z, t, obj.magFactor);
else
    obj.(layer).clearLayer([], y, x, z, t);
end
