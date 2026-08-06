function [positions, stats] = solveGlobalLeastSquares(layout, edges, options)
% SOLVEGLOBALLEASTSQUARES - Global tile origins from pairwise edges (weighted LS).
%
% Syntax:
%   .. code-block:: matlab
%
%      [positions, stats] = utils.stitch.solveGlobalLeastSquares(layout, edges)
%      [positions, stats] = utils.stitch.solveGlobalLeastSquares(layout, edges, options)
%
% Solves for every tile's global origin by minimising, per axis (y, x, z solved
% independently), the quality-weighted squared residual of the pairwise
% constraints ``p_j - p_i = measured``. This is the MIST/BigStitcher global
% optimisation: one sparse weighted least-squares system whose gauge is fixed by
% anchoring tile 1 to its nominal origin.
%
% Two-round strategy:
%   1. Round 1 uses only ``valid`` edges (quality above threshold).
%   2. Any tile left disconnected from the anchor, and any pruned (invalid) edge,
%      re-enters as a weak "spring" row ``p_j - p_i = nominal`` with weight
%      ``options.springWeight`` so the graph is fully connected.
%   3. Every tile additionally gets a very weak spring to its own nominal origin
%      (weight ``options.nominalSpringWeight``) so the normal equations are always
%      full rank even for isolated tiles.
%
% Input Arguments:
%   - **layout** - [struct array] tile layout with ``.nomOrigin`` (``[y x z]``).
%   - **edges** - [struct array] from :func:`utils.stitch.measureAllPairs`; uses
%     ``.i .j .measured .nominal .quality .valid``.
%   - **options** *(optional)* - struct with fields:
%
%     - ``.springWeight`` - [double] weight of re-added pruned/bridge springs (default: ``0.10``)
%     - ``.nominalSpringWeight`` - [double] weight of the per-tile self-spring (default: ``0.001``).
%       Keep tiny: it exists only for rank; any real weight biases tiles whose
%       true positions deviate from nominal (e.g. border-clamped acquisitions).
%     - ``.userEdgeWeight`` - [double] weight of USER-fixed edges
%       (``edge.source = 'user'``, from the seam inspector; default: ``5.0``).
%       Well above any quality (≤ 1) so a user fix dominates conflicting
%       automatic edges without being an absolute pin (two contradictory user
%       fixes average instead of fighting). User edges are never pruned by the
%       quality threshold and never demoted to springs.
%
% Output Arguments:
%   - **positions** - [N x 3 double] solved ``[y x z]`` origins (fractional allowed);
%     row 1 (the anchor) equals ``layout(1).nomOrigin``.
%   - **stats** - [struct] with fields:
%
%     - ``.residuals`` - [M x 3] per valid-edge residual ``(p_j - p_i) - measured``
%     - ``.rmse`` - [1x3] root-mean-square residual per axis over valid edges
%     - ``.rmseTotal`` - [double] RMSE over all axes/valid edges
%     - ``.nPruned`` - [double] number of invalid edges
%     - ``.nComponents`` - [double] connected components among valid edges
%     - ``.anchorComponent`` - [double] component id containing the anchor tile
%     - ``.disconnectedTiles`` - [vector] tiles not connected to the anchor by valid edges
%
% **Example** - solve a jittered grid:
%
%   .. code-block:: matlab
%
%      [positions, stats] = utils.stitch.solveGlobalLeastSquares(layout, edges);
%      fprintf('RMSE = %.3f px\n', stats.rmseTotal);

if nargin < 3; options = struct(); end
if ~isfield(options, 'springWeight');        options.springWeight = 0.10; end
if ~isfield(options, 'nominalSpringWeight');  options.nominalSpringWeight = 0.001; end
if ~isfield(options, 'userEdgeWeight');       options.userEdgeWeight = 5.0; end

nTiles = numel(layout);
nomOrigins = reshape([layout.nomOrigin], 3, nTiles)';   % N x 3 [y x z]

positions = nomOrigins;
stats = struct('residuals', zeros(0, 3), 'rmse', [0 0 0], 'rmseTotal', 0, ...
    'nPruned', 0, 'nComponents', 1, 'anchorComponent', 1, 'disconnectedTiles', []);

if nTiles == 0; return; end

% User-fixed edges (seam inspector) participate regardless of their quality
% flag and at a fixed dominant weight.
userMask = false(numel(edges), 1);
validMask = false(numel(edges), 1);
for k = 1:numel(edges)
    userMask(k) = isfield(edges, 'source') && strcmp(edges(k).source, 'user');
    validMask(k) = (~isempty(edges) && isfield(edges, 'valid') && edges(k).valid) || userMask(k);
end
validEdges     = edges(validMask);
validUserFlags = userMask(validMask);
prunedEdges    = edges(~validMask);
stats.nPruned = numel(prunedEdges);

% ---- connectivity among valid edges (which tiles reach the anchor?) ----------
adjacency = sparse(nTiles, nTiles);
for k = 1:numel(validEdges)
    ii = validEdges(k).i; jj = validEdges(k).j;
    adjacency(ii, jj) = 1; %#ok<SPRIX>
    adjacency(jj, ii) = 1; %#ok<SPRIX>
end
componentId = connectedComponents(adjacency, nTiles);
anchorTile = 1;
anchorComponent = componentId(anchorTile);
disconnectedTiles = find(componentId ~= anchorComponent);
stats.nComponents = max(componentId);
stats.anchorComponent = anchorComponent;
stats.disconnectedTiles = disconnectedTiles(:)';

