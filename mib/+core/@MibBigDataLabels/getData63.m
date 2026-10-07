function dataset = getData63(obj, type, orient, materialIndex, options)
% GETDATA63 - Read a label/mask/selection layer from the disk-backed BigData pyramid.
%
% Syntax:
%   .. code-block:: matlab
%
%      dataset = obj.getData63(type, orient, materialIndex, options)
%
% Override of ``core.MibLabels63.getData63``.  Selects the pyramid level that
% matches ``options.magFactor`` (or ``options.pyramidLevel``), materializes any
% dirty finer-level tiles on demand (``materializeForRead``), reads the requested
% region from that level, permutes it to the screen orientation, and resizes it
% to the display resolution **exactly like the image reader**
% (``MibVirtualImage.getDataZarr``) so the model overlay lines up pixel-for-pixel
% with the image in every orientation.
%
% **Bit packing** (packed uint8, same as ``core.MibLabels63``):
%
%   - bits 1-6 - material index 0-63 (``type='labels'``)
%   - bit 7     - mask flag (``type='mask'``)
%   - bit 8     - selection flag (``type='selection'``)
%   - all bits  - returned as-is (``type='everything'``)
%
% Input Arguments:
%   - **type** *(optional)* - [char] layer to unpack:
%
%     - ``'labels'``    - material indices 0-63 (or a binary map when ``materialIndex`` set)
%     - ``'mask'``      - binary mask (bit 7)
%     - ``'selection'`` - binary selection (bit 8)
%     - ``'everything'``- raw packed uint8 (all 3 layers)
%
%     Default: ``'labels'``.
%
%   - **orient** *(optional)* - [numeric] viewing orientation:
%
%     - ``1`` - ZX (vertical = Z, horizontal = X, slice = Y)
%     - ``2`` - YZ (vertical = Y, horizontal = Z, slice = X)
%     - ``3`` - YX (standard XY; vertical = Y, horizontal = X, slice = Z)
%
%     Default: ``3``.
%
%   - **materialIndex** *(optional)* - [numeric scalar | empty] when non-empty and
%     ``type='labels'``, returns a binary ``uint8`` mask that is 1 where the label equals
%     ``materialIndex``.  Pass ``[]`` to return all material indices (0-63).
%
%   - **options** *(optional)* - [struct] with fields:
%
%     - ``.magFactor``    - [numeric] current display magnification factor
%       (``dataset.magFactor``); the nearest pyramid level is chosen.  Default: ``1``.
%     - ``.pyramidLevel`` - [numeric] explicit 1-based level index (1 = finest).
%       Overrides ``magFactor`` entirely when set.
%     - ``.x``            - [1x2 numeric] horizontal screen coordinate range ``[x1 x2]``.
%       Default: full width of the selected level.
%     - ``.y``            - [1x2 numeric] vertical screen coordinate range ``[y1 y2]``.
%       Default: full height of the selected level.
%     - ``.z``            - [1x2 numeric] depth (slice) range ``[z1 z2]`` in the selected
%       level. Default: full depth of the selected level.
%
% Output Arguments:
%   - **dataset** - [uint8] unpacked layer at display resolution.  Shape is
%     ``[ny, nx, nz]`` for orientation 3 (YX), with ``ny/nx/nz`` determined by the
%     ``options.y/x/z`` ranges after level-scale division and display resize.  Returns
%     ``[]`` when the store is closed (``obj.exists == false``).
%
% **Example 1** - read the label map for the current view at the display zoom level:
%
%   .. code-block:: matlab
%
%      opts.magFactor = dataset.magFactor;   % e.g. 4 at 25% zoom
%      opts.x = dataset.slices{2};
%      opts.y = dataset.slices{1};
%      opts.z = dataset.slices{3};
%      labels = obj.mibModel.I{1}.labels.getData63('labels', 3, [], opts);
%
% **Example 2** - read the selection at a specific pyramid level:
%
%   .. code-block:: matlab
%
%      opts.pyramidLevel = 2;   % second finest level
%      sel = obj.mibModel.I{1}.labels.getData63('selection', 3, [], opts);

if nargin < 5; options = struct(); end
if nargin < 4; materialIndex = []; end
if nargin < 3; orient = []; end
if nargin < 2; type = []; end

if ~obj.exists || isempty(obj.modelArrays); dataset = []; return; end
if isempty(type); type = 'labels'; end
if isempty(orient); orient = 3; end
if ~strcmp(type, 'labels'); materialIndex = []; end

% --- select level ---------------------------------------------------------
levelIdx = obj.pickLevel(options);

% --- physical [Y X Z] ranges for this level (shared with setData63) -------
[physYlim, physXlim, physZlim] = obj.orientPhysRanges(levelIdx, orient, options);
sf = obj.modelScaleFactors(levelIdx, :);   % [yScale, xScale, zScale]

% --- ensure this level is materialized over the read window, then read -----
% Each edit is stored only at the level it was drawn (+ coarser). Tiles whose
% authoritative data lives at a coarser level (matLevel > this level) are dirty:
% materializeForRead recomputes them by upsampling from their source level, writes
% them to this level, and marks them clean (cached). Clean tiles are untouched -
% so the editing zoom reads its own data directly (no echo halo).
obj.materializeForRead(levelIdx, physYlim, physXlim, physZlim);
packed = obj.readPackedLevel(levelIdx, physYlim, physXlim, physZlim);   % [ny nx nz]

packed = reshape(packed, size(packed, 1), size(packed, 2), size(packed, 3), 1, 1);

% --- permute [y,x,z] to the requested screen orientation (mirror getDataZarr)
switch orient
    case 1  % zx: [y,x,z] -> [z, x, y]
        packed = pagetranspose(permute(packed, [2 3 1 4 5]));   % == permute(packed, [3 2 1 4 5]), but faster
    case 2  % yz: [y,x,z] -> [y, z, x]
        packed = permute(packed, [1 3 2 4 5]);
end

% --- single-factor display resize (mirror getDataZarr) --------------------
mf = 1;
if isfield(options, 'magFactor') && ~isempty(options.magFactor); mf = options.magFactor; end
explicitLevel = isfield(options, 'pyramidLevel') && ~isempty(options.pyramidLevel);
currentMag = sf(1);
resizeFactor = mf / currentMag;
if ~explicitLevel && abs(resizeFactor - 1) > 1e-3
    newY = max(1, round(size(packed, 1) / resizeFactor));
    newX = max(1, round(size(packed, 2) / resizeFactor));
    if ~isequal([newY newX], [size(packed, 1), size(packed, 2)])
        resized = zeros(newY, newX, size(packed, 3), 'uint8');
        for z = 1:size(packed, 3)
            resized(:, :, z) = imresize(packed(:, :, z), [newY newX], 'nearest');
        end
        packed = reshape(resized, newY, newX, size(packed, 3), 1, 1);
    end
end

% --- unpack the requested layer -------------------------------------------
switch type
    case 'labels'
        if ~isempty(materialIndex)
            dataset = uint8(bitand(packed, 63) == materialIndex(1));
        else
            dataset = bitand(packed, 63);
        end
    case 'mask'
        dataset = bitget(packed, 7);
    case 'selection'
        dataset = bitget(packed, 8);
    case 'everything'
        dataset = packed;
end
end
