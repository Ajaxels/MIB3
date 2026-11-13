function slab = readZarrSlab(levelArray, storeInfo, levelIndex, zRange)
% READZARRSLAB - read a Z-slab of one pyramid level of a zarr image store.
%
% Syntax:
%   .. code-block:: matlab
%
%      levelArray = deepmib.readZarrSlab([], storeInfo, levelIndex);   % open the level once
%      slab = deepmib.readZarrSlab(levelArray, storeInfo, levelIndex, zRange)
%
% Zarr stores are larger than memory as a rule, so DeepMIB predicts them slab by
% slab (``MibDeep.predictZarrStore``, ``MibDeep.startPredictionInstances``) and
% never loads a level whole. A slab spans the full XY extent and all channels of
% the level. The read goes straight to the array (``io.zarr.Array``, v2 or v3)
% and not through ``io.zarr.ChunkCache``: a slab is read once and is usually much
% larger than the cache, which would only copy it chunk by chunk. A slab aligned
% to the Z chunks of the level reads every chunk once.
%
% A read that fails with an error of the operating system (``os error`` in the
% message: a network share that drops or garbles a packet, e.g. "Invalid
% Signature", 0x80090006, of SMB signing during a multi-GB slab read) is retried
% three times, after 10, 30 and 60 s, with the level reopened; each retry is
% printed to the command window. Other errors (a wrong range, a broken store) are
% raised at once.
%
% A store opened with a region (``levelRegionOrigins`` other than ones) is read
% at the offset of the region, as ``core.MibVirtualImage.getDataZarr`` does;
% ``zRange`` is then in region coordinates.
%
% Input Arguments:
%   - **levelArray** - [io.zarr.Array] the opened level, from a call with
%     ``zRange`` omitted; ``[]`` to open it
%   - **storeInfo** - [struct] one element of the ``zarrStores`` output of
%     ``MibDeep.checkZarrStores``: ``.groupPath``, ``.levelNames``,
%     ``.levelRegionOrigins``, ``.colors``, ``.imgClass`` and
%     ``.pyramid.levelImageSizes``, ``.pyramid.axisOrder``
%   - **levelIndex** - [numeric] 1-based pyramid level
%   - **zRange** - *(optional)* [1x2 numeric] first and last slice, 1-based,
%     inclusive, within the level
%
% Output Arguments:
%   - **slab** - [io.zarr.Array] the opened level when ``zRange`` is omitted;
%     otherwise [numeric] ``[height, width, depth, colors]`` of ``storeInfo.imgClass``
%
% Usage:
%
%   **Example 1** - read slices 1-16 of level 2
%
%   .. code-block:: matlab
%
%      levelArray = deepmib.readZarrSlab([], zarrStores(1), 2);
%      slab = deepmib.readZarrSlab(levelArray, zarrStores(1), 2, [1 16]);

    groupPath = char(storeInfo.groupPath);
    levelPath = storeInfo.levelNames{levelIndex};
    if isempty(levelPath)
        fullPath = groupPath;
    elseif startsWith(groupPath, 'http://') || startsWith(groupPath, 'https://')
        fullPath = [groupPath, '/', levelPath];
    else
        fullPath = fullfile(groupPath, levelPath);
    end
    if isempty(levelArray)
        levelArray = io.zarr.Array(fullPath);
    end
    if nargin < 4
        slab = levelArray;
        return;
    end

    levelSize = storeInfo.pyramid.levelImageSizes(levelIndex, :);
    regionOrigin = storeInfo.levelRegionOrigins(levelIndex, :);     % [y x z], 1-based
    axisRanges.y = [1 levelSize(1)] + regionOrigin(1) - 1;
    axisRanges.x = [1 levelSize(2)] + regionOrigin(2) - 1;
    axisRanges.z = zRange + regionOrigin(3) - 1;
    axisRanges.c = [1 storeInfo.colors];
    axisRanges.t = [1 1];
    bbox = io.loaders.OmeZarrMetadataUtils.buildZarrBbox(storeInfo.pyramid.axisOrder, axisRanges);
    % a read error reported by the operating system (a network share that drops or
    % garbles a packet, "Invalid Signature" of SMB signing) is retried with the
    % level reopened; any other error is raised at once
    retryPauses = [10 30 60];   % seconds
    for attempt = 1:numel(retryPauses) + 1
        try
            raw = levelArray.read(bbox);
            break;
        catch err
            if attempt > numel(retryPauses) || ~contains(err.message, 'os error', 'IgnoreCase', true)
                rethrow(err);
            end
            fprintf('DeepMIB: reading slices %d-%d of %s failed (%s), retry %d of %d in %d s\n', ...
                zRange(1), zRange(2), fullPath, strtrim(err.message), attempt, numel(retryPauses), retryPauses(attempt));
            pause(retryPauses(attempt));
            levelArray = io.zarr.Array(fullPath);
        end
    end
    slab = permute(raw, io.loaders.OmeZarrMetadataUtils.computePermutation(storeInfo.pyramid.axisOrder));
    if ~isa(slab, storeInfo.imgClass); slab = cast(slab, storeInfo.imgClass); end
end
