function pairs = findNeighborPairs(layout, options)
% FINDNEIGHBORPAIRS - Find overlapping tile pairs from nominal origins and sizes.
%
% Syntax:
%   .. code-block:: matlab
%
%      pairs = utils.stitch.findNeighborPairs(layout)
%      pairs = utils.stitch.findNeighborPairs(layout, options)
%
% Tests all tile pairs for rectangle overlap using their nominal origins and
% tile sizes.  Within-layer pairs are tagged ``'x'`` (primarily side-by-side,
% ``abs(dx) >= abs(dy)``) or ``'y'`` (primarily top-bottom).  Pairs in adjacent Z-layers
% whose XY footprints overlap are tagged ``'z'``.
%
% Pairs with overlap smaller than ``options.minOverlapPx`` pixels in both
% dimensions are excluded.
%
% **Section layouts** (from :func:`utils.stitch.splitLayoutIntoSections`, every
% entry carrying ``.stageTile``): testing every pair of pieces is
% ``O(N^2)`` - 2.5e9 tests for 100 tiles x 500 sections - so the pairs are
% BUILT instead. The in-plane pairs of the first section are found as above and
% repeated for every section, and each piece is paired with the same tile's
% piece in the next section (``'z'``). The result equals the all-pairs search
% on the same layout (pinned by a test) whenever neighbouring tiles overlap by
% less than half a tile, i.e. for any real montage; at half or more the search
% would also pair DIFFERENT tiles across sections, which the builder leaves out
% on purpose - the section-to-section link is the same stage position. A section
% layout with a piece missing falls back to the all-pairs search.
%
% Input Arguments:
%   - **layout** - struct array as returned by ``buildLayoutGrid`` etc.
%   - **options** *(optional)* - struct with fields:
%
%     - ``.minOverlapPx`` - [double] minimum overlap in pixels (default: ``16``)
%     - ``.linkSections`` - [logical] section layouts only: pair each piece with
%       the same tile's piece in the next section (default: ``true``). ``false``
%       for slices unrelated to each other - in-plane pairs only, every section
%       stitched on its own.
%
% Output Arguments:
%   - **pairs** - struct array with fields:
%
%     - ``.i`` - [double] index of first tile in the pair
%     - ``.j`` - [double] index of second tile in the pair
%     - ``.direction`` - [char] ``'x'``, ``'y'``, or ``'z'``
%     - ``.nominal`` - [double] ``[dy dx dz]`` = ``layout(j).nomOrigin - layout(i).nomOrigin``
%
% **Example** - find all neighbor pairs in a simple 2x2 grid:
%
%   .. code-block:: matlab
%
%      opts.rows = 2; opts.cols = 2;
%      opts.tileOrder = 'Horizontal'; opts.overlapX = 10; opts.overlapY = 10;
%      layout = utils.stitch.buildLayoutGrid(files, opts);
%      pairs  = utils.stitch.findNeighborPairs(layout);
%

arguments
    layout  struct
    options struct = struct()
end
if ~isfield(options, 'minOverlapPx'); options.minOverlapPx = 16; end
if ~isfield(options, 'linkSections'); options.linkSections = true; end

minOverlapPixels = options.minOverlapPx;

if numel(layout) < 2
    pairs = struct('i', {}, 'j', {}, 'direction', {}, 'nominal', {});
    return;
end

if isfield(layout, 'stageTile') && ~any(arrayfun(@(piece) isempty(piece.stageTile), layout))
    [pairs, isCompleteGrid] = sectionPairs(layout, options);
    if isCompleteGrid; return; end
end

numTiles = numel(layout);
pairList = struct('i', {}, 'j', {}, 'direction', {}, 'nominal', {});
pairCount = 0;

