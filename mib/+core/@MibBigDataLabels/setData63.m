function result = setData63(obj, dataset, type, orient, materialIndex, options)
% SETDATA63 - write a packed layer block to the disk-backed BigData model pyramid.
%
% Override of ``core.MibLabels63.setData63``. The incoming data is at the
% displayed resolution; it is resized to the working level (the level matching
% ``options.magFactor``), merged into that level with the parent's bit logic,
% written, and then **propagated** to every other pyramid level (nearest-
% neighbour resize of the merged packed bytes) so all levels stay consistent.
%
% Input/Output: see core.MibLabels63.setData63.

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
if orient == 1
    dataset = ipermute(dataset, [2 3 1 4 5]);
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

% full-resolution physical ranges for cross-level propagation: scale the
% working-level region back up by this level's per-axis factor.
sf = obj.modelScaleFactors(levelIdx, :);
fullY = [(Yl(1)-1)*sf(1)+1, min(Yl(2)*sf(1), obj.height)];
fullX = [(Xl(1)-1)*sf(2)+1, min(Xl(2)*sf(2), obj.width)];
fullZ = [(Zl(1)-1)*sf(3)+1, min(Zl(2)*sf(3), obj.depth)];

% resize the displayed-resolution data down/up to the working level region.
% When zoomed out the brush arrives at a COARSER display resolution than the
% working level, so this is an UP-sample — use the smooth (signed-distance)
% reconstruction when enabled so the stored boundary isn't blocky at the
% working-level grid (the propagation below then carries it to other levels).
% 'everything' (undo/restore of packed bytes) is never smoothed; it must be exact.
smoothOn = io.zarr.Config.smoothing();
if smoothOn && ~strcmp(type, 'everything')
    isLabelMap = strcmp(type, 'labels') && isempty(materialIndex);
    dataLevel = core.MibBigDataLabels.resizeLayerSmooth(dataset, wSize, isLabelMap);
else
    dataLevel = core.MibBigDataLabels.resizeBlockNearest(dataset, wSize);
end

% --- read / merge / write the working level ------------------------------
packed = obj.readPackedLevel(levelIdx, Yl, Xl, Zl);
packed = mergePacked(packed, dataLevel, type, materialIndex);
obj.writePackedLevel(levelIdx, packed, Yl, Xl, Zl);

% --- propagate the merged region to every other level --------------------
% The working level is now authoritative on disk; the other levels are kept
% in sync. By default this is DEFERRED: the edit is queued and a debounce
% timer flushes it on idle (so rapid brush strokes don't pay N level-writes
% per stroke). Correctness is preserved because getData63 flushes before
% reading a stale level and closeStore flushes before releasing the store.
if obj.deferPropagation
    obj.enqueuePropagation(packed, fullY, fullX, fullZ, levelIdx);
else
    obj.propagateRegion(packed, fullY, fullX, fullZ, levelIdx);
end

result = true;
end

% ------------------------------------------------------------------------
function packed = mergePacked(packed, data, type, materialIndex)
% merge a layer into the packed uint8 block using the MibLabels63 bit scheme
data = reshape(uint8(data), size(packed));
switch type
    case 'labels'
        if ~isempty(materialIndex)
            lowBits = bitand(packed, 63);
            lowBits = lowBits .* uint8(lowBits ~= materialIndex);   % remove material
            lowBits(data == 1) = materialIndex;                     % write new material
            packed = bitor(bitand(packed, 192), lowBits);           % keep mask+selection
        else
            packed = bitor(bitand(packed, 192), data);              % replace all materials
        end
    case 'mask'
        packed = bitor(bitset(packed, 7, 0), data * 64);
    case 'selection'
        packed = bitor(bitset(packed, 8, 0), data * 128);
    case 'everything'
        packed = data;
end
end
