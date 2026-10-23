function result = setData63(obj, dataset, type, orient, materialIndex, options)
% SETDATA63 - Write a label/mask/selection layer to the disk-backed BigData pyramid.
%
% Syntax:
%   .. code-block:: matlab
%
%      result = obj.setData63(dataset, type, orient, materialIndex, options)
%
% Override of ``core.MibLabels63.setData63``.  The incoming data is at display
% resolution and screen orientation; it is:
%
%   1. Converted back to native ``[y, x, z]`` physical order.
%   2. Resized to the **working level** (level matching ``options.magFactor``)
%      using nearest-neighbour; optionally upgraded to a **smooth, label-aware
%      signed-distance upsample** (``resizeLayerSmooth``) when the display is
%      zoomed out and ``io.zarr.Config.smoothing()`` is on.
%   3. Merged into the working level using the packed bit scheme (same logic as
%      the parent ``MibLabels63``).
%   4. Propagated **downward to all coarser levels** (cheap nearest-neighbour
%      downsample of the changed bounding box only).  Finer levels are marked
%      dirty in the level map (``matLevel``) and recomputed lazily on the next
%      ``getData63`` call, so a brush stroke at 2% zoom does not trigger a
%      full-resolution write.
%
% **Bit packing** - same scheme as ``getData63``:
% bits 1-6 = material, bit 7 = mask, bit 8 = selection (uint8 layout), or bits
% 1-14 = index, bit 15 = mask, bit 16 = selection (uint16 layout). Index values
% above ``obj.materialMask`` are not clamped and would spill into the flag bits.
%
% Input Arguments:
%   - **dataset** - [uint8|uint16|logical] layer data at display resolution, in screen
%     orientation; cast to the container class before merging.
%     Shape ``[ny, nx, nz]`` matching what ``getData63`` would return for the same
%     ``orient``/``options``.
%   - **type** *(optional)* - [char] layer to write:
%
%     - ``'labels'``    - write material index; ``materialIndex`` controls single-material
%       vs full-map mode (see below)
%     - ``'mask'``      - write binary mask (bit 7 or 15)
%     - ``'selection'`` - write binary selection (bit 8 or 16)
%     - ``'everything'``- overwrite raw packed values (undo / restore; no smoothing)
%
%     Default: ``'labels'``.
%
%   - **orient** *(optional)* - [numeric] screen orientation (``1``/``2``/``3``; see
%     ``getData63``). Default: ``3``.
%
%   - **materialIndex** *(optional)* - [numeric scalar | empty]  when non-empty and
%     ``type='labels'``, treats ``dataset`` as a binary indicator and writes only
%     the voxels where ``dataset == 1`` to material ``materialIndex`` (other materials
%     unchanged).  Pass ``[]`` to replace the full material map.
%
%   - **options** *(optional)* - [struct] with the same fields as ``getData63``:
%     ``.magFactor``, ``.pyramidLevel``, ``.x``, ``.y``, ``.z``.
%
% Output Arguments:
%   - **result** - [logical] ``true`` when at least one voxel changed and was
%     written to disk; ``false`` if the store is closed, the input is empty, or
%     the merge produced no change (early-exit, no disk I/O).
%
% **Example 1** - paint a brush mask onto the selection layer:
%
%   .. code-block:: matlab
%
%      opts.magFactor = dataset.magFactor;
%      opts.x = dataset.slices{2};
%      opts.y = dataset.slices{1};
%      opts.z = dataset.slices{3};
%      brushMask = uint8(createBrushMask(...));   % [ny nx 1] binary
%      obj.mibModel.I{1}.labels.setData63(brushMask, 'selection', 3, [], opts);
%
% **Example 2** - accept selection into material 2 (programmatic undo step):
%
%   .. code-block:: matlab
%
%      packed = obj.mibModel.I{1}.labels.getData63('everything', 3, [], opts);
%      lb = obj.mibModel.I{1}.labels;
%      packed = bitset(packed, lb.selectionBit, 0);   % clear selection bit
%      obj.mibModel.I{1}.labels.setData63(packed, 'everything', 3, [], opts);

