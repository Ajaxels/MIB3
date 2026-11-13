function writeModelStoreSlab(obj, labelsStore, slabLabels, predictedLevel, zFirst)
% WRITEMODELSTORESLAB - write a Z-slab of the prediction into a BigData model store.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.writeModelStoreSlab(labelsStore, slabLabels, predictedLevel, zFirst)
%
% Second step of the "Zarr3 (BigData model)" output, after ``createModelStore``.
% The slab, the full XY extent of the predicted level from slice ``zFirst`` on,
% is written exactly to that level (``setData63`` with ``'everything'``, never
% smoothed). ``setData63`` propagates it to the coarser levels by
% nearest-neighbour downsampling, raises ``maxIndexUsed`` and sets the level map
% to the predicted level where the prediction has labels. The finer levels are
% not written: they are reconstructed from the predicted level when read
% (``materializeForRead``) or by "Finalize & save" (``materializeAll``), so no
% full-resolution array is built here.
%
% Slabs are independent when ``zFirst - 1`` is a multiple of the Z factor of
% every coarser level relative to the predicted level: each coarser slice then
% comes from one slab only. ``predictZarrStore`` and ``startPredictionInstances``
% size their slabs so; a misaligned slab still works, but a coarser slice it
% shares with the next slab is taken from the next one. Slab by slab gives the
% store of one whole-level write when the depth of the level is a multiple of
% the Z factors. Otherwise the nearest-neighbour slices of a coarser level
% differ: a slab takes the first slice of each block of the scale factor, while
% the resize of a whole odd depth (``propagateRegion``) stretches it (9 slices
% to 5 take 1, 2, 4, 6, 8 rather than 1, 3, 5, 7, 9). With ``'mode'`` both are the
% same block reduction.
%
% ``obj.ZarrModelOpt.DownsampleMethod = 'mode'`` replaces the nearest-neighbour
% coarser levels with a majority vote over blocks of the slab
% (``io.savers.Zarr3Saver.blockReduce2D``, or ``blockReduce3D`` for a level that
% also halves Z). The slab is cropped or padded (replicate) to whole blocks
% first, so the reduction stays vectorised; with an aligned slab only the last
% slab of the level is padded in Z, as a whole-level write would be.
%
% Input Arguments:
%   - **labelsStore** - [core.MibBigDataLabels] the store from ``createModelStore``
%   - **slabLabels** - [numeric] ``[height, width, depth]`` labels of the slab,
%     ``height`` and ``width`` of the predicted level; 0 = background
%   - **predictedLevel** - [numeric] level of the store the prediction belongs
%     to, from ``createModelStore``
%   - **zFirst** - [numeric] first slice of the slab within the predicted level

    slabLabels = cast(slabLabels, labelsStore.containerClass);
    if max(slabLabels, [], 'all') > labelsStore.materialMask
        error('MibDeep:writeModelStore:tooManyObjects', ...
            'The prediction has %d objects in one slice, but a BigData model store holds at most %d', ...
            max(slabLabels, [], 'all'), labelsStore.materialMask);
    end
    slabDepth = size(slabLabels, 3);
    zLast = zFirst + slabDepth - 1;

    % setData63 takes full-resolution coordinates and maps them to the level
    scaleFactors = labelsStore.modelScaleFactors(predictedLevel, :);   % [y x z]
    fullSize = labelsStore.modelLevelSizes(1, :);
    writeOptions = struct('pyramidLevel', predictedLevel, ...
        'y', [1 fullSize(1)], 'x', [1 fullSize(2)], ...
        'z', [(zFirst-1)*scaleFactors(3)+1, min(fullSize(3), zLast*scaleFactors(3))]);
    labelsStore.setData63(slabLabels, 'everything', 3, [], writeOptions);

    if ~strcmp(obj.ZarrModelOpt.DownsampleMethod, 'mode'); return; end
    % replace the nearest-neighbour coarser levels written by setData63 with a
    % majority vote over blocks of the slab
    for coarserLevel = predictedLevel+1:size(labelsStore.modelLevelSizes, 1)
        levelSize = labelsStore.modelLevelSizes(coarserLevel, :);
        factors = labelsStore.modelScaleFactors(coarserLevel, :) ./ scaleFactors;
        blockFactors = round(factors);
        targetZ = [ceil(zFirst/factors(3)), min(levelSize(3), ceil(zLast/factors(3)))];
        targetSize = [levelSize(1), levelSize(2), targetZ(2)-targetZ(1)+1];
        if all(abs(factors - blockFactors) < 1e-9)
            % crop or pad (replicate) to whole blocks, which keeps blockReduce on
            % its vectorised path; a level of ceil(size/2) would otherwise send the
            % whole slab through its per-pixel loop
            wholeSize = targetSize .* blockFactors;
            blocks = slabLabels(1:min(end, wholeSize(1)), 1:min(end, wholeSize(2)), 1:min(end, wholeSize(3)));
            blocks = padarray(blocks, max(0, wholeSize - size(blocks, 1:3)), 'replicate', 'post');
        else
            blocks = slabLabels;   % non-integer factors: blockReduce's block-boundary loop
        end
        if targetSize(3) == size(blocks, 3)
            % Z is kept: every slice is reduced on its own (passed as channels)
            coarserLabels = io.savers.Zarr3Saver.blockReduce2D(blocks, targetSize(1), targetSize(2), @mode);
        else
            coarserLabels = io.savers.Zarr3Saver.blockReduce3D(blocks, targetSize(1), targetSize(2), targetSize(3), @mode);
        end
        labelsStore.writePackedLevel(coarserLevel, coarserLabels, [1 targetSize(1)], [1 targetSize(2)], targetZ);
    end
end
