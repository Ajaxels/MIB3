function writeModelStore(obj, outputLabels, storePath, pyramid, zarrFormat, materialNames, materialColors)
% WRITEMODELSTORE - write a prediction of one pyramid level as a BigData model store.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.writeModelStore(outputLabels, storePath, pyramid, zarrFormat, materialNames, materialColors)
%
% The "Zarr3 (BigData model)" output for a prediction held in memory whole: the
% semantic workflows with images that are not zarr (``startPredictionBlockedImage``)
% and 2D Instance with images that are not zarr (``startPredictionInstances``).
% Zarr images are predicted and written slab by slab instead
% (``predictZarrStore``, and the per-slab writes of ``startPredictionInstances``).
%
% Creates the store with ``createModelStore`` (layout, pyramid, settings of
% ``obj.ZarrModelOpt``), writes ``outputLabels`` as one slab with
% ``writeModelStoreSlab`` (the coarser levels, the ``'mode'`` downsampling) and
% closes it, which persists the level map and the material names.
%
% A store that fails to write is removed together with its level-map side
% file, so no partial store is left that would open as a valid model, and the
% error is rethrown.
%
% Input Arguments:
%   - **outputLabels** - [numeric] labels at the size of the predicted level,
%     ``[height, width]`` or ``[height, width, depth]``; 0 = background
%   - **storePath** - [char] model store to create (``.zarr3`` or ``.zarr2``);
%     an existing folder is replaced, the caller confirms that beforehand
%   - **pyramid** - [struct] pyramid of the source image or ``[]``, see
%     ``createModelStore``
%   - **zarrFormat** - [numeric] 2 or 3
%   - **materialNames** - [cell] class names without Exterior; ``{}`` for an
%     instance model
%   - **materialColors** - [numeric] ``[N x 3]`` colours of the classes, at least
%     one row per name; ignored for an instance model

    [labelsStore, predictedLevel] = obj.createModelStore(storePath, pyramid, size(outputLabels, 1:3), ...
        zarrFormat, materialNames, materialColors);
    try
        obj.writeModelStoreSlab(labelsStore, outputLabels, predictedLevel, 1);
        labelsStore.closeStore();   % persists the level map and the material names
    catch err
        if isfolder(storePath); rmdir(storePath, 's'); end
        levelMapPath = core.MibBigDataLabels.levelMapPathFor(storePath);
        if isfile(levelMapPath); delete(levelMapPath); end
        rethrow(err);
    end
end
