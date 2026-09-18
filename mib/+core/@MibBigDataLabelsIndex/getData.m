function dataset = getData(obj, layerType, orient, colChannel, options)
% GETDATA - Read a displayed label slice from the attached pyramid.
%
% Syntax:
%   .. code-block:: matlab
%
%      dataset = obj.getData(layerType, orient, colChannel, options)
%
% Override of ``core.MibImage.getData``, and **load-bearing**: that method
% dispatches to ``getData63`` only for a ``core.MibLabels63`` and otherwise reads
% the in-memory ``obj.data``, which for this class is permanently empty. Without
% this override the overlay is silently blank.
%
% The read is three steps, and the middle one is the whole feature:
%
%   1. **Pick the level** in the image's scale space (:meth:`pickLevel`). At
%      ``magFactor`` 1 a pyramid starting at 128 nm has no level 1, so "nearest"
%      returns its finest published level - which is the fallback, arrived at with
%      no special case.
%   2. **Work out where the view's pixels land on that level.**
%      ``OmeZarrMetadataUtils.screenGridForRange`` says where the image layer put
%      each screen pixel in full-resolution space (and how many there are, which
%      must match or ``labeloverlay`` errors); ``levelReadWindow`` turns that into
%      one source voxel per pixel. Serving a fine view from a level 16x coarser is
%      not a resize - resizing the covering block gives the wrong size AND a
%      shifted origin. See those two methods for the arithmetic.
%   3. **Read and gather.** One indexed read, no intermediate at full resolution.
%
% Input Arguments:
%   - **layerType** *(optional)* - [char] layer to read:
%
%     - ``'labels'`` - material indices, or a binary map when ``colChannel`` is set
%     - ``'mask'`` / ``'selection'`` - correctly sized zeros; this class carries
%       neither layer, and a caller asking for one wants an empty overlay, not an error
%     - ``'image'`` - treated as ``'labels'``; the container IS the labels
%     - ``'everything'`` - errors. It means "the packed byte with all three layers",
%       which is structurally unavailable outside the ``MibLabels63`` family
%       (``getData3D.m:222`` makes the same point)
%
%     Default: ``'labels'``.
%
%   - **orient** *(optional)* - [numeric] viewing orientation, ``1`` = XZ,
%     ``2`` = YZ, ``3`` = YX. Default: ``3``.
%   - **colChannel** *(optional)* - [numeric|empty] material index; when non-empty
%     and reading labels, returns a binary ``uint8`` map of that object - the
%     store's own ids, unaffected by :attr:`renderPerObject`, which is a display
%     setting rather than a property of the data. ``[]`` returns all indices,
%     collapsed to 1 when :attr:`renderPerObject` is false.
%   - **options** *(optional)* - [struct] with fields:
%
%     - ``.magFactor`` - [numeric] display magnification. Default: ``1``
%     - ``.pyramidLevel`` - [numeric] explicit 1-based **label** level; overrides
%       ``magFactor`` and returns that level's own voxels with no display
%       resampling, matching ``getData63``'s meaning for the same field. This is
%       the read contract ``io.savers.MibImageSliceProvider`` needs, so it is also
%       how a level of these labels is exported to a file
%     - ``.x`` / ``.y`` / ``.z`` - [1x2 numeric] screen ranges in full-resolution
%       dataset coordinates. Default: the whole dataset on that axis
%
% Output Arguments:
%   - **dataset** - ``[ny, nx, nz]`` of class :attr:`dataClass` (``uint8`` for a
%     single material or a mask/selection request), at display resolution and the
%     same size the image layer returns for the same request. ``[]`` when no store
%     is attached.

if nargin < 5; options = struct(); end
if nargin < 4; colChannel = []; end
if nargin < 3; orient = []; end
if nargin < 2; layerType = []; end

if ~obj.exists || isempty(obj.modelArrays); dataset = []; return; end
if isempty(layerType); layerType = 'labels'; end
if isempty(orient); orient = 3; end
if strcmp(layerType, 'image'); layerType = 'labels'; end

