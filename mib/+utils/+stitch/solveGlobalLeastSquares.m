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
%   2. Every group of tiles (component) left disconnected from the anchor gets
%      ONE weak "spring" row, on its first tile, towards that tile's nominal
%      offset from the anchor; any pruned (invalid) edge joining two such groups
%      re-enters as ``p_j - p_i = nominal``. Both weigh ``options.springWeight``
%      and make the graph fully connected without bending a disconnected group
%      against its own measurements.
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
%     - ``.stagePriorSigma`` - [double] **stage prior** for section layouts
%       (pieces carrying ``.stageTile``, see
%       :func:`utils.stitch.splitLayoutIntoSections`): ``[]`` = off (default),
%       ``0`` = estimate, ``> 0`` = the stage repeatability in px. Every piece is
%       pulled towards ONE extra unknown per stage tile - where the stage really
%       was - with weight ``(seamSigma / stagePriorSigma)^2`` on the scale where
%       a quality-1 seam weighs 1. A star of N rows, equivalent to springs
%       between every pair of slices of a tile but linear in the slice count.
%       The estimate reads the valid seams between slices of the SAME stage
%       tile: each measures the difference of two independent stage errors, so
%       ``sigma = 1.4826 * median|offset - nominal| / sqrt(2)`` (floored at
%       ``seamSigma``; no such seam = no prior). Accurate when the stage error
%       does not accumulate (backlash); sample drift between sections is
%       resisted by the prior in proportion to its weight - which is why it is
%       a choice, see ``plan_serial_sections.md``.
%     - ``.seamSigma`` - [double] expected error (px) of a quality-1 seam; only
%       its ratio to ``stagePriorSigma`` matters (default: ``0.25``). Larger =
%       trust the stage more than the section-to-section registration.
%     - ``.robustLoss`` - [logical] iteratively reweighted solve with a Huber
%       loss on the automatic seams (default: ``false``): seams that disagree
%       with the rest are down-weighted instead of dragging their neighbours.
%       Huber, not a redescending loss (Cauchy / Tukey): those reject an
%       outlier in a well-looped grid exactly, but on serial sections - long
%       chains with few loops - they also reject good seams and were worse on
%       both benchmarks (test 19: max 4.0-5.3 px vs Huber 3.4 px).
%     - ``.robustIterations`` - [double] most reweighting rounds; stops earlier
%       once no position moves by 0.01 px (default: ``50``)
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
%     - ``.stagePriorSigma`` - [double] stage repeatability the prior used (px), NaN = none
%     - ``.robustWeights`` - [M x 1] final Huber factors of the valid edges
%       (``robustLoss`` only)
%     - ``.sectionDrift`` - [struct] section layouts only: drift vs backlash
%       check from the measured section-to-section seams, independent of the
%       solve - ``.stageSigma`` (px), ``.wholeSectionShift`` (px, how far the
%       sections as a whole move from section 1), ``.backlashBound`` (px, what
%       stage jitter alone would stay within), ``.numBoundaries``,
%       ``.withinStageJitter`` (logical). Above the bound the sections move
%       for real: sample drift OR oblique structures - indistinguishable here
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
if ~isfield(options, 'stagePriorSigma');      options.stagePriorSigma = []; end
if ~isfield(options, 'seamSigma');            options.seamSigma = 0.25; end
if ~isfield(options, 'robustLoss');           options.robustLoss = false; end
if ~isfield(options, 'robustIterations');     options.robustIterations = 50; end

if options.robustLoss
    [positions, stats] = solveRobust(layout, edges, options);
    return;
end

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
% when they join two groups the valid edges leave apart. Inside one connected
% group such a spring adds no information and only biases the solution toward
% the (wrong) nominal offsets.
for k = 1:numel(prunedEdges)
    e = prunedEdges(k);
    if componentId(e.i) == componentId(e.j)
        continue;   % inside one connected group - adds no connectivity, only bias
    end
    rowsI(end+1, 1)     = e.j; %#ok<AGROW>
    rowsMinus(end+1, 1) = e.i; %#ok<AGROW>
    targets(end+1, :)   = e.nominal; %#ok<AGROW>
    weights(end+1, 1)   = options.springWeight; %#ok<AGROW>
end

