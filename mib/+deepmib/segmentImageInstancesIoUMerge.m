function labelMap = segmentImageInstancesIoUMerge(img, net, options)
% SEGMENTIMAGEINSTANCESIOUMERGE - Tile an image, segment instances per tile and IoU-merge across seams.
%
% Syntax:
%   .. code-block:: matlab
%
%      labelMap = deepmib.segmentImageInstancesIoUMerge(img, net, options)
%
% Alternative to the centroid-in-core stitching (deepmib.segmentBlockedImageInstances) for
% 2D instance segmentation of large / whole-slide images. The image is split into a grid of
% core tiles, each read with a surrounding border of context so that neighbouring tile
% extents share an **overlap band**. ``segmentObjects`` runs on every bordered tile and
% **all** detections are kept (not only the centroid-in-core ones). Detections from
% neighbouring tiles are then compared **inside the shared overlap band**: if both tiles
% detected the same object, their masks are nearly identical within the band, so an
% in-band IoU (or intersection-over-smaller-area, IoA) above the threshold links them into
% one instance. Links are resolved globally with union-find and each merged group is
% painted with a single label.
%
% Compared with centroid-in-core, this lifts the "overlap must exceed the largest object"
% restriction: an object spanning several tiles is detected piecewise and its fragments are
% merged, so only the band width (not the object size) matters for correct stitching.
% The overlap band must still be wide enough for the network to produce consistent masks
% in it (a few tens of pixels in practice).
%
% Input Arguments:
%   - **img** - ``[height, width, 3] uint8`` image to segment (RGB, native resolution)
%   - **net** - trained ``solov2`` detector
%   - **options** - structure of parameters:
%
%     - ``.coreSize`` - ``[h, w]`` tile core size (grid stride), as used by the
%       centroid-in-core mode
%     - ``.borderSize`` - ``[h, w]`` border (overlap) added on each side of the core;
%       neighbouring tile extents share a band of ``2*borderSize`` pixels
%     - ``.threshold`` - confidence threshold for ``segmentObjects``
%     - ``.executionEnvironment`` - ``'auto'`` | ``'gpu'`` | ``'cpu'``
%     - ``.iouThreshold`` - *(optional, default 0.5)* link two detections when their
%       in-band IoU exceeds this
%     - ``.ioaThreshold`` - *(optional, default 0.8)* link when the in-band intersection
%       over the smaller in-band area exceeds this (catches a truncated fragment fully
%       contained in the neighbour's complete mask). Applied **only** when the smaller
%       detection is itself truncated by its tile, see the note below
%     - ``.minOverlapPixels`` - *(optional, default 5)* absolute minimum in-band
%       intersection to consider a link, guards against spurious 1-2 px overlaps
%     - ``.minSplitArea`` - *(optional, default 100)* after painting, each label is split
%       into its connected components so that one index never covers two separate objects;
%       components smaller than this many pixels are dropped as speckle. Set to 0 to keep
%       every component
%     - ``.segmentFcn`` - *(optional)* ``[masks, labels, scores] = fcn(tileImg)`` override
%       of the ``segmentObjects`` call, used by unit tests to validate the stitching
%       without a trained network
%
% Why the IoA criterion is restricted to truncated detections:
% SOLOv2 occasionally returns a single detection whose mask spans two neighbouring objects.
% Containment (IoA) is 1.0 for every smaller detection that falls inside such a mask, no
% matter how little of it that explains, so an unrestricted IoA link lets one spanning
% detection bridge two unrelated objects through the union-find - measured on a mitochondria
% dataset, this welded objects up to 500 px apart and hid ~3-5% of all instances. IoA exists
% only to rescue a fragment cut off by a tile edge, and such a fragment always touches its
% own tile extent; a detection lying clear of the tile border is a different object, not a
% truncation, so for it only the symmetric IoU criterion applies.
%
% Output Arguments:
%   - **labelMap** - ``[height, width] uint32`` instance label map (background 0). Each ID
%     is exactly one connected object; the final component split also renumbers the IDs to
%     1..N, so the relabelling the caller does (startPredictionInstances) is a no-op here

% Updates
%

if ~isfield(options, 'iouThreshold');     options.iouThreshold = 0.5; end
if ~isfield(options, 'ioaThreshold');     options.ioaThreshold = 0.8; end
if ~isfield(options, 'minOverlapPixels'); options.minOverlapPixels = 5; end
if ~isfield(options, 'minSplitArea');     options.minSplitArea = 100; end
if ~isfield(options, 'segmentFcn')
    options.segmentFcn = @(tileImg) segmentObjects(net, tileImg, ...
        'Threshold', options.threshold, ...
        'SelectStrongest', true, ...
        'ExecutionEnvironment', options.executionEnvironment);
end

[imgHeight, imgWidth, ~] = size(img);
coreSize = options.coreSize(1:2);
borderSize = options.borderSize(1:2);
labelMap = zeros(imgHeight, imgWidth, 'uint32');

numTileRows = max(1, ceil(imgHeight/coreSize(1)));
numTileCols = max(1, ceil(imgWidth/coreSize(2)));

% pad the image to a full grid of cores plus the surrounding border
% ('replicate' is safe for any pad size, unlike 'symmetric')
padBottom = numTileRows*coreSize(1) - imgHeight;
padRight  = numTileCols*coreSize(2) - imgWidth;
paddedImg = padarray(img, [borderSize(1), borderSize(2), 0], 'replicate', 'pre');
paddedImg = padarray(paddedImg, [borderSize(1)+padBottom, borderSize(2)+padRight, 0], 'replicate', 'post');
tileHeight = coreSize(1) + 2*borderSize(1);
tileWidth  = coreSize(2) + 2*borderSize(2);

% -- Pass 1: segment every bordered tile, collect all detections in global coordinates
% Each detection is stored as a bounding box + cropped mask (memory-light for whole slides)
detBBox = zeros(0, 4);      % [ymin ymax xmin xmax] in original image coordinates
detMask = {};               % cropped logical masks matching detBBox
detScore = zeros(0, 1);
detTruncated = false(0, 1); % the mask runs into its own tile extent, i.e. the object is cut
tileDetIds = cell(numTileRows, numTileCols);    % detection indices per tile
tileExtent = cell(numTileRows, numTileCols);    % clipped tile extent [ymin ymax xmin xmax]

for tileRow = 1:numTileRows
    for tileCol = 1:numTileCols
        % tile origin offsets: original coordinate = tile-local coordinate + offset
        offsetY = (tileRow-1)*coreSize(1) - borderSize(1);
        offsetX = (tileCol-1)*coreSize(2) - borderSize(2);
        tileExtent{tileRow, tileCol} = [max(1, offsetY+1), min(imgHeight, offsetY+tileHeight), ...
                                        max(1, offsetX+1), min(imgWidth,  offsetX+tileWidth)];

        rowRange = (tileRow-1)*coreSize(1) + (1:tileHeight);    % in padded coordinates
        colRange = (tileCol-1)*coreSize(2) + (1:tileWidth);
        tileData = paddedImg(rowRange, colRange, :);

        [masks, ~, scores] = options.segmentFcn(tileData);
        if isempty(scores); continue; end

        % tile-local sub-rectangle that maps into the original image (excludes padding)
        localRow1 = max(1, 1-offsetY);  localRow2 = min(tileHeight, imgHeight-offsetY);
        localCol1 = max(1, 1-offsetX);  localCol2 = min(tileWidth,  imgWidth-offsetX);

        for maskId = 1:numel(scores)
            maskInImage = masks(localRow1:localRow2, localCol1:localCol2, maskId);
            if ~any(maskInImage(:)); continue; end      % detection fully inside the padding
            rowsAny = any(maskInImage, 2);
            colsAny = any(maskInImage, 1);
            boxRow1 = find(rowsAny, 1, 'first');    boxRow2 = find(rowsAny, 1, 'last');
            boxCol1 = find(colsAny, 1, 'first');    boxCol2 = find(colsAny, 1, 'last');

            detBBox(end+1, :) = [boxRow1+localRow1-1+offsetY, boxRow2+localRow1-1+offsetY, ...
                                 boxCol1+localCol1-1+offsetX, boxCol2+localCol1-1+offsetX]; %#ok<AGROW>
            detMask{end+1, 1} = maskInImage(boxRow1:boxRow2, boxCol1:boxCol2); %#ok<AGROW>
            detScore(end+1, 1) = scores(maskId); %#ok<AGROW>
            % a detection reaching the edge of its own tile extent is cut by that edge, so
            % it may be only a fragment of an object the neighbouring tile sees in full;
            % edges that coincide with the image border do not truncate anything
            extent = tileExtent{tileRow, tileCol};
            bbox = detBBox(end, :);
            detTruncated(end+1, 1) = ...
                (bbox(1) <= extent(1) && extent(1) > 1) || (bbox(2) >= extent(2) && extent(2) < imgHeight) || ...
                (bbox(3) <= extent(3) && extent(3) > 1) || (bbox(4) >= extent(4) && extent(4) < imgWidth); %#ok<AGROW>
            tileDetIds{tileRow, tileCol}(end+1) = size(detBBox, 1);
        end
    end
end

numDetections = size(detBBox, 1);
if numDetections == 0; return; end

% -- Pass 2: link detections of neighbouring tiles that agree inside the shared band
% Tiles up to maxReach apart can share a band (extent = core + 2*border, stride = core)
maxReachRow = floor((coreSize(1) + 2*borderSize(1) - 1) / coreSize(1));
maxReachCol = floor((coreSize(2) + 2*borderSize(2) - 1) / coreSize(2));
parent = (1:numDetections)';    % union-find over all detections

for tileRow = 1:numTileRows
    for tileCol = 1:numTileCols
        if isempty(tileDetIds{tileRow, tileCol}); continue; end
        for deltaRow = 0:maxReachRow
            for deltaCol = -maxReachCol:maxReachCol
                % count each tile pair once: forward neighbours only
                if deltaRow == 0 && deltaCol <= 0; continue; end
                nbRow = tileRow + deltaRow;
                nbCol = tileCol + deltaCol;
                if nbRow > numTileRows || nbCol < 1 || nbCol > numTileCols; continue; end
                if isempty(tileDetIds{nbRow, nbCol}); continue; end

                % shared overlap band between the two tile extents
                band = localRectIntersect(tileExtent{tileRow, tileCol}, tileExtent{nbRow, nbCol});
                if isempty(band); continue; end

                for detA = tileDetIds{tileRow, tileCol}
                    [~, areaA] = localCropMaskToRect(detBBox(detA,:), detMask{detA}, band);
                    if areaA < options.minOverlapPixels; continue; end
                    boxA = localRectIntersect(detBBox(detA,:), band);
                    for detB = tileDetIds{nbRow, nbCol}
                        if localFind(parent, detA) == localFind(parent, detB); continue; end
                        boxAB = localRectIntersect(boxA, detBBox(detB,:));
                        if isempty(boxAB); continue; end
                        [~, areaB] = localCropMaskToRect(detBBox(detB,:), detMask{detB}, band);
                        if areaB < options.minOverlapPixels; continue; end
                        % align both masks on the common rectangle and score the in-band overlap
                        subA = localCropMaskToRect(detBBox(detA,:), detMask{detA}, boxAB);
                        subB = localCropMaskToRect(detBBox(detB,:), detMask{detB}, boxAB);
                        interArea = nnz(subA & subB);
                        if interArea < options.minOverlapPixels; continue; end
                        iou = interArea / (areaA + areaB - interArea);
                        ioa = interArea / min(areaA, areaB);
                        % containment only means "same object" when the contained detection
                        % is a truncated fragment; otherwise a mask spanning two objects
                        % scores ioa = 1 against both and bridges them (see the note above)
                        if areaA <= areaB; smallerDet = detA; else; smallerDet = detB; end
                        if iou >= options.iouThreshold || ...
                                (detTruncated(smallerDet) && ioa >= options.ioaThreshold)
                            parent = localUnion(parent, detA, detB);
                        end
                    end
                end
            end
        end
    end
end

% -- Pass 3: paint merged groups, low-score groups first so stronger ones win conflicts
root = localFindAll(parent);
[~, ~, groupId] = unique(root);
groupScore = accumarray(groupId, detScore, [], @max);
[~, paintOrder] = sortrows([groupScore(groupId), detScore], [1 2]);
for detId = paintOrder'
    box = detBBox(detId, :);
    region = labelMap(box(1):box(2), box(3):box(4));
    region(detMask{detId}) = uint32(groupId(detId));
    labelMap(box(1):box(2), box(3):box(4)) = region;
end

% -- Pass 4: one index per connected object
% A group can still cover several separate objects: a single detection whose mask spans two
% of them needs no link at all to do it, and painting can cut a group in two when a stronger
% group overwrites the pixels that joined it. Splitting each label into its connected
% components makes the count right in both cases; the tiny leftovers this exposes are
% thresholding speckle rather than objects, so they are dropped.
labelMap = uint32(utils.instances.splitDisconnected(labelMap, ...
    struct('connectivity', 8, 'minObjectPixels', options.minSplitArea)));
end

% =====================================================================
function rect = localRectIntersect(rectA, rectB)
% intersect two [ymin ymax xmin xmax] rectangles; [] when disjoint
rect = [max(rectA(1), rectB(1)), min(rectA(2), rectB(2)), ...
        max(rectA(3), rectB(3)), min(rectA(4), rectB(4))];
if rect(1) > rect(2) || rect(3) > rect(4); rect = []; end
end

% =====================================================================
function [sub, cnt] = localCropMaskToRect(bbox, mask, rect)
% crop a bbox-anchored mask to a global rectangle clipped to the bbox
clipped = localRectIntersect(bbox, rect);
if isempty(clipped); sub = false(0); cnt = 0; return; end
sub = mask(clipped(1)-bbox(1)+1 : clipped(2)-bbox(1)+1, ...
           clipped(3)-bbox(3)+1 : clipped(4)-bbox(3)+1);
cnt = nnz(sub);
end

% =====================================================================
function parent = localUnion(parent, a, b)
rootA = localFind(parent, a);
rootB = localFind(parent, b);
if rootA ~= rootB
    if rootA < rootB; parent(rootB) = rootA; else; parent(rootA) = rootB; end
end
end

function r = localFind(parent, x)
r = x;
while parent(r) ~= r; r = parent(r); end
end

function root = localFindAll(parent)
% fully flatten every node to its root
root = parent;
changed = true;
while changed
    newRoot = root(root);
    changed = ~isequal(newRoot, root);
    root = newRoot;
end
end
