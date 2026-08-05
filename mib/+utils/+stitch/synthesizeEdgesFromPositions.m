function edges = synthesizeEdgesFromPositions(layout, positions)
% SYNTHESIZEEDGESFROMPOSITIONS - Derive the edge set implied by an imported placement.
%
% Syntax:
%   .. code-block:: matlab
%
%      edges = utils.stitch.synthesizeEdgesFromPositions(layout, positions)
%
% A layout source that imports a vendor's FINISHED tile placement (Fibics Atlas
% ``.ve-updates``, SerialEM ``AlignedPieceCoords``) can arrive with positions but
% no pairwise measurements. Positions alone are not enough state to hand the rest
% of the pipeline:
%
%   - :meth:`controllers.Stitching.stitchBtn_Callback` fills an EMPTY edge set by
%     running a full measure pass before it ever looks at the positions, which
%     would throw the import away and pay for a registration that changes nothing;
%   - the seam inspector reviews edges, so with none it has nothing to show;
%   - the alignment quality chip re-derives from the worst valid edge.
%
% The edges the placement implies supply all three, and they are self-consistent
% by construction: re-solving from them reproduces the imported positions exactly.
%
% Input Arguments:
%   - **layout** - [struct array] tile layout (see :func:`utils.stitch.buildLayoutGrid`).
%   - **positions** - [N x 3 double] imported origins ``[y x z]``, one row per tile.
%
% Output Arguments:
%   - **edges** - struct array per the edge contract, one entry per neighbouring
%     pair found by :func:`utils.stitch.findNeighborPairs`. Every edge is marked
%     ``.valid = true`` with ``.quality = 1`` - the placement is being taken as
%     given, and it is :func:`utils.stitch.scoreSeams` (run by the caller) that
%     checks it against the pixels.
%
% **Example** - make an imported placement reviewable:
%
%   .. code-block:: matlab
%
%      edges = utils.stitch.synthesizeEdgesFromPositions(layout, positions);
%
% See also utils.stitch.buildLayoutAtlas, utils.stitch.buildLayoutMdoc,
% utils.stitch.findNeighborPairs

arguments
    layout    struct
    positions double
end

pairs = utils.stitch.findNeighborPairs(layout, struct('minOverlapPx', 16));

% A SCALAR template, taken once: copying the accumulating `edges` instead would
% make each new entry as long as the array so far, and the append would fail.
edgeTemplate = struct('i', 0, 'j', 0, 'direction', 'x', 'nominal', [0 0 0], ...
    'measured', [0 0 0], 'quality', 0, 'valid', false, 'tform', [], ...
    'source', 'auto', 'seamScore', [], 'dzHint', 0);
edges = edgeTemplate;
edges(1) = [];

for pairIdx = 1:numel(pairs)
    newEdge = edgeTemplate;
    newEdge.i         = pairs(pairIdx).i;
    newEdge.j         = pairs(pairIdx).j;
    newEdge.direction = pairs(pairIdx).direction;
    newEdge.nominal   = pairs(pairIdx).nominal;
    newEdge.measured  = positions(pairs(pairIdx).j, :) - positions(pairs(pairIdx).i, :);
    newEdge.quality   = 1;
    newEdge.valid     = true;
    edges(end + 1) = newEdge; %#ok<AGROW>
end

end