if strcmp(layerType, 'everything')
    error('core:MibBigDataLabelsIndex:getData', ...
        ['''everything'' returns the packed byte holding labels, mask and selection ' ...
         'in one array, which only the MibLabels63 family has. These labels are ' ...
         'separate-layer and read-only: read ''labels'' instead.']);
end

materialIndex = [];
if strcmp(layerType, 'labels') && ~isempty(colChannel) && ...
        ~(isscalar(colChannel) && isnan(colChannel))
    materialIndex = colChannel(1);
end

magFactor = 1;
if isfield(options, 'magFactor') && ~isempty(options.magFactor)
    magFactor = options.magFactor;
end
explicitLevel = isfield(options, 'pyramidLevel') && ~isempty(options.pyramidLevel);

levelIndex     = obj.pickLevel(options);
labelScaleYXZ  = obj.modelScaleFactors(levelIndex, :);
labelSizesYXZ  = obj.modelLevelSizes(levelIndex, :);

[fullRanges, magnified] = orientFullRanges(orient, options, ...
    [obj.height, obj.width, obj.depth]);

% An explicit level means "this resolution, unresampled", so the label level IS
% the grid - exactly what getData63 does when pyramidLevel is set.
if explicitLevel
    imageScaleYXZ = labelScaleYXZ;
    magnified     = [false false false];
else
    imageScaleYXZ = obj.imageScaleForMagFactor(magFactor);
end

outputSizes  = zeros(1, 3);
levelRanges  = zeros(3, 2);
sourceIndex  = cell(1, 3);
for axisIndex = 1:3
    if magnified(axisIndex)
        stepFactor = magFactor;
    else
        % The slice axis is never magnified: one output plane per image plane,
        % which is what passing the image's own scale as the step produces.
        stepFactor = imageScaleYXZ(axisIndex);
    end
    screenGrid = io.loaders.OmeZarrMetadataUtils.screenGridForRange( ...
        fullRanges(axisIndex, :), imageScaleYXZ(axisIndex), stepFactor);
    window = io.loaders.OmeZarrMetadataUtils.levelReadWindow( ...
        screenGrid, labelScaleYXZ(axisIndex), labelSizesYXZ(axisIndex));

    levelRanges(axisIndex, :) = window.levelRange;
    if explicitLevel
        % The level's own voxels, unresampled - what an export has to write. A
        % store whose shape rounded DOWN covers slightly less than the image
        % claims, and the gather would then repeat its last row to fill the
        % requested extent: right for a display, wrong in a file.
        outputSizes(axisIndex) = window.levelRange(2) - window.levelRange(1) + 1;
    else
        outputSizes(axisIndex) = screenGrid.size;
        sourceIndex{axisIndex} = window.sourceIndex;
    end
end

if any(strcmp(layerType, {'mask', 'selection'}))
    % Neither layer exists here, but the SIZE still has to be right: getRGBimage
    % composites whatever it is handed against the image slice.
    dataset = zeros(outputSizes, 'uint8');
    dataset = orientPermute(dataset, orient);
    return;
end

% A named material is a question about one object, so the read keeps the store's
% own ids even when renderPerObject is collapsing them for display - otherwise
% every id is already 1 and the match below returns the union of every object.
block = obj.readLevel(levelIndex, levelRanges(1, :), levelRanges(2, :), levelRanges(3, :), ...
    ~isempty(materialIndex));
if explicitLevel
    dataset = block;   % already exactly the requested level voxels
else
    dataset = block(sourceIndex{1}, sourceIndex{2}, sourceIndex{3});
end

dataset = orientPermute(dataset, orient);

if ~isempty(materialIndex)
    dataset = uint8(dataset == materialIndex);
end
end

% =========================================================================
function [fullRanges, magnified] = orientFullRanges(orient, options, fullSizeYXZ)
% ORIENTFULLRANGES - Map a screen request onto the physical [Y X Z] axes.
%
% The EXACT convention of ``MibVirtualImage.getDataZarr`` and
% ``MibBigDataLabels.orientPhysRanges``, so the overlay lines up with the image in
% every orientation: ``options.x`` is the horizontal screen range, ``.y`` the
% vertical, ``.z`` the slice, and which physical axis each lands on depends on the
% orientation.
%
% Unlike those two, the ranges stay in **full-resolution dataset** coordinates -
% the scaling onto a level happens later, per level, inside ``levelReadWindow``,
% because the label level and the image level are not the same one here.
%
% ``magnified`` reports which physical axes are screen axes: those two are divided
% by ``magFactor``, the third is the slice axis and is not.

switch orient
    case 1  % xz: vertical = X, horizontal = Z, slice = Y
        rangeY    = axisRange(options, 'z', fullSizeYXZ(1));
        rangeX    = axisRange(options, 'y', fullSizeYXZ(2));
        rangeZ    = axisRange(options, 'x', fullSizeYXZ(3));
        magnified = [false true true];
    case 2  % yz: vertical = Y, horizontal = Z, slice = X
        rangeY    = axisRange(options, 'y', fullSizeYXZ(1));
        rangeX    = axisRange(options, 'z', fullSizeYXZ(2));
        rangeZ    = axisRange(options, 'x', fullSizeYXZ(3));
        magnified = [true false true];
    otherwise  % 3 yx: vertical = Y, horizontal = X, slice = Z
        rangeY    = axisRange(options, 'y', fullSizeYXZ(1));
        rangeX    = axisRange(options, 'x', fullSizeYXZ(2));
        rangeZ    = axisRange(options, 'z', fullSizeYXZ(3));
        magnified = [true true false];
end
fullRanges = [rangeY; rangeX; rangeZ];
end

% =========================================================================
function range = axisRange(options, fieldName, axisSize)
% AXISRANGE - One [first last] range from options, defaulted and clamped.
% A scalar is read as a single-element range, the same way
% ``core.MibImage.getData`` reads ``options.x(1)`` / ``options.x(end)``.
if isfield(options, fieldName) && ~isempty(options.(fieldName))
    value = double(options.(fieldName));
    range = [value(1), value(end)];
else
    range = [1, axisSize];
end
range = [max(1, floor(range(1))), min(axisSize, floor(range(2)))];
range(2) = max(range(2), range(1));
end

% =========================================================================
function dataset = orientPermute(dataset, orient)
% ORIENTPERMUTE - [y,x,z] to the requested screen arrangement (mirror of getData63).
switch orient
    case 1  % xz: [y,x,z] -> [x, z, y]
        dataset = permute(dataset, [2 3 1]);
    case 2  % yz: [y,x,z] -> [y, z, x]
        dataset = permute(dataset, [1 3 2]);
end
end