result = false;

if nargin < 6; options = struct(); end
if nargin < 5; materialIndex = []; end
if nargin < 4; orient = []; end
if nargin < 3; type = []; end

if ~obj.exists || isempty(obj.modelArrays); return; end
if isempty(type); type = 'labels'; end
if isempty(orient); orient = 3; end
if ~strcmp(type, 'labels'); materialIndex = []; end
if isempty(dataset); return; end
if islogical(dataset(1)); dataset = uint8(dataset); end

% --- incoming data into native [y, x, z] order ----------------------------
% getData63 permutes physical [y x z] -> screen orientation; invert that here
% so the incoming screen-oriented block returns to native [y x z].
if orient == 1     % zx [z,x,y]
    dataset = pagetranspose(permute(dataset, [2 3 1 4 5]));   % == ipermute(dataset, [3 2 1 4 5]), but faster
elseif orient == 2
    dataset = ipermute(dataset, [1 3 2 4 5]);
end
dataset = reshape(dataset, size(dataset, 1), size(dataset, 2), []);   % [dy dx dz]

% --- working level + its physical region (same convention as getData63) ---
% Use the shared orientPhysRanges helper so write lands exactly where read
% takes it from, in every orientation (the two are inverses by construction).
levelIdx = obj.pickLevel(options);
[Yl, Xl, Zl] = obj.orientPhysRanges(levelIdx, orient, options);
wSize = [Yl(2)-Yl(1)+1, Xl(2)-Xl(1)+1, Zl(2)-Zl(1)+1];

% per-level scale factor [yScale xScale zScale]; used below to map the changed
% working-level sub-region back to full-resolution coords for propagation.
sf = obj.modelScaleFactors(levelIdx, :);

% --- read the working level ----------------------------------------------
before = obj.readPackedLevel(levelIdx, Yl, Xl, Zl);

% --- locate the CHANGED sub-region with a CHEAP nearest pass ---------------
% Only the voxels the edit actually altered need to be written and propagated.
% A small brush stroke (or selection→material move) at low magnification changes
% a tiny footprint even though the visible block (Yl/Xl/Zl) is the whole slice.
% Finding the changed bounding box with a nearest resize (cheap) first means the
% expensive smoothing below runs on the edit footprint only - per-stroke cost then
% scales with the edit, not the view (see development/bigdata/bigdata_logic.md).
% The smooth (signed-distance) reconstruction makes
% the stored boundary non-blocky when up-sampling display→working; 'everything'
% (undo/restore of packed bytes) is never smoothed - it must be exact.
smoothOn = io.zarr.Config.smoothing();
useSmooth = smoothOn && ~strcmp(type, 'everything');

dataNear = core.MibBigDataLabels.resizeBlockNearest(dataset, wSize);
packed = mergePacked(obj, before, dataNear, type, materialIndex);
diff = packed ~= before;
if ~any(diff(:)); result = true; return; end   % nothing changed → no disk I/O

anyY = find(any(any(diff, 2), 3));   y0 = anyY(1); y1 = anyY(end);
anyX = find(any(any(diff, 1), 3));   x0 = anyX(1); x1 = anyX(end);
anyZ = find(any(any(diff, 1), 2));   z0 = anyZ(1); z1 = anyZ(end);

% By default write the nearest result over the tight changed bbox.
subPacked = packed(y0:y1, x0:x1, z0:z1);
wY = [Yl(1)+y0-1, Yl(1)+y1-1];
wX = [Xl(1)+x0-1, Xl(1)+x1-1];
wZ = [Zl(1)+z0-1, Zl(1)+z1-1];

