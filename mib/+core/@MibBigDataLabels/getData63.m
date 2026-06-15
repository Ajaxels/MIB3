function dataset = getData63(obj, type, orient, materialIndex, options)
% GETDATA63 - read a packed layer block from the disk-backed BigData model pyramid.
%
% Override of ``core.MibLabels63.getData63``. Selects the pyramid level that
% matches ``options.magFactor`` (or ``options.pyramidLevel``), reads the
% requested region from that level, and resizes it to the displayed resolution
% **exactly like the image reader** (``MibVirtualImage.getDataZarr``) so the
% model overlay lines up with the image in every orientation (YX, XZ, YZ).
%
% The coordinate math mirrors ``getDataZarr`` precisely: each screen axis maps to
% a data dimension (``outDim*ind``), each axis is scaled by its OWN pyramid scale
% factor (so Z — which the pyramid does not downsample — is handled correctly),
% the screen ranges are remapped to physical Y/X/Z, and the block is permuted to
% the requested screen orientation before a single-factor display resize. Bit
% semantics and the return shape match the parent.
%
% Input/Output: see core.MibLabels63.getData63.

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

% If deferred propagation left this level stale on disk, flush the queue so the
% read returns the up-to-date model (the working level is never stale, so reads
% at the editing zoom stay fast and only zoom changes pay the flush).
if ~isempty(obj.propagationQueue) && levelIdx <= numel(obj.dirtyLevels) && obj.dirtyLevels(levelIdx)
    obj.flushPropagation();
end

% --- physical [Y X Z] ranges for this level (shared with setData63) -------
[physYlim, physXlim, physZlim] = obj.orientPhysRanges(levelIdx, orient, options);
sf = obj.modelScaleFactors(levelIdx, :);   % [yScale, xScale, zScale]

% --- read the physical [y x z] packed region ------------------------------
packed = obj.readPackedLevel(levelIdx, physYlim, physXlim, physZlim);   % [ny nx nz]
packed = reshape(packed, size(packed, 1), size(packed, 2), size(packed, 3), 1, 1);

% --- permute [y,x,z] to the requested screen orientation (mirror getDataZarr)
switch orient
    case 1  % xz: [y,x,z] -> [x, z, y]
        packed = permute(packed, [2 3 1 4 5]);
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
