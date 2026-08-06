function [tforms, positions, stats] = solveGlobalAffine(layout, edges, options)
% SOLVEGLOBALAFFINE - Global per-tile affine transforms from pairwise edges (linear LS).
%
% Syntax:
%   .. code-block:: matlab
%
%      [tforms, positions, stats] = utils.stitch.solveGlobalAffine(layout, edges)
%      [tforms, positions, stats] = utils.stitch.solveGlobalAffine(layout, edges, options)
%
% Affine generalisation of :func:`utils.stitch.solveGlobalLeastSquares`. Every
% tile ``t`` gets a 2D affine map from 1-based tile-local pixel coordinates to
% global coordinates, ``x_global = L_t * x_local + p_t`` (``L_t`` 2x2, ``p_t``
% 2x1, xy order). A pairwise edge measured as the tile-local map
% ``x_j = M * x_i + c`` (``edge.tform``, from the feature-based estimator)
% pins the two tiles' maps together: a physical point seen at ``x_i`` in tile
% ``i`` and ``x_j`` in tile ``j`` must land on the same global point, which for
% all overlap points splits into
%
% - ``L_i = L_j * M``            (4 scalar rows)
% - ``p_i - p_j - L_j * c = 0``  (2 scalar rows)
%
% Both are LINEAR in the stacked unknowns ``{L_t, p_t}``, so the global solve
% stays one sparse weighted least-squares system (the BigStitcher affine model)
% - no nonlinear optimiser. Edges without a stored transform (phase-correlation
% or translation-model measurements) participate with ``M = I`` and ``c``
% synthesised from ``.measured``, so mixed edge sets are fine.
%
% The linear-part rows are scaled by a characteristic tile extent so that a
% dimensionless error in ``L`` is weighted like the pixel error it causes at
% the tile edge; without this the position rows (pixels) would numerically
% dominate the linear rows (~1).
%
% Gauge, springs and connectivity mirror the translation solver: tile 1 is
% anchored at ``L = I`` / its nominal origin; pruned edges touching a component
% disconnected from the anchor re-enter as weak springs toward nominal;
% disconnected tiles get a bridge spring; every tile gets a tiny self-spring
% (position toward nominal, linear part toward identity) for rank.
%
% **Rigid / Similarity - solved by projection, not by a nonlinear optimiser.**
% ``options.transformType`` restricts the model: after the (always-linear)
% affine solve, each tile's linear part is polar-decomposed ``L = R * S``
% (rotation x symmetric stretch, via SVD) and replaced by the closest member of
% the requested group - ``R`` for Rigid, ``s*R`` (``s`` = mean singular value,
% the Frobenius-optimal scalar) for Similarity. ``options.allowRotation = false``
% additionally locks the rotation factor to identity (``R = I`` branch of the
% same decomposition): Rigid degenerates to pure translation, Similarity to
% scale + translation, Affine keeps scale/shear but no rotation. After the
% projection the tile translations are RE-SOLVED with the projected linear
% parts held fixed - each edge then contributes the known offset
% ``pos_j - pos_i = (L_j - L_i)*[1;1] - L_j*c``, which is exactly the
% translation solver's row shape, so the refinement reuses
% :func:`utils.stitch.solveGlobalLeastSquares` (same springs/anchoring).
%
% The z axis composes additively regardless of the in-plane model (2D affine
% acts within a slice), so z origins are solved with the existing scalar path
% (:func:`utils.stitch.solveGlobalLeastSquares`) and merged into ``positions``.
%
% Input Arguments:
%   - **layout** - [struct array] tile layout with ``.nomOrigin`` (``[y x z]``).
%   - **edges** - [struct array] from :func:`utils.stitch.measureAllPairs`; uses
%     ``.i .j .measured .nominal .quality .valid`` and (when present) ``.tform``
%     (3x3 double, tile-local xy map ``i → j``).
%   - **options** *(optional)* - struct with fields:
%
%     - ``.springWeight`` - [double] weight of re-added pruned/bridge springs (default: ``0.10``)
%     - ``.nominalSpringWeight`` - [double] weight of the per-tile position self-spring
%       (default: ``0.001``; rank guard only - real weight biases the solution)
%     - ``.identitySpringWeight`` - [double] weight of the per-tile linear-part
%       self-spring toward identity (default: ``0.001``). A mild prior against
%       scale/shear drift accumulating across the mosaic.
%     - ``.transformType`` - [char] ``'Affine'`` (default) | ``'Rigid'`` |
%       ``'Similarity'`` - the group each tile's linear part is projected onto
%       after the linear solve (see above).
%     - ``.allowRotation`` - [logical] ``true`` (default) permits per-tile
%       rotation; ``false`` locks the rotation factor to identity in the
%       projection (robustness prior for stage-tiled data that cannot rotate).
%     - ``.userEdgeWeight`` - [double] weight of USER-fixed edges
%       (``edge.source = 'user'``; default: ``5.0``) - never pruned, dominate
%       conflicting automatic edges (see the translation solver's doc).
%
% Output Arguments:
%   - **tforms** - [N x 1 cell] per-tile 3x3 doubles mapping 1-based tile-local
%     xy to global xy: ``[x'; y'; 1] = tforms{t} * [x; y; 1]``. The anchor tile
%     has an identity linear part and its nominal origin.
%   - **positions** - [N x 3 double] solved ``[y x z]`` origins - the global
%     coordinate of each tile's pixel (1,1) (``L_t*[1;1] + p_t`` in yx order,
%     z from the scalar solve). Collapses to the translation-solver result when
%     every edge is a pure translation.
%   - **stats** - [struct] same shape as the translation solver's:
%     ``.residuals`` (M x 3, position mismatch per valid edge evaluated at the
%     source tile's centre), ``.rmse`` (1x3), ``.rmseTotal``, ``.nPruned``,
%     ``.nComponents``, ``.anchorComponent``, ``.disconnectedTiles``.
%
% **Example** - solve an affine-jittered grid:
%
%   .. code-block:: matlab
%
%      [tforms, positions, stats] = utils.stitch.solveGlobalAffine(layout, edges);
%      fprintf('RMSE = %.3f px\n', stats.rmseTotal);

if nargin < 3; options = struct(); end
if ~isfield(options, 'springWeight');         options.springWeight = 0.10; end
if ~isfield(options, 'nominalSpringWeight');  options.nominalSpringWeight = 0.001; end
if ~isfield(options, 'identitySpringWeight'); options.identitySpringWeight = 0.001; end
if ~isfield(options, 'transformType') || isempty(options.transformType)
    options.transformType = 'Affine';
end
if ~isfield(options, 'allowRotation'); options.allowRotation = true; end
if ~isfield(options, 'userEdgeWeight'); options.userEdgeWeight = 5.0; end

nTiles = numel(layout);
nomOrigins = reshape([layout.nomOrigin], 3, nTiles)';   % N x 3 [y x z]

tforms = repmat({eye(3)}, nTiles, 1);
positions = nomOrigins;
stats = struct('residuals', zeros(0, 3), 'rmse', [0 0 0], 'rmseTotal', 0, ...
    'nPruned', 0, 'nComponents', 1, 'anchorComponent', 1, 'disconnectedTiles', []);

if nTiles == 0; return; end

% z axis is untouched by the in-plane affine model - reuse the scalar solver for
% the z origins (and let it also compute the graph connectivity once).
[translationPositions, translationStats] = utils.stitch.solveGlobalLeastSquares(layout, edges, options);
positions(:, 3) = translationPositions(:, 3);
stats.nPruned           = translationStats.nPruned;
stats.nComponents       = translationStats.nComponents;
stats.anchorComponent   = translationStats.anchorComponent;
stats.disconnectedTiles = translationStats.disconnectedTiles;

% User-fixed edges (seam inspector): never pruned, fixed dominant weight.
userMask = false(numel(edges), 1);
validMask = false(numel(edges), 1);
for k = 1:numel(edges)
    userMask(k) = isfield(edges, 'source') && strcmp(edges(k).source, 'user');
    validMask(k) = (~isempty(edges) && isfield(edges, 'valid') && edges(k).valid) || userMask(k);
end
validEdges     = edges(validMask);
validUserFlags = userMask(validMask);
prunedEdges    = edges(~validMask);

anchorTile = 1;
disconnectedTiles = stats.disconnectedTiles;
isDisconnected = false(nTiles, 1);
isDisconnected(disconnectedTiles) = true;

% Characteristic tile extent: a dimensionless residual r in the linear part
% causes a pixel error of linearScale*r at the tile edge, so the L rows must
% enter the quadratic cost as (linearScale*r)^2 - i.e. weighted by
% linearScale^2 relative to the position rows. Under-weighting them lets the
% solver tilt L (the L*c lever arm is the tile pitch in pixels) to trade
% measurement-exactness for spring satisfaction.
tileSizes = reshape([layout.tileSize], 4, nTiles)';   % N x 4 [H W D C]
linearScale = mean(max(tileSizes(:, 1), tileSizes(:, 2)));
if ~isfinite(linearScale) || linearScale <= 0; linearScale = 1; end
linearRowWeight = linearScale^2;

% ---- assemble the sparse system over 6 unknowns per tile ----------------------
% Per-tile block [L11 L12 L21 L22 p1 p2] (xy). Rows are accumulated as triplets;
% the anchor's columns are folded into the RHS afterwards (gauge fix).
rowsAccum = struct('i', {[]}, 'j', {[]}, 'v', {[]});
targets = [];
weights = [];
nextRow = 0;

    function addRow(colIdx, coeffs, target, weight)
        nextRow = nextRow + 1;
        rowsAccum.i = [rowsAccum.i; repmat(nextRow, numel(colIdx), 1)];
        rowsAccum.j = [rowsAccum.j; colIdx(:)];
        rowsAccum.v = [rowsAccum.v; coeffs(:)];
        targets(end+1, 1) = target;
        weights(end+1, 1) = weight;
    end

    function idx = colL(tile, r, c)
        idx = 6*(tile-1) + (r-1)*2 + c;
    end

    function idx = colP(tile, r)
        idx = 6*(tile-1) + 4 + r;
    end

    function addEdgeRows(i, j, M, c, weight)
        % L_i(r,cc) - sum_k L_j(r,k)*M(k,cc) = 0
        for r = 1:2
            for cc = 1:2
                addRow([colL(i, r, cc), colL(j, r, 1), colL(j, r, 2)], ...
                       [1, -M(1, cc), -M(2, cc)], 0, weight * linearRowWeight);
            end
        end
        % p_i(r) - p_j(r) - sum_k L_j(r,k)*c(k) = 0
        for r = 1:2
            addRow([colP(i, r), colP(j, r), colL(j, r, 1), colL(j, r, 2)], ...
                   [1, -1, -c(1), -c(2)], 0, weight);
        end
    end

    function addSpringRows(tile, refTile, offsetXY, weightP, weightL)
        % Position spring: p_tile - p_ref = offsetXY (approximates the origin
        % offset; exact when both linear parts are identity).
        for r = 1:2
            addRow([colP(tile, r), colP(refTile, r)], [1, -1], offsetXY(r), weightP);
        end
        % Linear spring: L_tile - L_ref = 0 (the anchor's L is pinned to I, so
        % springs against the anchor regularise toward identity).
        for r = 1:2
            for cc = 1:2
                addRow([colL(tile, r, cc), colL(refTile, r, cc)], [1, -1], 0, weightL * linearRowWeight);
            end
        end
    end

% Valid edges, weighted by quality (user fixes: fixed dominant weight).
for k = 1:numel(validEdges)
    e = validEdges(k);
    [M, c] = edgeTransform(e);
    if validUserFlags(k)
        addEdgeRows(e.i, e.j, M, c, options.userEdgeWeight);
    else
        addEdgeRows(e.i, e.j, M, c, max(e.quality, eps));
    end
end

% Pruned edges re-enter as weak springs toward NOMINAL, but only when they touch
% a tile the valid edges leave disconnected from the anchor (same rule as the
% translation solver - elsewhere they only bias the solution).
for k = 1:numel(prunedEdges)
    e = prunedEdges(k);
    if ~isDisconnected(e.i) && ~isDisconnected(e.j); continue; end
    % p_j - p_i = nominal_xy  ==  spring from i to j with offset +nominal.
    addSpringRows(e.j, e.i, [e.nominal(2), e.nominal(1)], ...
        options.springWeight, options.springWeight);
end

% Bridge springs: pull tiles the valid graph leaves disconnected toward their
% nominal offset from the anchor.
for t = disconnectedTiles(:)'
    if t == anchorTile; continue; end
    offsetXY = [nomOrigins(t, 2) - nomOrigins(anchorTile, 2), ...
                nomOrigins(t, 1) - nomOrigins(anchorTile, 1)];
    addSpringRows(t, anchorTile, offsetXY, options.springWeight, options.springWeight);
end

% Per-tile self springs (rank guard): position toward the nominal offset from
% the anchor, linear part toward identity. Anchor rows cancel harmlessly.
for t = 1:nTiles
    offsetXY = [nomOrigins(t, 2) - nomOrigins(anchorTile, 2), ...
                nomOrigins(t, 1) - nomOrigins(anchorTile, 1)];
    addSpringRows(t, anchorTile, offsetXY, ...
        options.nominalSpringWeight, options.identitySpringWeight);
end

A = sparse(rowsAccum.i, rowsAccum.j, rowsAccum.v, nextRow, 6*nTiles);

% ---- gauge fix: pin the anchor at L = I, pixel(1,1) at its nominal origin -----
% positions convention: pos = L*[1;1] + p, so p_anchor = nomOrigin_xy - [1;1].
anchorState = [1; 0; 0; 1; ...
               nomOrigins(anchorTile, 2) - 1; ...
               nomOrigins(anchorTile, 1) - 1];
anchorCols = 6*(anchorTile-1) + (1:6);
freeCols = setdiff(1:6*nTiles, anchorCols);

bAdjusted = targets - A(:, anchorCols) * anchorState;
Afree = A(:, freeCols);

% Weighted normal equations, one coupled solve (x and y interact through L).
Wsqrt = sqrt(weights);
Aw = Afree .* Wsqrt;
bw = bAdjusted .* Wsqrt;
solution = (Aw' * Aw) \ (Aw' * bw);

fullState = zeros(6*nTiles, 1);
fullState(freeCols) = solution;
fullState(anchorCols) = anchorState;

% ---- unpack per-tile transforms and origin positions ---------------------------
for t = 1:nTiles
    block = fullState(6*(t-1) + (1:6));
    L = [block(1), block(2); block(3), block(4)];
    p = [block(5); block(6)];
    tforms{t} = [L, p; 0 0 1];
    posXY = L * [1; 1] + p;
    positions(t, 1) = posXY(2);
    positions(t, 2) = posXY(1);
end

% ---- project onto the requested transform group + translation refinement -------
% Rigid/Similarity (and the AllowRotation lock) are enforced by replacing each
% tile's linear part with its closest group member (polar/SVD decomposition),
% then re-solving the translations with the projected linear parts held fixed.
% The refinement rows have the translation solver's shape, so it is reused
% wholesale (same weights, springs, anchoring and connectivity handling).
needsProjection = ~strcmpi(options.transformType, 'Affine') || ~options.allowRotation;
if needsProjection && nTiles > 1
    for t = 1:nTiles
        tforms{t}(1:2, 1:2) = utils.stitch.projectLinearPart(tforms{t}(1:2, 1:2), ...
            options.transformType, options.allowRotation);
    end

    % Synthesize the per-edge offset implied by the projected linear parts.
    % Matching the two tile maps at a point x (tile-i local xy) gives
    %   pos_j - pos_i = (L_i - L_j*M)*x - L_j*c + (L_j - L_i)*[1;1]
    % which is exact for group-consistent data (L_i = L_j*M) and, for model
    % mismatch, is anchored at the OVERLAP centroid so the seams meet where the
    % tiles actually blend.
    refineEdges = edges;
    for k = 1:numel(edges)
        [M, c] = edgeTransform(edges(k));
        Li = tforms{edges(k).i}(1:2, 1:2);
        Lj = tforms{edges(k).j}(1:2, 1:2);
        centroidXY = overlapCentroid(layout, positions, edges(k));
        deltaXY = (Li - Lj * M) * centroidXY - Lj * c + (Lj - Li) * [1; 1];
        refineEdges(k).measured = [deltaXY(2), deltaXY(1), edges(k).measured(3)];
    end
    refinedPositions = utils.stitch.solveGlobalLeastSquares(layout, refineEdges, options);
    positions(:, 1:2) = refinedPositions(:, 1:2);
    for t = 1:nTiles
        L = tforms{t}(1:2, 1:2);
        tforms{t}(1:2, 3) = [positions(t, 2); positions(t, 1)] - L * [1; 1];
    end
end

% ---- residual statistics over valid edges --------------------------------------
% Position mismatch of the two tile maps at the source tile's centre: where tile
% i's map puts the centre vs where tile j's map puts the same physical point.
if ~isempty(validEdges)
    resid = zeros(numel(validEdges), 3);
    for k = 1:numel(validEdges)
        e = validEdges(k);
        [M, c] = edgeTransform(e);
        centreA = [(tileSizes(e.i, 2) + 1) / 2; (tileSizes(e.i, 1) + 1) / 2];   % [x; y]
        Ti = tforms{e.i};
        Tj = tforms{e.j};
        globalFromI = Ti(1:2, 1:2) * centreA + Ti(1:2, 3);
        centreInB = M * centreA + c;
        globalFromJ = Tj(1:2, 1:2) * centreInB + Tj(1:2, 3);
        mismatchXY = globalFromJ - globalFromI;
        residZ = (positions(e.j, 3) - positions(e.i, 3)) - e.measured(3);
        resid(k, :) = [mismatchXY(2), mismatchXY(1), residZ];
    end
    stats.residuals = resid;
    stats.rmse = sqrt(mean(resid.^2, 1));
    stats.rmseTotal = sqrt(mean(resid(:).^2));
end
end

% =====================================================================
function centroidXY = overlapCentroid(layout, positions, edge)
% OVERLAPCENTROID - Centre of the two tiles' overlap in tile-i LOCAL xy
% coordinates, from the current solved positions. Falls back to the tile centre
% when the tiles do not overlap at those positions.
sizeI = layout(edge.i).tileSize;
sizeJ = layout(edge.j).tileSize;
delta = positions(edge.j, 1:2) - positions(edge.i, 1:2);   % [dy dx]
rowRange = [max(1, 1 + delta(1)), min(sizeI(1), sizeJ(1) + delta(1))];
colRange = [max(1, 1 + delta(2)), min(sizeI(2), sizeJ(2) + delta(2))];
if rowRange(2) < rowRange(1) || colRange(2) < colRange(1)
    centroidXY = [(sizeI(2) + 1) / 2; (sizeI(1) + 1) / 2];
else
    centroidXY = [mean(colRange); mean(rowRange)];
end
end

% =====================================================================
function [M, c] = edgeTransform(edge)
% EDGETRANSFORM - Tile-local i->j map [M c] of an edge; synthesised from the
% measured translation when no full transform was fitted (phase correlation or
% translation-model edges): p_j - p_i = measured with M = I gives c = -measured_xy.
if isfield(edge, 'tform') && ~isempty(edge.tform)
    T = double(edge.tform);
    M = T(1:2, 1:2);
    c = T(1:2, 3);
else
    M = eye(2);
    c = [-edge.measured(2); -edge.measured(1)];
end
end