% ---- assemble constraint rows -------------------------------------------------
% Each row constrains p_j - p_i (or p_i - anchor) toward a target with a weight.
% Columns: one per tile. We build a design matrix A (M x N), targets b (M x 3),
% and weights w (M x 1), then solve the weighted normal equations per axis.
rowsI = [];   % tile index with +1 (the "j" of the difference)
rowsMinus = [];   % tile index with -1 (the "i")
targets = zeros(0, 3);
weights = zeros(0, 1);

% Valid edges: p_j - p_i = measured, weight = quality (user fixes: fixed
% dominant weight).
for k = 1:numel(validEdges)
    e = validEdges(k);
    rowsI(end+1, 1)     = e.j; %#ok<AGROW>
    rowsMinus(end+1, 1) = e.i; %#ok<AGROW>
    targets(end+1, :)   = e.measured; %#ok<AGROW>
    if validUserFlags(k)
        weights(end+1, 1) = options.userEdgeWeight; %#ok<AGROW>
    else
        weights(end+1, 1) = max(e.quality, eps); %#ok<AGROW>
    end
end

% Pruned edges re-enter as weak springs toward their NOMINAL offset - but only
% when they touch a tile that the valid edges leave disconnected from the anchor.
% Between well-connected tiles such springs add no information and only bias the
% solution toward the (wrong) nominal offsets.
for k = 1:numel(prunedEdges)
    e = prunedEdges(k);
    if componentId(e.i) == anchorComponent && componentId(e.j) == anchorComponent
        continue;
    end
    rowsI(end+1, 1)     = e.j; %#ok<AGROW>
    rowsMinus(end+1, 1) = e.i; %#ok<AGROW>
    targets(end+1, :)   = e.nominal; %#ok<AGROW>
    weights(end+1, 1)   = options.springWeight; %#ok<AGROW>
end

% Bridge springs: for any tile disconnected from the anchor, add a spring to its
% nominal offset relative to the anchor so it is pulled into the global frame.
for t = disconnectedTiles(:)'
    if t == anchorTile; continue; end
    rowsI(end+1, 1)     = t; %#ok<AGROW>
    rowsMinus(end+1, 1) = anchorTile; %#ok<AGROW>
    targets(end+1, :)   = nomOrigins(t, :) - nomOrigins(anchorTile, :); %#ok<AGROW>
    weights(end+1, 1)   = options.springWeight; %#ok<AGROW>
end

% Per-tile self springs to their own nominal origin (absolute constraint against
% the anchor's frame) - guarantees full rank. Implemented as p_t - anchor = nom_t - nom_anchor.
for t = 1:nTiles
    rowsI(end+1, 1)     = t; %#ok<AGROW>
    rowsMinus(end+1, 1) = anchorTile; %#ok<AGROW>
    targets(end+1, :)   = nomOrigins(t, :) - nomOrigins(anchorTile, :); %#ok<AGROW>
    weights(end+1, 1)   = options.nominalSpringWeight; %#ok<AGROW>
end

nRows = numel(weights);

% Build sparse design matrix A (nRows x nTiles) with +1 at rowsI, -1 at rowsMinus.
% The self-difference of the anchor cancels; that is intentional - the anchor
% column is then removed and folded into the target (gauge fix p_anchor = nom_anchor).
rowIndex = (1:nRows)';
iEntries = [rowIndex; rowIndex];
jEntries = [rowsI; rowsMinus];
vEntries = [ones(nRows, 1); -ones(nRows, 1)];
A = sparse(iEntries, jEntries, vEntries, nRows, nTiles);

% Gauge fix: pin the anchor to its nominal origin by moving its column to the RHS.
anchorPin = nomOrigins(anchorTile, :);   % 1x3
freeTiles = setdiff(1:nTiles, anchorTile);
Afree = A(:, freeTiles);
anchorColumn = full(A(:, anchorTile));   % nRows x 1

% Weighted least squares via normal equations per axis.
Wsqrt = sqrt(weights);
Aw = Afree .* Wsqrt;                       % scale rows

positions = nomOrigins;   % initialise; anchor keeps its nominal
for axis = 1:3
    bAxis = targets(:, axis) - anchorColumn * anchorPin(axis);
    bw = bAxis .* Wsqrt;
    % Solve (Aw' * Aw) x = Aw' * bw with sparse mldivide on the normal equations.
    normalMatrix = Aw' * Aw;
    normalRhs    = Aw' * bw;
    solution = normalMatrix \ normalRhs;
    positions(freeTiles, axis) = solution;
    positions(anchorTile, axis) = anchorPin(axis);
end

% ---- residual statistics over valid edges ------------------------------------
if ~isempty(validEdges)
    resid = zeros(numel(validEdges), 3);
    for k = 1:numel(validEdges)
        e = validEdges(k);
        resid(k, :) = (positions(e.j, :) - positions(e.i, :)) - e.measured;
    end
    stats.residuals = resid;
    stats.rmse = sqrt(mean(resid.^2, 1));
    stats.rmseTotal = sqrt(mean(resid(:).^2));
else
    stats.residuals = zeros(0, 3);
    stats.rmse = [0 0 0];
    stats.rmseTotal = 0;
end
end

% =====================================================================
function componentId = connectedComponents(adjacency, nTiles)
% CONNECTEDCOMPONENTS - Label connected components of a symmetric adjacency matrix.
componentId = zeros(nTiles, 1);
nextLabel = 0;
for seed = 1:nTiles
    if componentId(seed) ~= 0; continue; end
    nextLabel = nextLabel + 1;
    stack = seed;
    componentId(seed) = nextLabel;
    while ~isempty(stack)
        node = stack(end);
        stack(end) = [];
        neighbours = find(adjacency(node, :));
        for nb = neighbours
            if componentId(nb) == 0
                componentId(nb) = nextLabel;
                stack(end+1) = nb; %#ok<AGROW>
            end
        end
    end
end
end