% --- upgrade the footprint to the SMOOTH reconstruction (footprint only) ---
% Re-run the smoothing on just the display crop that maps to the changed working
% window (plus a margin for boundary context). The display→working crop is mapped
% at the SAME global scale (wSize/displaySize) so the smoothed block stays aligned
% to the working grid; the margin region carries the data=0 background, so the
% window edges introduce no spurious changes.
dY = size(dataset, 1); dX = size(dataset, 2);
fy = wSize(1) / dY; fx = wSize(2) / dX;
if useSmooth && (fy > 1 || fx > 1)
    isLabelMap = strcmp(type, 'labels') && isempty(materialIndex);
    marg = 4;   % display-pixel margin around the footprint for smoothing context
    dy0 = max(1, floor((y0 - 1) / fy) + 1 - marg);   dy1 = min(dY, ceil(y1 / fy) + marg);
    dx0 = max(1, floor((x0 - 1) / fx) + 1 - marg);   dx1 = min(dX, ceil(x1 / fx) + marg);
    dispCrop = dataset(dy0:dy1, dx0:dx1, :);
    % working window covered by the display crop (same global scale), clamped
    wcY0 = max(1, round((dy0 - 1) * fy) + 1);   wcY1 = min(wSize(1), round(dy1 * fy));
    wcX0 = max(1, round((dx0 - 1) * fx) + 1);   wcX1 = min(wSize(2), round(dx1 * fx));
    subSize = [wcY1 - wcY0 + 1, wcX1 - wcX0 + 1, wSize(3)];
    smoothCrop = core.MibBigDataLabels.resizeLayerSmooth(dispCrop, subSize, isLabelMap);
    beforeWin = before(wcY0:wcY1, wcX0:wcX1, :);
    subPacked = mergePacked(obj, beforeWin, smoothCrop, type, materialIndex);
    wY = [Yl(1) + wcY0 - 1, Yl(1) + wcY1 - 1];
    wX = [Xl(1) + wcX0 - 1, Xl(1) + wcX1 - 1];
    wZ = [Zl(1), Zl(2)];
end

obj.writePackedLevel(levelIdx, subPacked, wY, wX, wZ);
if strcmp(type, 'labels') || strcmp(type, 'everything')
    % upper bound of the indices in use, for "next empty material" without a scan
    obj.maxIndexUsed = max(obj.maxIndexUsed, double(max(bitand(subPacked, obj.materialMask), [], 'all')));
end

% full-resolution region of the changed sub-region (for cross-level propagation)
pfY = [(wY(1)-1)*sf(1)+1, min(wY(2)*sf(1), obj.height)];
pfX = [(wX(1)-1)*sf(2)+1, min(wX(2)*sf(2), obj.width)];
pfZ = [(wZ(1)-1)*sf(3)+1, min(wZ(2)*sf(3), obj.depth)];