for tileA = 1:(numTiles - 1)
    for tileB = (tileA + 1):numTiles
        originA = layout(tileA).nomOrigin;   % [y x z]
        originB = layout(tileB).nomOrigin;
        sizeA   = layout(tileA).tileSize;    % [H W D C]
        sizeB   = layout(tileB).tileSize;

        zLayerA = layout(tileA).zLayer;
        zLayerB = layout(tileB).zLayer;
        zDiff   = abs(zLayerB - zLayerA);

        if zDiff > 1
            % Only check adjacent layers
            continue;
        end

        % Compute XY overlap extents
        overlapY = computeIntervalOverlap(originA(1), originA(1) + sizeA(1) - 1, ...
                                          originB(1), originB(1) + sizeB(1) - 1);
        overlapX = computeIntervalOverlap(originA(2), originA(2) + sizeA(2) - 1, ...
                                          originB(2), originB(2) + sizeB(2) - 1);

        if zDiff == 0
            % Same layer: require minimum overlap in both X and Y
            if overlapY < minOverlapPixels || overlapX < minOverlapPixels
                continue;
            end
            % Tag direction by which offset is larger
            deltaX = abs(originB(2) - originA(2));
            deltaY = abs(originB(1) - originA(1));
            if deltaX >= deltaY
                direction = 'x';
            else
                direction = 'y';
            end
            % Skip DIAGONAL neighbours: a direct x/y neighbour overlaps most of
            % the perpendicular tile extent, a diagonal one only a small corner.
            % Corner overlaps carry no information the direct edges do not, and
            % their tiny crops routinely produce confident-but-wrong shifts.
            if direction == 'x'
                perpendicularFraction = overlapY / min(sizeA(1), sizeB(1));
            else
                perpendicularFraction = overlapX / min(sizeA(2), sizeB(2));
            end
            if perpendicularFraction < 0.5
                continue;
            end
        else
            % Adjacent layers: require XY footprint overlap in both dims
            if overlapY < minOverlapPixels || overlapX < minOverlapPixels
                continue;
            end
            % Cross-layer edges are kept ONLY between tiles at (near) the same XY
            % position - large overlap in BOTH dims. A thin XY strip (tiles offset
            % in one axis) or a corner (offset in both) yields an unreliable dz
            % from its narrow projected crop, and adds nothing: the within-layer
            % edges already connect the tiles inside each layer, and one
            % same-position z-edge per stacked tile connects the layers - together
            % a fully connected graph. So a stray weak z-edge only injects noise.
            fractionY = overlapY / min(sizeA(1), sizeB(1));
            fractionX = overlapX / min(sizeA(2), sizeB(2));
            if fractionY < 0.5 || fractionX < 0.5
                continue;
            end
            direction = 'z';
        end

        nominal = originB - originA;   % [dy dx dz]

        pairCount = pairCount + 1;
        pairList(pairCount).i         = tileA;
        pairList(pairCount).j         = tileB;
        pairList(pairCount).direction = direction;
        pairList(pairCount).nominal   = nominal;
    end
end

pairs = pairList;

end

% =========================================================================
function [pairs, isCompleteGrid] = sectionPairs(layout, options)
% SECTIONPAIRS - Pairs of a section layout, built from (stage tile, section).
% isCompleteGrid is false - and the caller falls back to the all-pairs search -
% unless every stage tile has exactly one piece in every section.
pairs = struct('i', {}, 'j', {}, 'direction', {}, 'nominal', {});
isCompleteGrid = false;
stageTiles = [layout.stageTile];
sections = [layout.zLayer];
stageIds = unique(stageTiles);
sectionIds = unique(sections);
% pieceAt(t, s) = layout index of stage tile stageIds(t) in section sectionIds(s)
[~, stageRow] = ismember(stageTiles, stageIds);
[~, sectionCol] = ismember(sections, sectionIds);
pieceAt = zeros(numel(stageIds), numel(sectionIds));
pieceAt(sub2ind(size(pieceAt), stageRow, sectionCol)) = 1:numel(layout);
if any(pieceAt(:) == 0) || numel(layout) ~= numel(pieceAt); return; end
isCompleteGrid = true;

% In-plane template: the all-pairs search on the first section alone.
firstSection = pieceAt(:, 1)';
template = utils.stitch.findNeighborPairs(rmfield(layout(firstSection), 'stageTile'), options);
templateI = stageRow(firstSection([template.i]));
templateJ = stageRow(firstSection([template.j]));

numSections = numel(sectionIds);
numPairs = numel(template) * numSections + options.linkSections * numel(stageIds) * (numSections - 1);
if numPairs == 0; return; end
pairs(numPairs).i = [];   % preallocate
pairCount = 0;
for sectionIdx = 1:numSections
    for templateIdx = 1:numel(template)
        pieceI = pieceAt(templateI(templateIdx), sectionIdx);
        pieceJ = pieceAt(templateJ(templateIdx), sectionIdx);
        pairCount = pairCount + 1;
        pairs(pairCount).i = pieceI;
        pairs(pairCount).j = pieceJ;
        pairs(pairCount).direction = template(templateIdx).direction;
        pairs(pairCount).nominal = layout(pieceJ).nomOrigin - layout(pieceI).nomOrigin;
    end
end
for stageIdx = 1:numel(stageIds) * options.linkSections
    for sectionIdx = 1:numSections - 1
        pieceI = pieceAt(stageIdx, sectionIdx);
        pieceJ = pieceAt(stageIdx, sectionIdx + 1);
        pairCount = pairCount + 1;
        pairs(pairCount).i = pieceI;
        pairs(pairCount).j = pieceJ;
        pairs(pairCount).direction = 'z';
        pairs(pairCount).nominal = layout(pieceJ).nomOrigin - layout(pieceI).nomOrigin;
    end
end
end

% =========================================================================
function overlapLength = computeIntervalOverlap(aStart, aEnd, bStart, bEnd)
% Compute the length of the overlap between interval [aStart,aEnd] and [bStart,bEnd].
% Returns 0 when they do not overlap.
overlapLength = max(0, min(aEnd, bEnd) - max(aStart, bStart) + 1);
end