% Bridge springs: ONE per component the valid edges leave disconnected from the
% anchor - on its first tile, towards that tile's nominal offset from the
% anchor - so the component is pulled into the global frame as a whole. A
% spring on EVERY tile of a multi-tile component would pull each tile towards
% its own nominal and bend the component against its own measurements
% (unrelated serial sections: every section is such a component).
componentFirstTiles = arrayfun(@(component) find(componentId == component, 1), ...
    setdiff(unique(componentId(disconnectedTiles)), anchorComponent));
for t = componentFirstTiles(:)'
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

% Stage prior (section layouts): one extra unknown per stage tile - the stage
% position - and every piece of that tile pulled towards it. A star of N rows,
% not the N^2/2 pairwise springs it is equivalent to. Seam rows weigh
% quality, i.e. quality / seamSigma^2 in 1/px^2 up to a common factor, so the
% prior row weighs (seamSigma / stageSigma)^2 on the same scale.
numLatent = 0;
stats.stagePriorSigma = NaN;
if ~isempty(options.stagePriorSigma) && isfield(layout, 'stageTile') && ...
        ~any(arrayfun(@(piece) isempty(piece.stageTile), layout))
    stageSigma = options.stagePriorSigma;
    if stageSigma == 0
        stageSigma = estimateStageSigma(layout, validEdges, options.seamSigma);
    end
    if ~isnan(stageSigma)
        stageTiles = [layout.stageTile];
        [stageIds, ~, latentOf] = unique(stageTiles);
        [~, firstPiece] = ismember(stageIds, stageTiles);   % the latent sits at its first piece's nominal
        numLatent = numel(stageIds);
        priorWeight = (options.seamSigma / stageSigma)^2;
        for t = 1:nTiles
            rowsI(end+1, 1)     = t; %#ok<AGROW>
            rowsMinus(end+1, 1) = nTiles + latentOf(t); %#ok<AGROW>
            targets(end+1, :)   = nomOrigins(t, :) - nomOrigins(firstPiece(latentOf(t)), :); %#ok<AGROW>
            weights(end+1, 1)   = priorWeight; %#ok<AGROW>
        end
        stats.stagePriorSigma = stageSigma;
    end
end

nRows = numel(weights);
numColumns = nTiles + numLatent;

% Build sparse design matrix A (nRows x numColumns) with +1 at rowsI, -1 at
% rowsMinus; columns are the tiles, then the stage positions (if any). The
% self-difference of the anchor cancels; that is intentional - the anchor
% column is then removed and folded into the target (gauge fix p_anchor = nom_anchor).
rowIndex = (1:nRows)';
iEntries = [rowIndex; rowIndex];
jEntries = [rowsI; rowsMinus];
vEntries = [ones(nRows, 1); -ones(nRows, 1)];
A = sparse(iEntries, jEntries, vEntries, nRows, numColumns);

% Gauge fix: pin the anchor to its nominal origin by moving its column to the RHS.
anchorPin = nomOrigins(anchorTile, :);   % 1x3
freeTiles = setdiff(1:nTiles, anchorTile);
Afree = A(:, [freeTiles, nTiles + (1:numLatent)]);
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
    positions(freeTiles, axis) = solution(1:numel(freeTiles));   % the rest: stage positions
    positions(anchorTile, axis) = anchorPin(axis);
end

% ---- drift vs backlash check (section layouts) -------------------------------
if isfield(layout, 'stageTile') && ~any(arrayfun(@(piece) isempty(piece.stageTile), layout))
    stats.sectionDrift = sectionDriftCheck(layout, validEdges);
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
function [positions, stats] = solveRobust(layout, edges, options)
% SOLVEROBUST - Iteratively reweighted solve with a Huber loss on the seams.
% Each round scales every valid automatic seam's weight by
% min(1, 1.5 * scale / |residual|), scale = 1.4826 * median |residual| of the
% previous round (floor 0.02 px): seams that agree keep their full weight, the
% few that disagree with the rest are pulled down instead of dragging their
% neighbours along. User-fixed seams keep their fixed weight. The edges are
% returned untouched; only stats.robustWeights records the final factors.
options.robustLoss = false;
validMask = arrayfun(@(edge) (isfield(edge, 'valid') && edge.valid) || ...
    (isfield(edge, 'source') && strcmp(edge.source, 'user')), edges);