% --- tell the instance index where the labels changed ----------------------
% Only while an index is synced (markLabelsChanged is a no-op otherwise, but the
% diff below is not free). A 'labels' write changes labels over the written
% window by definition; an 'everything' write - undo, selection->material moves -
% may have changed only the selection or mask bits, so its labels bits are
% compared to find the real box, and a write that left them alone marks nothing.
% Above level 1 every write counts, a selection or mask stroke included: markTiles
% below makes this level authoritative for the touched tiles, and the next
% level-1 read rebuilds ALL their bits from here, labels too - measured, a
% selection stroke at level 4 over a one-pixel checkerboard of two objects
% changed 512 of its 1024 full-resolution label voxels.
if ~isempty(obj.syncedInstanceIndex) && (strcmp(type, 'labels') || strcmp(type, 'everything') || levelIdx > 1)
    labelsBox = [pfY, pfX, pfZ];
    if strcmp(type, 'everything') && levelIdx == 1
        labelsDiff = bitand(packed, obj.materialMask) ~= bitand(before, obj.materialMask);
        if any(labelsDiff(:))
            rowsChanged = find(any(any(labelsDiff, 2), 3));
            colsChanged = find(any(any(labelsDiff, 1), 3));
            planesChanged = find(any(any(labelsDiff, 1), 2));
            labelsBox = [(Yl(1)+rowsChanged(1)-2)*sf(1)+1,   min((Yl(1)+rowsChanged(end)-1)*sf(1), obj.height), ...
                         (Xl(1)+colsChanged(1)-2)*sf(2)+1,   min((Xl(1)+colsChanged(end)-1)*sf(2), obj.width), ...
                         (Zl(1)+planesChanged(1)-2)*sf(3)+1, min((Zl(1)+planesChanged(end)-1)*sf(3), obj.depth)];
        else
            labelsBox = [];
        end
    end
    if levelIdx > 1
        % ...and it does so for whole coarsest tiles, so at full resolution the
        % whole tiles can change
        [tileY, tileX, tileZ] = obj.tilesForFullRegion(labelsBox(1:2), labelsBox(3:4), labelsBox(5:6));
        tileSize = obj.modelScaleFactors(end, :);
        labelsBox = [(tileY(1)-1)*tileSize(1)+1, min(tileY(2)*tileSize(1), obj.height), ...
                     (tileX(1)-1)*tileSize(2)+1, min(tileX(2)*tileSize(2), obj.width), ...
                     (tileZ(1)-1)*tileSize(3)+1, min(tileZ(2)*tileSize(3), obj.depth)];
    end
    if ~isempty(labelsBox); obj.markLabelsChanged(labelsBox); end
end

% --- propagate the changed region to COARSER levels only -----------------
% Each edit is stored at the resolution it was drawn (the working level) plus all
% COARSER levels (a cheap downsample of the small changed region). FINER levels are
% NEVER written - they hold no information beyond the working level, so they are
% reconstructed on demand by getData63 (upsampling the coarsest level for the
% viewport). This makes a stroke cost ~ one bounded write regardless of zoom or
% slide size: a 500 px brush at 2% no longer triggers a ~600 MB full-res write.
% Durability is unaffected - every edit is persisted at its drawn resolution and
% coarser, and the coarsest level holds every edit.
obj.propagateRegion(subPacked, pfY, pfX, pfZ, levelIdx, 'coarser');

% record the working level as authoritative for the touched tiles; finer levels
% are now implicitly dirty and recomputed lazily on read (getData63) / at Save.
obj.markTiles(pfY, pfX, pfZ, levelIdx);

% keep the selection footprint box in sync so selection→material/mask moves and
% clear can scope to it instead of scanning the whole slice. 'packed' is the full
% processed region [Yl Xl Zl]; its selection bit is authoritative there.
if strcmp(type, 'selection') || strcmp(type, 'everything')
    obj.updateSelectionBBoxFromWrite(packed, Yl, Xl, Zl, levelIdx);
end

result = true;
end

% ------------------------------------------------------------------------
function packed = mergePacked(obj, packed, data, type, materialIndex)
% merge a layer into the packed block using the bit layout of obj (core.MibLabels63.setLayout)
data = reshape(cast(data, obj.containerClass), size(packed));
switch type
    case 'labels'
        if ~isempty(materialIndex)
            lowBits = bitand(packed, obj.materialMask);
            lowBits = lowBits .* cast(lowBits ~= materialIndex, 'like', lowBits);   % remove material
            lowBits(data == 1) = materialIndex;                     % write new material
            packed = bitor(bitand(packed, obj.flagsMask), lowBits);   % keep mask+selection
        else
            packed = bitor(bitand(packed, obj.flagsMask), data);      % replace all materials
        end
    case 'mask'
        packed = bitor(bitset(packed, obj.maskBit, 0), data * cast(obj.maskValue, 'like', data));
    case 'selection'
        packed = bitor(bitset(packed, obj.selectionBit, 0), data * cast(obj.selectionValue, 'like', data));
    case 'everything'
        packed = data;
end
end
