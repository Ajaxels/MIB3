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

% --- physical [Y X Z] ranges for this level (shared with setData63) -------
[physYlim, physXlim, physZlim] = obj.orientPhysRanges(levelIdx, orient, options);
sf = obj.modelScaleFactors(levelIdx, :);   % [yScale, xScale, zScale]

% --- read the physical [y x z] packed region ------------------------------
packed = obj.readPackedLevel(levelIdx, physYlim, physXlim, physZlim);   % [ny nx nz]

% --- reconstruct coarse-drawn edits missing from this (finer) level -------
% setData63 stores each edit only at its drawn (working) level and COARSER; finer
% levels are never written. So when reading a level finer than the coarsest, fill
% any empty voxels from the coarsest level (which holds every edit), upsampled to
% this level's resolution — bounded to the read window. Voxels this level DOES hold
% (an edit drawn at this level or finer) keep their full detail. Finer levels are
% therefore on-demand views of the coarse data, so strokes never pay a full-res
% write (see development/bigdata_brush_performance.md).
nLevels = size(obj.modelLevelSizes, 1);
if levelIdx < nLevels && ~isempty(packed)
    fullY = [(physYlim(1)-1)*sf(1)+1, min(physYlim(2)*sf(1), obj.height)];
    fullX = [(physXlim(1)-1)*sf(2)+1, min(physXlim(2)*sf(2), obj.width)];
    fullZ = [(physZlim(1)-1)*sf(3)+1, min(physZlim(2)*sf(3), obj.depth)];
    [cY, cX, cZ] = obj.regionForLevel(nLevels, fullY, fullX, fullZ);
    coarse = obj.readPackedLevel(nLevels, cY, cX, cZ);
    if any(coarse(:))
        packed = core.MibBigDataLabels.reconstructFinerFill(packed, coarse);
    end
end

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