validIdx = find(validMask);
baseQuality = [edges.quality];
weightedEdges = edges;
robustWeights = ones(numel(validIdx), 1);
previousPositions = [];
for iteration = 1:options.robustIterations
    [positions, stats] = utils.stitch.solveGlobalLeastSquares(layout, weightedEdges, options);
    if isempty(validIdx); break; end
    % Huber IRLS converges slowly (tens of rounds for a 4 px outlier in a 3x3
    % grid), so stop on convergence rather than after a fixed count.
    if ~isempty(previousPositions) && max(abs(positions(:) - previousPositions(:))) < 0.01
        break;
    end
    previousPositions = positions;
    residualLength = sqrt(sum(stats.residuals(:, 1:2).^2, 2));
    scale = max(1.4826 * median(residualLength), 0.02);
    robustWeights = min(1, 1.5 * scale ./ max(residualLength, eps));
    for k = 1:numel(validIdx)
        weightedEdges(validIdx(k)).quality = baseQuality(validIdx(k)) * robustWeights(k);
    end
end
stats.robustWeights = robustWeights;
end

% =====================================================================
function check = sectionDriftCheck(layout, validEdges)
% SECTIONDRIFTCHECK - How far whole sections move along the stack, compared
% with what stage jitter alone could produce. Reads only the measured
% section-to-section seams (same stage tile), never the solved positions, so
% it describes the DATA and is the same whatever SectionAlignment chose.
%
% At each section boundary the tiles' measured steps are averaged - the
% movement common to the whole section - and summed through the stack; the
% largest distance that sum reaches from section 1 is wholeSectionShift.
% Under backlash alone the common position of a section is the mean of K
% independent stage errors, so it stays within about 3 * sigma * 2/sqrt(K)
% (backlashBound; 2/sqrt(K) = sqrt(2/K) for the difference to section 1,
% times sqrt(2) for the two axes). Above it, whole sections really move:
% sample drift, OR structures running obliquely through Z, which bias every
% section-to-section match the same way - the pixels cannot tell those two
% apart, so the check never claims which (see plan_serial_sections.md).
check = struct('stageSigma', NaN, 'wholeSectionShift', NaN, 'backlashBound', NaN, ...
    'numBoundaries', 0, 'withinStageJitter', true);
if isempty(validEdges); return; end
stageTiles = [layout.stageTile];
sameStage = stageTiles([validEdges.i]) == stageTiles([validEdges.j]);
if ~any(sameStage); return; end
sectionEdges = validEdges(sameStage);
offsets = reshape([sectionEdges.measured], 3, [])' - reshape([sectionEdges.nominal], 3, [])';
boundary = [layout([sectionEdges.i]).zLayer]';
[~, ~, boundaryIdx] = unique(boundary);
commonStep = [accumarray(boundaryIdx, offsets(:, 1), [], @mean), ...
              accumarray(boundaryIdx, offsets(:, 2), [], @mean)];
cumulative = cumsum(commonStep, 1);
check.stageSigma = estimateStageSigma(layout, validEdges, 0);
check.wholeSectionShift = max([0; hypot(cumulative(:, 1), cumulative(:, 2))]);
check.backlashBound = 3 * check.stageSigma * 2 / sqrt(numel(unique(stageTiles)));
check.numBoundaries = size(commonStep, 1);
check.withinStageJitter = check.wholeSectionShift <= check.backlashBound;
end

% =====================================================================
function stageSigma = estimateStageSigma(layout, validEdges, seamSigma)
% ESTIMATESTAGESIGMA - Stage repeatability (px) from the section-to-section
% seams: a seam between two slices of the SAME stage tile measures the
% difference of two independent stage errors, variance 2*sigma^2. Robust
% (median-based) so a few wrong seams do not inflate it; never below
% seamSigma, below which the seams cannot resolve the stage anyway. NaN when
% no such seam exists (no prior).
stageSigma = NaN;
if isempty(validEdges); return; end
stageTiles = [layout.stageTile];
sameStage = stageTiles([validEdges.i]) == stageTiles([validEdges.j]);
if ~any(sameStage); return; end
offsets = reshape([validEdges(sameStage).measured], 3, [])' - ...
          reshape([validEdges(sameStage).nominal], 3, [])';
offsets = offsets(:, 1:2);
stageSigma = max(1.4826 * median(abs(offsets(:))) / sqrt(2), seamSigma);
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
