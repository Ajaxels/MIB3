function correction = estimateIntensityCorrection(layout, options)
% ESTIMATETILECORRECTION - Estimate a per-mosaic intensity correction for the tiles.
%
% Syntax:
%   .. code-block:: matlab
%
%      correction = utils.stitch.estimateIntensityCorrection(layout)
%      correction = utils.stitch.estimateIntensityCorrection(layout, options)
%
% Measures how the tiles' brightness differs from one another and returns the
% correction that removes it, for :func:`utils.stitch.makeTileReader` to apply.
% Nothing is written and no pixels are modified here - the result is a small
% description that every reader can be built with, so measurement, seam scoring
% and fusion all see the same corrected pixels.
%
% **Why the default is a shading FIELD and not per-tile means.** On the data this
% was written against (TEM, where the beam profile makes one side of every tile
% brighter than the other), the visible seam steps are NOT a tile-to-tile mean
% difference. Each tile carries an in-plane gradient, so at a vertical seam one
% tile's dark right edge meets its neighbour's bright left edge and they disagree
% by 4 - 5 % even when the two tiles' overall means agree to 0.16 %. Measured on a
% 3x3 reference montage, as rms mismatch across the 12 seams:
%
%   ==================================  =========
%   correction                           mismatch
%   ==================================  =========
%   ``None``                              3.50 %
%   ``Match tile means``                  3.13 %
%   ``Flat-field (shared)``               1.04 %
%   flat-field AND mean matching          1.36 %
%   ==================================  =========
%
% (Read through :func:`utils.stitch.makeTileReader` on the same MRC the numbers
% come out ~2.1x larger, because the header rescale removes a big offset and that
% amplifies ratios: 7.50 / 6.73 / 2.31 %. ``Flat-field (overlap-solved)`` scores
% **1.01 %** on that scale, i.e. better than twice the shared field.)
%
% Two things follow, and both are deliberate: matching tile means barely helps
% (it cannot touch a gradient that lives INSIDE each tile), and stacking mean
% matching on top of a flat field makes it WORSE - tiles genuinely contain
% different amounts of material, so forcing their means together fights real
% signal. The methods are therefore alternatives, not layers.
%
% ``Match tile means`` is kept because it is the right correction for a DIFFERENT
% fault: a detector or stain whose response drifts over a long acquisition, where
% the tiles really do differ by a flat factor.
%
% .. note::
%    Estimating reads every tile once. The caller is expected to cache the result
%    (the Stitching controller keeps it in ``obj.intensityCorrection`` and drops it when
%    the layout or the method changes) rather than re-deriving it per stage.
%
% .. warning::
%    **``Flat-field (shared)`` assumes the tiles' CONTENT averages out.** It takes
%    the mean of every tile normalised by its own mean, so whatever survives that
%    average is attributed to illumination. That holds for a real mosaic - many
%    tiles, modest overlap, different specimen under each - but it fails when the
%    tiles are few and heavily overlapping, because then they all show nearly the
%    same thing and the specimen's own low-frequency structure is absorbed into
%    the field. A 3x3 montage at 10 % overlap estimates cleanly; a 2x2 at 33 %
%    can come out worse than no correction at all.
%
%    There is no way to tell the two apart from the field alone. Use
%    ``Flat-field (overlap-solved)`` instead: it fits the field to the
%    DISAGREEMENT between tiles where they overlap, and because both tiles image
%    the same specimen there, the specimen cancels exactly. It has no equivalent
%    failure mode and is the better answer whenever seams still show.
%
% .. warning::
%    **Seams do not observe the tile interior, and a too-flexible fit bows there.**
%    Overlaps sample the field only in narrow border strips; the polynomial
%    carries it into the middle with nothing checking it. At degree 4 on real data
%    the fit dipped to **0.87 at the tile centre against 1.12 at the edges** - a
%    37 % span where the whole-tile evidence says 14 %. Dividing that out
%    brightened every tile centre and drew a **dark grid along the seams**, while
%    the seam residual read 1.01 %, better than any other method. The seam metric
%    is blind to this by construction: it measures only the quantity the fit
%    minimises.
%
%    The degree is therefore CHOSEN, by two tests that both have to pass
%    (:func:`chooseFieldDegree`):
%
%    - **cross-validation over held-out seams**, which catches a degree fitting
%      noise in the border strips, with a parsimony margin so extra freedom has to
%      earn its place;
%    - **the interior check**, which compares the fitted field's centre against
%      its borders and vetoes anything that bows.
%
%    Neither suffices alone, and the reference montage shows why: cross-validation
%    PREFERRED degree 4 (held-out error 8 % better than degree 1) - it is the guard
%    that rejects it at 16.9 % interior deviation. No seam-based number can see
%    that failure, because no seam observes the tile interior.
%
%    Do not reach for a ridge on the field coefficients to tame a high degree: it
%    competes with the gain gauge and, past a small weight, flattens the field
%    entirely so the per-tile gains absorb everything - fitting the seams just as
%    well while leaving every tile's internal gradient in place. Degree is the
%    honest lever.
%
% .. note::
%    **The other thing ``Flat-field (overlap-solved)`` cannot see.** On a regular
%    grid a linear field tilt is indistinguishable from a matching ramp of
%    per-tile gains - both fit the seams identically, so the seams cannot choose
%    between them and the fit needs a rule that comes from outside the data.
%
%    Two of the three possible rules are bad. Pinning the FIELD flat leaves every
%    tile's internal gradient in place and makes the mosaic ripple with the tile
%    period. Pinning the GAINS flat (what ``fitSeamModel``'s ridge does on its
%    own) removes that ripple but leaves the tile means untouched, so the mosaic
%    becomes a monotone STAIRCASE - on real montages this made the overall
%    brightness ramp worse than doing nothing at all.
%
%    The rule actually used is the third: fit the shape from the seams, then
%    spend the leftover freedom on making the assembled MOSAIC flat
%    (:func:`levelMosaicPlane`). It is provably free - seam residuals are
%    unchanged to the last digit - because it only moves along the direction the
%    seams cannot see. Pass ``levelMosaic = false`` to keep the mosaic's own
%    brightness trend.
%
% .. note::
%    **``Re-exposure damage`` is a different fault altogether**: the specimen is
%    harmed where an earlier tile's scan already passed, so the LATER tile of every
%    overlap is darker there - a sharp-edged patch in one tile, not a smooth shading
%    shared by all. No field-plus-gain model can represent it: on the reference
%    2-tile SEM pair ``Flat-field (overlap-solved)`` closed the step AT the seam
%    line but left the re-imaged band 10 grey levels dark and a 28-level dark
%    ridge beside it. The model and its measured behaviour are described under
%    :func:`solveReexposureDamage` below.
%
% Input Arguments:
%   - **layout** - [struct array] tile layout (see :func:`utils.stitch.buildLayoutGrid`).
%   - **options** *(optional)* - struct with fields:
%
%     - ``.method`` - [char] ``'None'`` (default), ``'Flat-field (shared)'``,
%       ``'Flat-field (overlap-solved)'``, ``'Match tile means'`` or
%       ``'Re-exposure damage'``.
%     - ``.positions`` - [N x 3] solved tile origins. Optional for the
%       overlap-solved method: nominal origins are used when absent, which is what
%       lets the method run before anything has been solved (samples are
%       block-averaged, so a few pixels of placement error cannot move a low-order
%       field). **Required** for ``'Re-exposure damage'``, whose footprint edges
%       are sharp: without positions it warns and returns no correction.
%     - ``.edges`` - [struct array] seams, for the overlap-solved and re-exposure
%       methods. When given, only ``.valid`` ones are fitted, so a seam excluded
%       in the inspector cannot steer the fit either.
%     - ``.damageReach`` - [double] how far, in pixels, re-exposure damage may
%       extend beyond the earlier tile's recorded edge (default: ``150``). Also
%       the margin kept from any OTHER footprint while sampling. Re-exposure only.
%     - ``.damageFarWidth`` - [double] width, in pixels, of the undamaged strip
%       beyond ``damageReach`` used as the outside baseline (default: ``50``).
%     - ``.edgeGuard`` - [double] pixels next to a tile's own border that are not
%       trusted as reference, because every tile carries its own border roll-off
%       (default: ``25``). Re-exposure only.
%     - ``.minDarkening`` - [double] a seam's later tile must be darker by at least
%       this fraction of the overlap mean before damage is assumed there
%       (default: ``0.02``). Re-exposure only.
%     - ``.previous`` - [struct] a ``'Re-exposure damage'`` correction estimated
%       earlier for the same layout. When no tile has moved by more than
%       ``maxReuseShift`` pixels since, its fitted model is kept and only the
%       footprints are re-placed - no pixel is read.
%     - ``.maxReuseShift`` - [double] default ``20``.
%     - ``.polynomialDegree`` - [double] force the order of the fitted field.
%       ``[]`` (default) lets the data choose it, which is the recommended path.
%       A forced degree is still subject to the interior check.
%     - ``.maxPolynomialDegree`` - [double] highest order the search considers
%       (default: ``4``).
%     - ``.maxInteriorDeviation`` - [double] how far the fitted field may differ
%       between the tile centre and its borders before it is rejected
%       (default: ``0.15``).
%     - ``.degreeSelectionMargin`` - [double] a higher degree must beat the best
%       held-out error by more than this fraction to be preferred over a simpler
%       one (default: ``0.05``).
%     - ``.levelMosaic`` - [logical] after solving, remove the assembled mosaic's
%       overall brightness plane (default: ``true``). This is free at the seams -
%       it moves only along the direction seam data cannot see - but it does
%       flatten a genuine large-scale trend in the specimen along with an
%       instrumental one. Overlap-solved method only.
%     - ``.samplesPerSeam`` - [double] roughly how many blocks to sample per seam
%       (default: ``800``).
%     - ``.robustIterations`` - [double] IRLS passes (default: ``4``).
%     - ``.smoothSigma`` - [double] Gaussian sigma, in pixels, that separates the
%       illumination field from the specimen. Default: 2 % of the shorter tile
%       side (floor 8 px) - large enough that structure averages out, small
%       enough to follow a real beam profile.
%     - ``.showWaitbar`` / ``.parentFigure`` - progress reporting.
%     - ``.cacheSizeBytes`` - [double] tile-reader cache budget (default 256 MB;
%       tiles are read once each, so a big cache buys nothing here).
%
% Output Arguments:
%   - **correction** - struct of PLAIN NUMERICS (no handles), so it survives both
%     ``parfor`` serialisation and a JSON round-trip into the project sidecar:
%
%     - ``.method`` - [char] the method actually applied
%     - ``.field`` - ``[H W]`` single multiplicative illumination field normalised
%       to mean 1, or ``[]`` when the method uses none
%     - ``.gain`` - ``[N x 1]`` per-tile multiplier (all ones when unused)
%     - ``.offset`` - ``[N x 1]`` per-tile additive term, applied BEFORE the gain
%     - ``.tileSize`` - ``[H W]`` the field belongs to, so a reader can refuse a
%       mismatched layout instead of silently mis-scaling
%     - ``.degree`` / ``.degreeReport`` - the chosen field order and what each
%       candidate scored (overlap-solved method)
%     - ``.mosaicPlane`` - ``[dx dy]`` the log-brightness plane removed from the
%       assembled mosaic, ``[0 0]`` when none was
%     - ``.damage`` - ``[]``, or for ``'Re-exposure damage'`` a struct:
%
%       - ``.gain`` / ``.offset`` - the plateau damage, ``observed = gain * truth +
%         offset`` where one earlier exposure fully covers the pixel
%       - ``.distance`` - ``[1 K]`` signed distance, in pixels, from a footprint
%         edge (negative inside the earlier tile's footprint)
%       - ``.profiles`` - ``[4 K]`` damage strength along ``.distance`` for the
%         footprint's left, right, top and bottom side (rows in that order), 1 on
%         the plateau
%       - ``.footprints`` - ``[M 5]`` rows ``[tile rowMin rowMax colMin colMax]``:
%         where an earlier tile's footprint lies in ``tile``'s own pixel frame
%       - ``.pairs`` - ``[P 3]`` rows ``[i j direction]`` for every overlapping
%         pair, ``direction`` = +1 when ``j`` was imaged after ``i``, -1 the other
%         way round, 0 when no damage is assumed between them
%       - ``.order`` - ``[N 1]`` acquisition rank derived from the seams, ``NaN``
%         for a tile no seam could place
%       - ``.positions`` - ``[N 2]`` the tile origins the footprints were placed
%         with; a caller compares it against its own to know when to re-place them
%
% **Example** - correct a montage's shading before fusing it:
%
%   .. code-block:: matlab
%
%      correction = utils.stitch.estimateIntensityCorrection(layout, ...
%          struct('method', 'Flat-field (shared)'));
%      mosaic = utils.stitch.fuseInMemory(layout, canvas, ...
%          struct('correction', correction));
%
% See also utils.stitch.makeTileReader, utils.stitch.scoreSeams

arguments
    layout  struct
    options struct = struct()
end

if ~isfield(options, 'method');         options.method = 'None'; end
if ~isfield(options, 'smoothSigma');    options.smoothSigma = []; end
if ~isfield(options, 'showWaitbar');    options.showWaitbar = false; end
if ~isfield(options, 'parentFigure');   options.parentFigure = []; end
if ~isfield(options, 'cacheSizeBytes'); options.cacheSizeBytes = 256 * 1024^2; end
if ~isfield(options, 'positions');      options.positions = []; end
if ~isfield(options, 'edges');          options.edges = []; end
if ~isfield(options, 'polynomialDegree'); options.polynomialDegree = []; end
if ~isfield(options, 'maxPolynomialDegree'); options.maxPolynomialDegree = 4; end
if ~isfield(options, 'maxInteriorDeviation'); options.maxInteriorDeviation = 0.15; end
if ~isfield(options, 'degreeSelectionMargin'); options.degreeSelectionMargin = 0.05; end
if ~isfield(options, 'samplesPerSeam');   options.samplesPerSeam = 800; end
if ~isfield(options, 'robustIterations'); options.robustIterations = 4; end
if ~isfield(options, 'levelMosaic');      options.levelMosaic = true; end
if ~isfield(options, 'damageReach');      options.damageReach = 150; end
if ~isfield(options, 'damageFarWidth');   options.damageFarWidth = 50; end
if ~isfield(options, 'edgeGuard');        options.edgeGuard = 25; end
if ~isfield(options, 'minDarkening');     options.minDarkening = 0.02; end
if ~isfield(options, 'previous');         options.previous = []; end
if ~isfield(options, 'maxReuseShift');    options.maxReuseShift = 20; end

numTiles = numel(layout);
correction = struct('method', 'None', 'field', [], ...
    'gain', ones(numTiles, 1), 'offset', zeros(numTiles, 1), 'tileSize', [0 0], ...
    'degree', [], 'degreeReport', [], 'mosaicPlane', [0 0], 'damage', []);

if strcmp(options.method, 'None') || numTiles == 0
    return;
end

% A shared field only means anything if the tiles share a size. Rather than
% mis-scaling silently, fall back to no correction and say so.
tileSizes = reshape([layout.tileSize], [], numTiles).';
if ~isscalar(unique(tileSizes(:, 1))) || ~isscalar(unique(tileSizes(:, 2)))
    warning('utils:stitch:estimateIntensityCorrection:mixedTileSizes', ...
        ['Tiles are not all the same size, so no shared intensity correction ' ...
         'can be estimated. Continuing without one.']);
    return;
end
tileHeight = tileSizes(1, 1);
tileWidth  = tileSizes(1, 2);
correction.tileSize = [tileHeight, tileWidth];

if isempty(options.smoothSigma)
    % 2% of the shorter side: wide enough that specimen structure averages out,
    % narrow enough to follow a real beam profile.
    options.smoothSigma = max(8, 0.02 * min(tileHeight, tileWidth));
end

readerFcn = utils.stitch.makeTileReader(layout, ...
    struct('cacheSizeBytes', options.cacheSizeBytes));

waitbarHandle = [];
if options.showWaitbar && ~isempty(options.parentFigure)
    waitbarHandle = uiprogressdlg(options.parentFigure, 'Value', 0, ...
        'Message', 'Reading tiles...', 'Title', 'Estimating intensity correction');
    cleanupWaitbar = onCleanup(@() delete(waitbarHandle));
end

% The overlap-driven fit never looks at a whole tile - it reads only the shared
% strips - so it branches out before the full pass below.
if strcmp(options.method, 'Flat-field (overlap-solved)')
    correction = solveFieldFromOverlaps(layout, options, readerFcn, ...
        tileHeight, tileWidth, correction, waitbarHandle);
    return;
end
if strcmp(options.method, 'Re-exposure damage')
    correction = solveReexposureDamage(layout, options, readerFcn, ...
        tileHeight, tileWidth, correction, waitbarHandle);
    return;
end

% ---- One pass over the tiles: per-tile mean, and the running field sum ----
tileMeans = zeros(numTiles, 1);
needsField = strcmp(options.method, 'Flat-field (shared)');
fieldSum = [];
if needsField; fieldSum = zeros(tileHeight, tileWidth, 'single'); end

for tileIdx = 1:numTiles
    % [H W D C] -> one plane: average over depth and colour, so a multi-channel
    % or Z-stack tile contributes its overall illumination rather than channel 1.
    tilePlane = single(readerFcn(tileIdx));
    tilePlane = mean(reshape(tilePlane, tileHeight, tileWidth, []), 3);

    tileMeans(tileIdx) = mean(tilePlane, 'all');
    if needsField && tileMeans(tileIdx) > 0
        % Normalise each tile by its OWN mean before accumulating, so a bright
        % tile does not dominate the shape of the shared field.
        fieldSum = fieldSum + tilePlane / tileMeans(tileIdx);
    end

    if ~isempty(waitbarHandle)
        waitbarHandle.Value = tileIdx / numTiles;
        waitbarHandle.Message = sprintf('Reading tile %d of %d...', tileIdx, numTiles);
    end
end

switch options.method
    case 'Flat-field (shared)'
        if ~isempty(waitbarHandle); waitbarHandle.Message = 'Fitting the illumination field...'; end
        illuminationField = fieldSum / numTiles;
        % Smooth away the specimen, keeping only what varies slowly across the
        % frame. 'replicate' padding matters: zero padding would darken the tile
        % BORDERS, which is exactly where the seams are.
        illuminationField = imgaussfilt(illuminationField, options.smoothSigma, ...
            'Padding', 'replicate');
        fieldMean = mean(illuminationField, 'all');
        if ~isfinite(fieldMean) || fieldMean <= 0
            warning('utils:stitch:estimateIntensityCorrection:degenerateField', ...
                'The illumination field came out empty or non-positive; continuing without a correction.');
            return;
        end
        illuminationField = illuminationField / fieldMean;
        % Never divide by ~0: a floor keeps a dark corner from exploding.
        correction.field  = max(illuminationField, 0.05);
        correction.method = options.method;

    case 'Match tile means'
        usable = tileMeans > 0;
        if ~any(usable)
            warning('utils:stitch:estimateIntensityCorrection:emptyTiles', ...
                'Every tile read as empty; continuing without a correction.');
            return;
        end
        targetMean = mean(tileMeans(usable));
        correction.gain(usable) = targetMean ./ tileMeans(usable);
        correction.method = options.method;

    otherwise
        error('utils:stitch:estimateIntensityCorrection:unknownMethod', ...
            'Unknown intensity-correction method: %s', options.method);
end

end

% =========================================================================
function correction = solveFieldFromOverlaps(layout, options, readerFcn, ...
    tileHeight, tileWidth, correction, waitbarHandle)
% SOLVEFIELDFROMOVERLAPS - Fit the illumination field to seam DISAGREEMENT.
%
% Where two tiles overlap they image the SAME specimen, so at a shared point
%
%   log A = log S + logF(u_i) + logG_i
%   log B = log S + logF(u_j) + logG_j
%
% and subtracting cancels the specimen EXACTLY:
%
%   log A - log B = [logF(u_i) - logF(u_j)] + [logG_i - logG_j]
%
% ``u_i`` / ``u_j`` are the same physical point's position WITHIN each tile, which
% differ by the tile step - which is why the field is observable at all. This is
% the whole advantage over the shared-field method: nothing here depends on the
% tiles' content being uncorrelated, so a specimen with its own broad brightness
% trend cannot leak into the field.
%
% ``logF`` is fitted on a low-order 2-D polynomial with NO constant term (a
% constant cancels in the difference and is therefore unobservable), plus one
% ``logG`` per tile pinned by a zero-sum gauge row.

positions = options.positions;
if isempty(positions)
    % The fit needs to know which pixels correspond, not where they belong to the
    % nearest pixel: samples are block-averaged, so nominal origins are ample
    % (a few px of placement error is nothing against a 32 px block and a
    % degree-4 polynomial). This keeps the method usable BEFORE the first solve.
    positions = reshape([layout.nomOrigin], 3, []).';
end
positions = round(positions(:, 1:2));
numTiles  = numel(layout);

pairList = overlappingPairs(layout, positions, options.edges, tileHeight, tileWidth);
if isempty(pairList)
    warning('utils:stitch:estimateIntensityCorrection:noOverlaps', ...
        ['No overlapping tile pairs were found, so the field cannot be fitted from ' ...
         'seams. Continuing without a correction.']);
    return;
end

% Samples are gathered ONCE and reused for every candidate degree: reading the
% overlap crops is the whole cost here, while a fit on the gathered blocks is
% milliseconds. That is what makes choosing the degree by cross-validation
% essentially free.
sampleCoordsI = {};
sampleCoordsJ = {};
sampleTileI   = {};
sampleTileJ   = {};
sampleLogRatio = {};
sampleSeamId   = {};

for pairIdx = 1:size(pairList, 1)
    tileI = pairList(pairIdx, 1);
    tileJ = pairList(pairIdx, 2);

    % Shared rectangle in the mosaic frame, then the same rectangle expressed in
    % each tile's own pixels.
    rowStart = max(positions(tileI, 1), positions(tileJ, 1));
    rowEnd   = min(positions(tileI, 1), positions(tileJ, 1)) + tileHeight - 1;
    colStart = max(positions(tileI, 2), positions(tileJ, 2));
    colEnd   = min(positions(tileI, 2), positions(tileJ, 2)) + tileWidth - 1;
    if rowEnd <= rowStart || colEnd <= colStart; continue; end

    boxI = [rowStart - positions(tileI, 1) + 1, rowEnd - positions(tileI, 1) + 1; ...
            colStart - positions(tileI, 2) + 1, colEnd - positions(tileI, 2) + 1];
    boxJ = [rowStart - positions(tileJ, 1) + 1, rowEnd - positions(tileJ, 1) + 1; ...
            colStart - positions(tileJ, 2) + 1, colEnd - positions(tileJ, 2) + 1];

    cropI = flattenToPlane(readerFcn(tileI, boxI));
    cropJ = flattenToPlane(readerFcn(tileJ, boxJ));

    % Block-average before taking the ratio. Two things need this: photon noise,
    % and the sub-pixel misalignment that survives any solve - a per-pixel ratio
    % of two slightly shifted images is dominated by edges, not by illumination.
    blockSize = chooseBlockSize(size(cropI), options.samplesPerSeam);
    [blockI, blockRows, blockCols] = blockMean(cropI, blockSize);
    blockJ = blockMean(cropJ, blockSize);

    usable = blockI > 0 & blockJ > 0 & isfinite(blockI) & isfinite(blockJ);
    if ~any(usable(:)); continue; end

    % Block centres in each tile's own pixel coordinates.
    centreRowsI = blockRows + boxI(1, 1) - 1;
    centreColsI = blockCols + boxI(2, 1) - 1;
    centreRowsJ = blockRows + boxJ(1, 1) - 1;
    centreColsJ = blockCols + boxJ(2, 1) - 1;
    [gridColsI, gridRowsI] = meshgrid(centreColsI, centreRowsI);
    [gridColsJ, gridRowsJ] = meshgrid(centreColsJ, centreRowsJ);

    % Store the raw geometry, not a design matrix: the basis depends on the
    % degree, which is not chosen yet.
    sampleCoordsI{end+1} = normalizeCoords(gridRowsI(usable), gridColsI(usable), tileHeight, tileWidth); %#ok<AGROW>
    sampleCoordsJ{end+1} = normalizeCoords(gridRowsJ(usable), gridColsJ(usable), tileHeight, tileWidth); %#ok<AGROW>
    numSamples = size(sampleCoordsI{end}, 1);
    sampleTileI{end+1}    = repmat(tileI, numSamples, 1); %#ok<AGROW>
    sampleTileJ{end+1}    = repmat(tileJ, numSamples, 1); %#ok<AGROW>
    sampleSeamId{end+1}   = repmat(pairIdx, numSamples, 1); %#ok<AGROW>
    sampleLogRatio{end+1} = log(double(blockI(usable))) - log(double(blockJ(usable))); %#ok<AGROW>

    if ~isempty(waitbarHandle)
        waitbarHandle.Value = pairIdx / size(pairList, 1);
        waitbarHandle.Message = sprintf('Reading seam %d of %d...', pairIdx, size(pairList, 1));
    end
end

if isempty(sampleLogRatio)
    warning('utils:stitch:estimateIntensityCorrection:noSeamSamples', ...
        'No usable seam pixels were found; continuing without a correction.');
    return;
end

samples = struct( ...
    'coordsI',  vertcat(sampleCoordsI{:}), ...
    'coordsJ',  vertcat(sampleCoordsJ{:}), ...
    'tileI',    vertcat(sampleTileI{:}), ...
    'tileJ',    vertcat(sampleTileJ{:}), ...
    'seamId',   vertcat(sampleSeamId{:}), ...
    'logRatio', vertcat(sampleLogRatio{:}));

if ~isempty(waitbarHandle); waitbarHandle.Message = 'Choosing the illumination model...'; end

% ---- How flexible a field do these seams actually support? ----
[chosenDegree, degreeReport] = chooseFieldDegree(samples, numTiles, ...
    tileHeight, tileWidth, options);
if isempty(chosenDegree)
    if ~isempty(options.polynomialDegree)
        % A degree was forced, and it bowed. Say which check failed rather than
        % implying a search happened.
        warning('utils:stitch:estimateIntensityCorrection:interiorNotObserved', ...
            ['Degree %d was requested, but its field differs by %.0f%% between the ' ...
             'tile centre and its borders. Seams observe only the borders, so this ' ...
             'is the polynomial bowing where nothing constrains it - it would ' ...
             'brighten every tile centre and leave a dark grid along the seams. ' ...
             'Leave polynomialDegree empty to let the data choose. Continuing ' ...
             'without a correction.'], options.polynomialDegree, ...
            100 * degreeReport(1).interiorDeviation);
    else
        warning('utils:stitch:estimateIntensityCorrection:noUsableDegree', ...
            ['No illumination model passed the interior check (tried degree 1..%d). ' ...
             'The seams disagree in a way no smooth field explains - suspect a real ' ...
             'brightness difference between tiles rather than shading. Continuing ' ...
             'without a correction.'], options.maxPolynomialDegree);
    end
    return;
end
correction.degree       = chosenDegree;
correction.degreeReport = degreeReport;

if ~isempty(waitbarHandle); waitbarHandle.Message = 'Solving for the illumination field...'; end

[fieldCoefficients, logGains] = fitSeamModel(samples, chosenDegree, numTiles, ...
    true(size(samples.logRatio)), options.robustIterations);
illuminationField = evaluateField(fieldCoefficients, chosenDegree, tileHeight, tileWidth);
if isempty(illuminationField)
    warning('utils:stitch:estimateIntensityCorrection:degenerateField', ...
        'The seam-fitted field came out non-positive; continuing without a correction.');
    return;
end

% observed = truth * field * gain, so the correction DIVIDES by both.
tileGains = exp(-logGains);
tileGains = tileGains / exp(mean(log(tileGains)));   % geometric mean 1: overall brightness kept

correction.field  = single(max(illuminationField, 0.05));
correction.gain   = tileGains(:);
correction.method = options.method;

% The seams fix the field's SHAPE but not where the mosaic's overall brightness
% should sit; that is a free direction, and the choice is visible (see
% levelMosaicPlane).
if options.levelMosaic
    if ~isempty(waitbarHandle); waitbarHandle.Message = 'Levelling the mosaic...'; end
    correction = levelMosaicPlane(correction, layout, positions, ...
        tileHeight, tileWidth, readerFcn);
end

end

% =========================================================================
function correction = solveReexposureDamage(layout, options, readerFcn, ...
    tileHeight, tileWidth, correction, waitbarHandle)
% SOLVEREEXPOSUREDAMAGE - Model the darkening left where a tile re-images an earlier one.
%
% Some specimens are harmed by the beam, so the region an earlier tile already
% scanned comes out darker when the next tile images it again. The damage belongs
% to the LATER tile only, follows the earlier tile's scan footprint and has a sharp
% edge - nothing a smooth illumination field can express. Measured on the
% reference pair (SEM, 2 tiles of 4096 x 6144, 587 px overlap):
%
% - **The plateau is affine, not a gain**: ``B = 1.12 * A - 33`` inside the
%   overlap, i.e. -21 grey levels at 100 but only -9 at 200, and uniform across
%   the whole overlap.
% - **It reaches ~50 px BEYOND the recorded edge**, with a ridge ~1.7x the plateau
%   5 - 15 px out: the beam scans past the saved field. That ridge is the darkest
%   line in the uncorrected mosaic.
% - The earlier tile shows no step at the later tile's edge, so the damage really
%   is one-sided.
%
% **Model.** For tile ``j`` with earlier-imaged neighbours ``k``:
%
%   observed = truth + S(u) * dI(truth),   dI(x) = (gain - 1) * x + offset
%   S(u)     = sum_k  px_k(u_x) * py_k(u_y)
%
% ``px``/``py`` are 1-D strength profiles across the footprint's vertical and
% horizontal sides, 1 on the plateau, above 1 on the ridge, 0 far outside; each
% of the four sides gets its own because a scan's line start, line end, first and
% last line need not behave alike. A pixel under two earlier footprints (a grid
% corner) gets S = 2 - accumulation is assumed LINEAR, which was not yet verified
% on a real grid. The reader inverts it:
%
%   truth = (observed - S * offset) / (1 + S * (gain - 1))
%
% **Fit.** Which tile of a seam is the damaged one is read off the pixels: the
% later one is the DARKER one in the overlap (``minDarkening``). Diagonal pairs,
% whose shared corner is too small and too confounded to judge, take the order
% implied by the decided seams (:func:`acquisitionRank`). The plateau ``gain`` /
% ``offset`` come from block means where exactly one earlier footprint covers the
% damaged tile and none covers the reference (total least squares - both sides are
% measurements). The profiles INSIDE a footprint come from the same comparison per
% distance; OUTSIDE it there is no second tile to compare with, so the damaged
% tile's own mean along the edge is compared to a baseline interpolated between
% the reference's content at the edge and the damaged tile's undamaged far
% strip, pooled over every seam of the same side.
%
% .. warning::
%    The outside part is the weak point: it is a within-tile estimate, so the
%    specimen leaks into it. On the reference pair, fitting one half of the edge
%    and checking the other left +-4 grey levels of ripple at the ridge (from
%    -29 uncorrected); the overlap itself transferred to 0.24. The profile is
%    therefore forced non-negative and non-increasing beyond its peak - a
%    negative lobe would BRIGHTEN undamaged pixels, which no physical damage does.
%
% .. note::
%    Each tile's own border roll-off (every tile, damaged or not, darkens over its
%    last ~40 px on the reference data) would otherwise be read as a WEAKER damage
%    right at the edge: the reference is dark there too. ``edgeGuard`` px next to
%    any tile border are therefore never used as reference, and the profile is
%    bridged linearly across that gap.

positions = options.positions;
if isempty(positions)
    warning('utils:stitch:estimateIntensityCorrection:needsPositions', ...
        ['Re-exposure damage needs solved tile positions - the footprint edges it ' ...
         'corrects are sharp, and nominal positions can be off by many pixels. ' ...
         'Continuing without a correction.']);
    return;
end
positions = double(positions(:, 1:2));
numTiles  = numel(layout);
zLayers = ones(numTiles, 1);
if isfield(layout, 'zLayer'); zLayers = reshape([layout.zLayer], [], 1); end

correction.tileSize = [tileHeight, tileWidth];
correction.method   = options.method;

% ---- A small move keeps the fitted model: only the footprints are re-placed ----
previous = options.previous;
if ~isempty(previous) && isstruct(previous) && isfield(previous, 'damage') && ...
        isstruct(previous.damage) && isfield(previous.damage, 'positions') && ...
        isequal(size(previous.damage.positions), size(positions)) && ...
        isequal(previous.tileSize, [tileHeight, tileWidth]) && ...
        max(abs(previous.damage.positions - positions), [], 'all') <= options.maxReuseShift
    correction.damage = placeFootprints(previous.damage, positions, zLayers, ...
        tileHeight, tileWidth);
    return;
end

guard = options.edgeGuard;
reach = options.damageReach;
roundedPositions = round(positions);
pairList = damagePairs(roundedPositions, zLayers, tileHeight, tileWidth);
numPairs = size(pairList, 1);
emptyDamage = struct('gain', 1, 'offset', 0, 'distance', zeros(1, 0), ...
    'profiles', zeros(4, 0), 'footprints', zeros(0, 5), 'pairs', zeros(0, 3), ...
    'order', nan(numTiles, 1), 'positions', positions);
correction.damage = emptyDamage;
if numPairs == 0
    warning('utils:stitch:estimateIntensityCorrection:noOverlaps', ...
        'No overlapping tile pairs were found; continuing without a correction.');
    return;
end
judged = judgeablePairs(pairList, roundedPositions, options.edges, tileHeight, tileWidth);

% ---- 1. Which tile of each seam was imaged second: the darker one ----
direction = zeros(numPairs, 1);
judgedIdx = find(judged);
for n = 1:numel(judgedIdx)
    pairIdx = judgedIdx(n);
    [cropI, cropJ] = readOverlapPair(readerFcn, pairList(pairIdx, 1), pairList(pairIdx, 2), ...
        roundedPositions, tileHeight, tileWidth);
    meanI = mean(cropI, 'all');
    meanJ = mean(cropJ, 'all');
    relativeStep = (meanJ - meanI) / max(eps, (meanI + meanJ) / 2);
    if relativeStep <= -options.minDarkening
        direction(pairIdx) = 1;       % j darker -> j imaged after i
    elseif relativeStep >= options.minDarkening
        direction(pairIdx) = -1;
    end
    if ~isempty(waitbarHandle)
        waitbarHandle.Value = 0.3 * n / numel(judgedIdx);
        waitbarHandle.Message = sprintf('Comparing seam %d of %d...', n, numel(judgedIdx));
    end
end
if ~any(direction)
    warning('utils:stitch:estimateIntensityCorrection:noReexposureDamage', ...
        ['No seam shows one tile darker than its neighbour by %.0f%% or more, so ' ...
         'no re-exposure damage was assumed. Continuing without a correction.'], ...
        100 * options.minDarkening);
    return;
end

% Diagonal and excluded pairs cannot be judged from their own pixels; they follow
% the acquisition order the judged seams imply.
order = acquisitionRank(pairList(judged, :), direction(judged), numTiles);
direction = directionFromOrder(pairList, direction, judged, order);

damage = emptyDamage;
damage.pairs = [pairList, direction];
damage.order = order;
footprints = footprintTable(pairList, direction, roundedPositions, tileHeight, tileWidth);

% ---- 2. The plateau: where exactly one earlier footprint covers the damaged tile ----
decidedIdx = find(judged & direction ~= 0);
plateauEarlier = {};
plateauLater   = {};
for n = 1:numel(decidedIdx)
    pairIdx = decidedIdx(n);
    [earlier, later] = orientPair(pairList(pairIdx, :), direction(pairIdx));
    [cropEarlier, cropLater, rowRange, colRange] = readOverlapPair(readerFcn, earlier, later, ...
        roundedPositions, tileHeight, tileWidth);
    % Clean = well inside the overlap, clear of every OTHER footprint of the damaged
    % tile, and on an undamaged part of the reference.
    cleanMask = plateauMask(rowRange, colRange, earlier, later, footprints, ...
        roundedPositions, tileHeight, tileWidth, guard, reach);
    blockSize = chooseBlockSize(size(cropLater), options.samplesPerSeam);
    blockEarlier = blockMean(cropEarlier, blockSize);
    blockLater   = blockMean(cropLater, blockSize);
    blockClean   = blockMean(single(cleanMask), blockSize);
    keep = blockClean >= 1 - 1e-6;
    plateauEarlier{end+1} = double(blockEarlier(keep)); %#ok<AGROW>
    plateauLater{end+1}   = double(blockLater(keep)); %#ok<AGROW>
    if ~isempty(waitbarHandle)
        waitbarHandle.Value = 0.3 + 0.2 * n / numel(decidedIdx);
        waitbarHandle.Message = sprintf('Measuring the damage, seam %d of %d...', n, numel(decidedIdx));
    end
end
plateauEarlier = vertcat(plateauEarlier{:});
plateauLater   = vertcat(plateauLater{:});
if numel(plateauEarlier) < 3
    warning('utils:stitch:estimateIntensityCorrection:noCleanPlateau', ...
        ['The overlaps are too narrow, or too crowded by other tiles, to measure the ' ...
         'damage in. Continuing without a correction.']);
    return;
end
[damage.gain, damage.offset] = fitPlateau(plateauEarlier, plateauLater);
damageAt = @(x) (damage.gain - 1) .* x + damage.offset;
if damageAt(mean(plateauEarlier)) >= 0
    warning('utils:stitch:estimateIntensityCorrection:notDarkened', ...
        ['The re-imaged overlaps are not darker than the first exposure, so this ' ...
         'is not re-exposure damage. Continuing without a correction.']);
    return;
end

% ---- 3. The profiles across each footprint side ----
insideSpan = max(tileHeight, tileWidth);
distanceGrid = (-insideSpan + 0.5):(reach - 0.5);
accumulators = struct('numerIn', zeros(4, numel(distanceGrid)), ...
    'denomIn', zeros(4, numel(distanceGrid)), ...
    'numerOut', zeros(4, numel(distanceGrid)), ...
    'denomOut', zeros(4, numel(distanceGrid)));
for n = 1:numel(decidedIdx)
    pairIdx = decidedIdx(n);
    [earlier, later] = orientPair(pairList(pairIdx, :), direction(pairIdx));
    for side = 1:4
        accumulators = accumulateSide(accumulators, side, earlier, later, footprints, ...
            roundedPositions, readerFcn, damageAt, tileHeight, tileWidth, options, distanceGrid);
    end
    if ~isempty(waitbarHandle)
        waitbarHandle.Value = 0.5 + 0.5 * n / numel(decidedIdx);
        waitbarHandle.Message = sprintf('Measuring the damage edges, seam %d of %d...', n, numel(decidedIdx));
    end
end
damage.distance = distanceGrid;
damage.profiles = finishProfiles(accumulators, distanceGrid, guard);

correction.damage = placeFootprints(damage, positions, zLayers, tileHeight, tileWidth);

end

% =========================================================================
function damage = placeFootprints(damage, positions, zLayers, tileHeight, tileWidth)
% PLACEFOOTPRINTS - Where each earlier tile's footprint lies in every later tile.
%
% Uses the UNROUNDED positions: the reader evaluates the profiles at fractional
% distances, and a half-pixel error at a sharp edge is visible. Pairs that
% overlap now but were not measured (a re-solve can bring two tiles together)
% take their direction from the stored acquisition order.
pairList = damagePairs(positions, zLayers, tileHeight, tileWidth);
direction = zeros(size(pairList, 1), 1);
known = damage.pairs;
for pairIdx = 1:size(pairList, 1)
    match = find(known(:, 1) == pairList(pairIdx, 1) & known(:, 2) == pairList(pairIdx, 2), 1);
    if ~isempty(match)
        direction(pairIdx) = known(match, 3);
    else
        rankI = damage.order(pairList(pairIdx, 1));
        rankJ = damage.order(pairList(pairIdx, 2));
        if isfinite(rankI) && isfinite(rankJ) && rankI ~= rankJ
            direction(pairIdx) = sign(rankJ - rankI);
        end
    end
end
if ~isempty(known)
    % Keep the judgements of pairs that no longer overlap, so a later move back
    % restores them rather than falling to the rank.
    stale = ~ismember(known(:, 1:2), pairList, 'rows');
    damage.pairs = [pairList, direction; known(stale, :)];
end
if isempty(damage.profiles)
    damage.footprints = zeros(0, 5);
else
    damage.footprints = footprintTable(pairList, direction, positions, tileHeight, tileWidth);
end
damage.positions = positions;
end

% =========================================================================
function pairList = damagePairs(positions, zLayers, tileHeight, tileWidth)
% DAMAGEPAIRS - Every same-layer pair whose tiles share at least one pixel.
% Unlike registration this INCLUDES diagonal pairs: a corner imaged twice is
% damaged whether or not the pair is ever measured.
numTiles = size(positions, 1);
pairList = zeros(0, 2);
for tileI = 1:numTiles - 1
    for tileJ = tileI + 1:numTiles
        if zLayers(tileI) ~= zLayers(tileJ); continue; end
        overlapRows = tileHeight - abs(positions(tileI, 1) - positions(tileJ, 1));
        overlapCols = tileWidth  - abs(positions(tileI, 2) - positions(tileJ, 2));
        if overlapRows >= 1 && overlapCols >= 1
            pairList(end+1, :) = [tileI, tileJ]; %#ok<AGROW>
        end
    end
end
end

% =========================================================================
function judged = judgeablePairs(pairList, positions, edges, tileHeight, tileWidth)
% JUDGEABLEPAIRS - Pairs whose shared strip is big enough to tell which is darker.
% Supplied edges win, as for the overlap-solved method: a seam the user excluded is
% one whose geometry is doubted, and a wrong geometry compares the wrong pixels.
numPairs = size(pairList, 1);
if ~isempty(edges) && isstruct(edges)
    validEdges = edges(logical([edges.valid]));
    edgePairs = sort([[validEdges.i]', [validEdges.j]'], 2);
    judged = ismember(pairList, edgePairs, 'rows');
    return;
end
judged = false(numPairs, 1);
for pairIdx = 1:numPairs
    tileI = pairList(pairIdx, 1);
    tileJ = pairList(pairIdx, 2);
    overlapRows = tileHeight - abs(positions(tileI, 1) - positions(tileJ, 1));
    overlapCols = tileWidth  - abs(positions(tileI, 2) - positions(tileJ, 2));
    % Side-by-side neighbours share at least half of the perpendicular extent; a
    % diagonal pair shares a corner only.
    judged(pairIdx) = overlapRows >= tileHeight / 2 || overlapCols >= tileWidth / 2;
end
end

% =========================================================================
function order = acquisitionRank(pairList, direction, numTiles)
% ACQUISITIONRANK - One acquisition order consistent with the decided seams.
%
% Each decided seam says "later minus earlier = 1"; least squares turns those into
% one rank per tile. A weak pull toward the LAYOUT order breaks ties (two tiles
% whose relative order no seam states - the two off-diagonal tiles of a 2x2),
% because layout order is usually acquisition order. A tile no decided seam
% touches gets ``NaN``: nothing places it.
decided = direction ~= 0;
order = nan(numTiles, 1);
if ~any(decided); return; end
pairs = pairList(decided, :);
later   = pairs(:, 2); earlier = pairs(:, 1);
flip = direction(decided) < 0;
later(flip)   = pairs(flip, 1);
earlier(flip) = pairs(flip, 2);
numDecided = numel(later);
constraintMatrix = sparse([1:numDecided, 1:numDecided], [later; earlier], ...
    [ones(numDecided, 1); -ones(numDecided, 1)], numDecided, numTiles);
priorWeight = 1e-3;
designMatrix = [constraintMatrix; priorWeight * speye(numTiles)];
target = [ones(numDecided, 1); priorWeight * (1:numTiles)' / numTiles];
rank = designMatrix \ target;
placed = false(numTiles, 1);
placed(unique([later; earlier])) = true;
order(placed) = rank(placed);
end

% =========================================================================
function direction = directionFromOrder(pairList, direction, judged, order)
% DIRECTIONFROMORDER - Orient the pairs no seam decided, from the acquisition rank.
% A JUDGED pair that showed no darkening keeps 0: its own pixels say there is
% nothing to correct, and that outranks any order.
for pairIdx = 1:size(pairList, 1)
    if judged(pairIdx); continue; end
    rankI = order(pairList(pairIdx, 1));
    rankJ = order(pairList(pairIdx, 2));
    if isfinite(rankI) && isfinite(rankJ) && rankI ~= rankJ
        direction(pairIdx) = sign(rankJ - rankI);
    end
end
end

% =========================================================================
function footprints = footprintTable(pairList, direction, positions, tileHeight, tileWidth)
% FOOTPRINTTABLE - ``[later rowMin rowMax colMin colMax]`` for every damaging pair.
% The rectangle is the EARLIER tile's pixel centres expressed in the later tile's
% frame; its boundary lies half a pixel outside them.
footprints = zeros(0, 5);
for pairIdx = 1:size(pairList, 1)
    if direction(pairIdx) == 0; continue; end
    [earlier, later] = orientPair(pairList(pairIdx, :), direction(pairIdx));
    rowMin = positions(earlier, 1) - positions(later, 1) + 1;
    colMin = positions(earlier, 2) - positions(later, 2) + 1;
    footprints(end+1, :) = [later, rowMin, rowMin + tileHeight - 1, ...
        colMin, colMin + tileWidth - 1]; %#ok<AGROW>
end
end

% =========================================================================
function [earlier, later] = orientPair(pair, direction)
% ORIENTPAIR - Split a pair into the tile imaged first and the one imaged after it.
if direction > 0
    earlier = pair(1); later = pair(2);
else
    earlier = pair(2); later = pair(1);
end
end

% =========================================================================
function [cropA, cropB, rowRange, colRange] = readOverlapPair(readerFcn, tileA, tileB, ...
    positions, tileHeight, tileWidth)
% READOVERLAPPAIR - The shared rectangle of two tiles, read from each.
% ``rowRange`` / ``colRange`` are the rectangle in ``tileB``'s own pixel frame.
rowStart = max(positions(tileA, 1), positions(tileB, 1));
rowEnd   = min(positions(tileA, 1), positions(tileB, 1)) + tileHeight - 1;
colStart = max(positions(tileA, 2), positions(tileB, 2));
colEnd   = min(positions(tileA, 2), positions(tileB, 2)) + tileWidth - 1;
boxA = [rowStart - positions(tileA, 1) + 1, rowEnd - positions(tileA, 1) + 1; ...
        colStart - positions(tileA, 2) + 1, colEnd - positions(tileA, 2) + 1];
boxB = [rowStart - positions(tileB, 1) + 1, rowEnd - positions(tileB, 1) + 1; ...
        colStart - positions(tileB, 2) + 1, colEnd - positions(tileB, 2) + 1];
cropA = flattenToPlane(readerFcn(tileA, boxA));
cropB = flattenToPlane(readerFcn(tileB, boxB));
rowRange = boxB(1, :);
colRange = boxB(2, :);
end

% =========================================================================
function cleanMask = plateauMask(rowRange, colRange, earlier, later, footprints, ...
    positions, tileHeight, tileWidth, guard, reach)
% PLATEAUMASK - Overlap pixels that show ONE full exposure against an undamaged reference.
% Rows/columns are the overlap in the later tile's frame. Three exclusions: the
% ``guard`` band along the overlap's own border (tile roll-off, the earlier tile's
% edge), anything within ``reach`` of another footprint in the later tile (a second
% exposure), and anything within ``reach`` of a footprint in the earlier tile (the
% reference damaged too).
rows = (rowRange(1):rowRange(2))';
cols = colRange(1):colRange(2);
cleanMask = (rows >= rowRange(1) + guard & rows <= rowRange(2) - guard) & ...
            (cols >= colRange(1) + guard & cols <= colRange(2) - guard);
ownRows = find(footprints(:, 1) == later);
offset = positions(later, :) - positions(earlier, :);   % later frame -> earlier frame
measured = [1 tileHeight 1 tileWidth] - [offset(1) offset(1) offset(2) offset(2)];
for footprintIdx = ownRows'
    fp = footprints(footprintIdx, 2:5);
    if all(abs(fp - measured) < 0.5); continue; end   % the footprint being measured
    cleanMask = cleanMask & ~((rows >= fp(1) - reach & rows <= fp(2) + reach) & ...
                              (cols >= fp(3) - reach & cols <= fp(4) + reach));
end
earlierRows = find(footprints(:, 1) == earlier);
for footprintIdx = earlierRows'
    fp = footprints(footprintIdx, 2:5) - [offset(1) offset(1) offset(2) offset(2)];
    cleanMask = cleanMask & ~((rows >= fp(1) - reach & rows <= fp(2) + reach) & ...
                              (cols >= fp(3) - reach & cols <= fp(4) + reach));
end
end

% =========================================================================
function [gain, offset] = fitPlateau(reference, damaged)
% FITPLATEAU - ``damaged = gain * reference + offset`` by total least squares.
% Both sides are block means of real pixels, so both carry noise and specimen;
% ordinary least squares would pull the gain toward zero by the reference's noise.
% A near-singular spread (a featureless overlap) falls back to a pure offset.
centred = [reference - mean(reference), damaged - mean(damaged)];
gain = 1;
if std(reference) > 1e-6 * max(1, abs(mean(reference)))
    [~, ~, rightVectors] = svd(centred, 0);
    principal = rightVectors(:, 1);
    if abs(principal(1)) > eps
        gain = principal(2) / principal(1);
    end
end
if ~isfinite(gain) || gain < 0.25 || gain > 4
    gain = 1;
end
offset = mean(damaged) - gain * mean(reference);
end

% =========================================================================
function acc = accumulateSide(acc, side, earlier, later, footprints, positions, ...
    readerFcn, damageAt, tileHeight, tileWidth, options, distanceGrid)
% ACCUMULATESIDE - Add one footprint side's evidence to the pooled profile sums.
%
% ``side`` 1..4 = the earlier tile's left / right / top / bottom side, seen inside
% the later tile. Works on an "across" axis (perpendicular to the side, distance
% measured outward) and an "along" axis. INSIDE the footprint the damage is read
% directly as ``(B - A) / dI(A)``; OUTSIDE there is no reference tile, so the
% damaged tile's mean along the edge is compared to a baseline drawn from the
% reference's content just inside the edge to the damaged tile's own undamaged
% far strip.
guard = options.edgeGuard;
reach = options.damageReach;
farWidthMax = options.damageFarWidth;

fp = footprints(footprints(:, 1) == later, :);
thisFootprint = [positions(earlier, 1) - positions(later, 1) + 1, 0, ...
                 positions(earlier, 2) - positions(later, 2) + 1, 0];
thisFootprint([2 4]) = thisFootprint([1 3]) + [tileHeight, tileWidth] - 1;
isThis = all(abs(fp(:, 2:5) - thisFootprint) < 0.5, 2);
otherFootprints = fp(~isThis, 2:5);
offsetToEarlier = positions(later, :) - positions(earlier, :);
earlierFootprints = footprints(footprints(:, 1) == earlier, 2:5);
earlierFootprints = earlierFootprints - [offsetToEarlier(1) offsetToEarlier(1) ...
    offsetToEarlier(2) offsetToEarlier(2)];

isVertical = side <= 2;         % left/right sides run along rows
isHigh = side == 2 || side == 4;
if isVertical
    acrossLength = tileWidth;  alongLength = tileHeight;
    acrossMin = thisFootprint(3); acrossMax = thisFootprint(4);
    alongMin  = thisFootprint(1); alongMax  = thisFootprint(2);
    acrossCols = [3 4]; alongCols = [1 2];
else
    acrossLength = tileHeight; alongLength = tileWidth;
    acrossMin = thisFootprint(1); acrossMax = thisFootprint(2);
    alongMin  = thisFootprint(3); alongMax  = thisFootprint(4);
    acrossCols = [1 2]; alongCols = [3 4];
end

% The side must lie inside the later tile with room on both sides of it. Pixels
% within `guard` of the later tile's own border are never used.
usableLow = 1 + guard; usableHigh = acrossLength - guard;
if isHigh
    if acrossMax < usableLow || acrossMax >= usableHigh; return; end
    insideCoords  = max(usableLow, acrossMin):acrossMax;
    outsideCoords = acrossMax + 1:min(usableHigh, acrossMax + reach + farWidthMax);
    distanceOf = @(c) c - (acrossMax + 0.5);
else
    if acrossMin > usableHigh || acrossMin <= usableLow; return; end
    insideCoords  = acrossMin:min(usableHigh, acrossMax);
    outsideCoords = max(usableLow, acrossMin - reach - farWidthMax):acrossMin - 1;
    distanceOf = @(c) (acrossMin - 0.5) - c;
end
if numel(insideCoords) < guard + 10; return; end
bandCoords = min([insideCoords, outsideCoords]):max([insideCoords, outsideCoords]);

% Along the side: stay `reach` clear of the footprint's own corners wherever they
% fall inside the tile, then drop every stretch another footprint could reach.
alongStart = max(1 + guard, alongMin + (alongMin > 1) * reach);
alongEnd   = min(alongLength - guard, alongMax - (alongMax < alongLength) * reach);
if alongEnd - alongStart < 32; return; end
alongCoords = alongStart:alongEnd;
clean = true(size(alongCoords));
for n = 1:size(otherFootprints, 1)
    other = otherFootprints(n, :);
    if other(acrossCols(2)) + reach >= bandCoords(1) && other(acrossCols(1)) - reach <= bandCoords(end)
        clean = clean & ~(alongCoords >= other(alongCols(1)) - reach & ...
                          alongCoords <= other(alongCols(2)) + reach);
    end
end
for n = 1:size(earlierFootprints, 1)
    other = earlierFootprints(n, :);
    if other(acrossCols(2)) + reach >= insideCoords(1) && other(acrossCols(1)) - reach <= insideCoords(end)
        clean = clean & ~(alongCoords >= other(alongCols(1)) - reach & ...
                          alongCoords <= other(alongCols(2)) + reach);
    end
end
if nnz(clean) < 32; return; end

% Read the damaged tile across the whole band and the reference across the inside.
if isVertical
    offsetAlong = offsetToEarlier(1); offsetAcross = offsetToEarlier(2);
    bandLater = flattenToPlane(readerFcn(later, [alongStart alongEnd; bandCoords(1) bandCoords(end)]));
    insideEarlier = flattenToPlane(readerFcn(earlier, ...
        [alongStart alongEnd; insideCoords(1) insideCoords(end)] + [offsetAlong; offsetAcross]));
else
    offsetAlong = offsetToEarlier(2); offsetAcross = offsetToEarlier(1);
    bandLater = flattenToPlane(readerFcn(later, [bandCoords(1) bandCoords(end); alongStart alongEnd])).';
    insideEarlier = flattenToPlane(readerFcn(earlier, ...
        [insideCoords(1) insideCoords(end); alongStart alongEnd] + [offsetAcross; offsetAlong])).';
end
bandLater     = double(bandLater(clean, :));
insideEarlier = double(insideEarlier(clean, :));
numAlong = nnz(clean);

bandDistance = distanceOf(bandCoords);
insideInBand = ismember(bandCoords, insideCoords);
insideDistance = bandDistance(insideInBand);
laterInside = bandLater(:, insideInBand);
gridIndex = @(d) round(d - distanceGrid(1)) + 1;

% Inside: direct comparison, except the reference's own edge roll-off.
trusted = insideDistance < -guard;
if any(trusted)
    idx = gridIndex(insideDistance(trusted));
    acc.numerIn(side, idx) = acc.numerIn(side, idx) + ...
        sum(laterInside(:, trusted) - insideEarlier(:, trusted), 1);
    acc.denomIn(side, idx) = acc.denomIn(side, idx) + sum(damageAt(insideEarlier(:, trusted)), 1);
end

% Outside: needs an undamaged far strip AND reference content next to the edge.
outsideInBand = bandDistance > 0;
outsideDistance = bandDistance(outsideInBand);
outsideSpan = numel(outsideDistance);
edgeWindow = insideDistance >= -guard - 20 & insideDistance < -guard;
if outsideSpan < max(20, 2 * guard) || ~any(edgeWindow); return; end
farWidth = min(farWidthMax, max(5, floor(outsideSpan / 4)));
[outsideDistance, sortOrder] = sort(outsideDistance);
columnMeans = mean(bandLater(:, outsideInBand), 1);
columnMeans = columnMeans(sortOrder);
farWindow = outsideSpan - farWidth + 1:outsideSpan;
truthFar  = mean(columnMeans(farWindow));
distanceFar = mean(outsideDistance(farWindow));
truthEdge = mean(insideEarlier(:, edgeWindow), 'all');
distanceEdge = mean(insideDistance(edgeWindow));
supported = 1:outsideSpan - farWidth;
baseline = truthEdge + (truthFar - truthEdge) * ...
    (outsideDistance(supported) - distanceEdge) / (distanceFar - distanceEdge);
supported = supported(outsideDistance(supported) <= distanceGrid(end));
baseline = baseline(1:numel(supported));
idx = gridIndex(outsideDistance(supported));
acc.numerOut(side, idx) = acc.numerOut(side, idx) + numAlong * (columnMeans(supported) - baseline);
acc.denomOut(side, idx) = acc.denomOut(side, idx) + numAlong * damageAt(baseline);
end

% =========================================================================
function profiles = finishProfiles(acc, distanceGrid, guard)
% FINISHPROFILES - Turn the pooled sums into four smooth, physical profiles.
%
% Per side: smooth, hold the deepest inside value flat, bridge the untrusted
% ``guard`` band next to the edge linearly, and constrain the outside part to be
% non-negative and non-increasing beyond its peak (damage cannot brighten, and a
% second bump far out is specimen leaking into the baseline). The whole profile is
% scaled so the plateau reads 1, which is what the fitted ``gain`` / ``offset``
% describe. A side no seam observed borrows its opposite (same scan axis), then the
% best-observed side, and without any evidence becomes a plain step.
numSides = 4;
profiles = zeros(numSides, numel(distanceGrid));
observed = false(numSides, 1);
support = zeros(numSides, 1);
inside = distanceGrid < 0;
for side = 1:numSides
    insideValues = acc.numerIn(side, :) ./ acc.denomIn(side, :);
    insideValues(~inside | acc.denomIn(side, :) == 0) = NaN;
    outsideValues = acc.numerOut(side, :) ./ acc.denomOut(side, :);
    outsideValues(inside | acc.denomOut(side, :) == 0) = NaN;
    trustedInside = inside & distanceGrid < -guard & isfinite(insideValues);
    if nnz(trustedInside) < 10 || ~any(isfinite(outsideValues)); continue; end

    plateau = median(insideValues(trustedInside));
    if ~isfinite(plateau) || plateau <= 0; continue; end

    profile = zeros(size(distanceGrid));
    % Inside: smoothed, and held at the deepest measured value further in.
    smoothedInside = smoothdata(insideValues(inside), 'gaussian', 9, 'omitnan');
    smoothedInside(~trustedInside(inside)) = NaN;
    smoothedInside = fillmissing(smoothedInside, 'nearest');
    profile(inside) = smoothedInside;

    % Outside: smoothed, non-negative, unimodal, and zero once it has decayed.
    outsideIdx = find(~inside);
    outsideSmoothed = smoothdata(outsideValues(outsideIdx), 'gaussian', 7, 'omitnan');
    measured = isfinite(outsideValues(outsideIdx));
    lastMeasured = find(measured, 1, 'last');
    outsideSmoothed(lastMeasured + 1:end) = 0;
    outsideSmoothed(~isfinite(outsideSmoothed)) = 0;
    outsideSmoothed = max(0, outsideSmoothed);
    [~, peakIdx] = max(outsideSmoothed);
    outsideSmoothed(peakIdx:end) = cummin(outsideSmoothed(peakIdx:end));
    decayed = find(outsideSmoothed(peakIdx:end) < 0.02 * plateau, 1, 'first');
    if ~isempty(decayed); outsideSmoothed(peakIdx + decayed - 1:end) = 0; end
    profile(outsideIdx) = outsideSmoothed;

    % Bridge the band next to the edge the reference cannot be trusted in.
    bridge = find(distanceGrid >= -guard & distanceGrid < 0);
    if ~isempty(bridge)
        anchorLow  = bridge(1) - 1;
        anchorHigh = outsideIdx(1);
        if anchorLow >= 1
            profile(bridge) = interp1([distanceGrid(anchorLow), distanceGrid(anchorHigh)], ...
                [profile(anchorLow), profile(anchorHigh)], distanceGrid(bridge));
        end
    end

    profiles(side, :) = profile / plateau;
    observed(side) = true;
    support(side) = nnz(acc.denomOut(side, :));
end

opposite = [2 1 4 3];
fallbackStep = double(inside);
for side = 1:numSides
    if observed(side); continue; end
    if observed(opposite(side))
        profiles(side, :) = profiles(opposite(side), :);
    elseif any(observed)
        [~, best] = max(support .* observed);
        profiles(side, :) = profiles(best, :);
    else
        profiles(side, :) = fallbackStep;
    end
end
end

% =========================================================================
function correction = levelMosaicPlane(correction, layout, positions, ...
    tileHeight, tileWidth, readerFcn)
% LEVELMOSAICPLANE - Spend the gauge freedom on a FLAT mosaic.
%
% Fitting the seams leaves one family of solutions, not one solution: for any
% plane ``a``,
%
%   field'(u) = field(u) * exp(a.u),  gain'_k = gain_k * exp(-a.c_k)
%
% (``c_k`` = tile k's centre in mosaic coordinates) reproduces **every seam
% difference exactly** - the reader divides by the field and multiplies by the
% gain, and the two changes cancel at any shared point. What it does change is
% the assembled mosaic, which comes out multiplied by ``exp(-a.x)``. So a global
% brightness plane can be added or removed for free, and *something* has to pick
% one. No seam residual can guide that choice: all of them are identical.
%
% The gain gauge in ``fitSeamModel`` picks one implicitly, and picks badly. By
% pushing brightness into the field it leaves each tile's mean where it was,
% so once the internal gradient is divided out the mosaic is a clean STAIRCASE
% of tile means. Measured on three SerialEM montages, as the mosaic's fitted
% brightness plane across x:
%
%   ==================  ==========  ================  ===============
%   montage              no corr.    field only        field + levelled
%   ==================  ==========  ================  ===============
%   ``Bat0/Cell01``        +4.9 %          **+9.2 %**           +0.5 %
%   ``Bat0/Cell10``        +0.5 %            +3.2 %             +0.3 %
%   ``Bat6/Cell3``         +2.3 %            +4.4 %             +0.1 %
%   ==================  ==========  ================  ===============
%
% Correcting the tiles made the mosaic ramp WORSE in all three - it trades a
% sawtooth for a monotone gradient, and the eye forgives a repeating pattern far
% more readily than a smooth one, so the montage with the largest starting trend
% read as a failure even at a 1.02 % seam residual. Seam rms is bit-identical
% before and after this step (1.02 / 0.13 / 0.64 % on the three above); that
% equality is the check that this really is a gauge move and not a second fit.
%
% .. note::
%    Only the PLANE is removable this way. A curved mosaic-scale trend would need
%    a per-tile spatially varying term, which the correction struct cannot carry
%    and which would no longer be free at the seams.
%
% .. warning::
%    A genuine linear brightness trend in the SPECIMEN is removed too - nothing
%    here can tell the two apart, and by construction nothing measurable can. It
%    is levelled because a montage that shades from one side to the other reads
%    as an artefact whatever its cause. Pass ``levelMosaic = false`` to keep it.

numTiles = numel(layout);
if numTiles < 3; return; end

% Corrected tile means. The correction is applied here rather than through a
% second reader so the raw tiles stay in the cache the seam pass just filled.
correctedLogMeans = nan(numTiles, 1);
fieldPatch = double(correction.field);
for tileIdx = 1:numTiles
    tilePlane = flattenToPlane(readerFcn(tileIdx));
    if ~isequal(size(tilePlane), [tileHeight, tileWidth]); return; end
    tileMean = mean(double(tilePlane) ./ fieldPatch, 'all') * correction.gain(tileIdx);
    if isfinite(tileMean) && tileMean > 0
        correctedLogMeans(tileIdx) = log(tileMean);
    end
end

usable = isfinite(correctedLogMeans);
if sum(usable) < 3; return; end

% Tile centres on the SAME scale the field's coordinates use, so the fitted
% slope can be added straight to the field.
centres = [(positions(:, 2) + (tileWidth  - 1) / 2) / (tileWidth  / 2), ...
           (positions(:, 1) + (tileHeight - 1) / 2) / (tileHeight / 2)];

% Plain least squares, deliberately: each point is already a mean over millions
% of pixels, so this is not noise-limited but specimen-limited, and down-weighting
% a tile that disagrees would be down-weighting real specimen. lsqminnorm keeps a
% single-row or single-column montage well posed - the unobservable direction then
% simply gets zero slope.
designMatrix = [ones(sum(usable), 1), centres(usable, :)];
planeCoefficients = lsqminnorm(designMatrix, correctedLogMeans(usable));
planeXY = planeCoefficients(2:3);
if ~all(isfinite(planeXY)) || all(planeXY == 0); return; end

[allCols, allRows] = meshgrid(1:tileWidth, 1:tileHeight);
tileCoords = normalizeCoords(allRows(:), allCols(:), tileHeight, tileWidth);
adjustedField = double(correction.field) .* ...
    reshape(exp(tileCoords * planeXY), tileHeight, tileWidth);

fieldMean = mean(adjustedField, 'all');
if ~isfinite(fieldMean) || fieldMean <= 0; return; end
adjustedField = adjustedField / fieldMean;

adjustedGains = correction.gain .* exp(-(centres * planeXY));
adjustedGains = adjustedGains / exp(mean(log(adjustedGains)));
if ~all(isfinite(adjustedGains)) || any(adjustedGains <= 0); return; end

correction.field       = single(max(adjustedField, 0.05));
correction.gain        = adjustedGains(:);
correction.mosaicPlane = planeXY(:)';

end

% =========================================================================
function [chosenDegree, report] = chooseFieldDegree(samples, numTiles, tileHeight, tileWidth, options)
% CHOOSEFIELDDEGREE - Let the data say how flexible the illumination model may be.
%
% Two independent tests, and BOTH have to pass, because neither can do the job
% alone:
%
% 1. **Cross-validation over whole SEAMS.** Fit on all but one fold of the seams
%    and predict the held-out ones. This is what catches a degree that is fitting
%    noise in the border strips rather than real structure. Whole seams are the
%    held-out unit, not random blocks: holding out blocks from a seam the fit has
%    already seen tests nothing but interpolation.
%
%    The held-out error is measured on the MEAN-REMOVED residual, i.e. how well
%    the field explains the way the mismatch VARIES along the seam. The constant
%    part belongs to the two tiles' gains, and a tile whose only seam is held out
%    has no gain left - scoring that would measure the fold, not the model.
%
% 2. **The interior check.** Seams observe the field only near tile borders, so
%    NO cross-validation over seams - held out or not - can see the polynomial
%    bowing in the tile centre. That failure is invisible to every seam-based
%    number, which is exactly how it shipped once. It needs its own veto.
%
% Ties go to the simpler model: a degree is only preferred over a lower one when
% it improves held-out error by a clear margin, because the extra freedom is
% spent in a region nothing measures.

report = struct('degree', {}, 'heldOutError', {}, 'interiorDeviation', {}, 'accepted', {});
seamIds = unique(samples.seamId);
numSeams = numel(seamIds);

% With very few seams there is nothing to hold out; fall back to the lowest
% degree that survives the interior check.
numFolds = min(5, numSeams);
canCrossValidate = numFolds >= 3;

foldOfSeam = zeros(numSeams, 1);
if canCrossValidate
    foldOfSeam = mod(0:numSeams-1, numFolds)' + 1;
end

% An explicit degree is honoured, but still has to pass the interior check - a
% forced degree that bows is the exact failure this guard exists for.
candidateDegrees = 1:options.maxPolynomialDegree;
if ~isempty(options.polynomialDegree)
    candidateDegrees = options.polynomialDegree;
end

for degree = candidateDegrees
    if polynomialTermCount(degree) >= numel(samples.logRatio); break; end

    % --- interior check on the full fit ---
    [coefficients, ~] = fitSeamModel(samples, degree, numTiles, ...
        true(size(samples.logRatio)), options.robustIterations);
    fittedField = evaluateField(coefficients, degree, tileHeight, tileWidth);
    if isempty(fittedField)
        interiorDeviation = Inf;
    else
        interiorDeviation = abs(interiorToBorderRatio(fittedField) - 1);
    end

    % --- held-out seam error ---
    if canCrossValidate
        foldErrors = nan(numFolds, 1);
        for fold = 1:numFolds
            heldOutSeams = seamIds(foldOfSeam == fold);
            testMask  = ismember(samples.seamId, heldOutSeams);
            trainMask = ~testMask;
            if ~any(trainMask) || ~any(testMask); continue; end
            % Fewer IRLS passes during selection: this runs numFolds x degrees
            % times and the weights barely move after the second pass.
            foldCoefficients = fitSeamModel(samples, degree, numTiles, trainMask, 2);
            foldErrors(fold) = heldOutSeamError(samples, foldCoefficients, degree, testMask);
        end
        heldOutError = mean(foldErrors, 'omitnan');
    else
        heldOutError = NaN;
    end

    report(end+1) = struct('degree', degree, 'heldOutError', heldOutError, ...
        'interiorDeviation', interiorDeviation, ...
        'accepted', interiorDeviation <= options.maxInteriorDeviation); %#ok<AGROW>
end

accepted = [report.accepted];
chosenDegree = [];
if ~any(accepted); return; end

acceptedDegrees = [report(accepted).degree];
acceptedErrors  = [report(accepted).heldOutError];

if all(isnan(acceptedErrors))
    % No cross-validation was possible: take the simplest model that passed.
    chosenDegree = acceptedDegrees(1);
    return;
end

% Parsimony: the simplest degree within a margin of the best held-out error. The
% extra freedom of a higher degree is spent where nothing observes it, so it has
% to earn its place rather than merely tie.
bestError = min(acceptedErrors);
withinMargin = acceptedErrors <= bestError * (1 + options.degreeSelectionMargin);
chosenDegree = acceptedDegrees(find(withinMargin, 1, 'first'));

end

% =========================================================================
function [fieldCoefficients, logGains] = fitSeamModel(samples, degree, numTiles, includeMask, robustIterations)
% FITSEAMMODEL - Robust least squares for the field coefficients + per-tile gains.

numBasis = polynomialTermCount(degree);
basisI = polynomialBasis(samples.coordsI(includeMask, :), degree);
basisJ = polynomialBasis(samples.coordsJ(includeMask, :), degree);
observed = samples.logRatio(includeMask);

tileI = samples.tileI(includeMask);
tileJ = samples.tileJ(includeMask);
numSamples = numel(observed);
rowIdx = (1:numSamples)';
gainColumns = sparse([rowIdx; rowIdx], [tileI; tileJ], ...
    [ones(numSamples, 1); -ones(numSamples, 1)], numSamples, numTiles);

designMatrix = [basisI - basisJ, full(gainColumns)];

% ---- Gauge: three directions the seams genuinely cannot see ----
% 1. A common offset on every log gain (it cancels in every difference).
% 2 and 3. On a REGULAR grid, a LINEAR term in the field produces a difference
%    that is the same at every pixel of a seam - which is exactly what a pair of
%    gains produces. Field tilt and a matching ramp of per-tile gains are
%    therefore indistinguishable from seam data alone, one ambiguity per axis.
%
% Both explanations fit the seams equally well but give different mosaics, so
% something has to choose. A weak ridge on the gains resolves all three by
% preferring to explain brightness with the field. It acts only inside the null
% space, so it cannot bias the part of the solution the seams DO determine.
%
% This ridge is NOT the final word on the two tilt directions: it only has to
% leave a well-posed system. Which plane the mosaic ends up with is decided
% afterwards by `levelMosaicPlane`, which re-gauges the solved field and gains
% together so the assembled mosaic comes out flat. Do not "improve" the ridge
% here to shape the mosaic - it is the wrong end of the pipeline, and the two
% would fight.
%
% NOTE: there is deliberately NO matching ridge on the FIELD coefficients. It
% looks like the obvious cure for interior bowing and is a trap: it competes with
% this one, and past ~0.05 it wins, flattening the field to nothing so the gains
% absorb everything. That fits the seams just as well while leaving every tile's
% internal gradient in place - the sawtooth this gauge exists to avoid. Degree is
% the honest lever, and it is now chosen by chooseFieldDegree.
ridgeWeight = 1e-3 * sqrt(numSamples);
designMatrix = [designMatrix; zeros(numTiles, numBasis), ridgeWeight * eye(numTiles)];
observed     = [observed; zeros(numTiles, 1)];
numGaugeRows = numTiles;

% Iteratively reweighted least squares with a Huber loss: residual misregistration
% and genuinely non-overlapping content (debris, a charged patch) would otherwise
% pull the field toward a handful of blocks.
weights = ones(size(observed));
solution = zeros(numBasis + numTiles, 1);
for iteration = 1:max(1, robustIterations)
    weighted = designMatrix .* weights;
    solution = weighted \ (observed .* weights);
    residual = designMatrix * solution - observed;
    scale = 1.4826 * median(abs(residual - median(residual)));
    if ~isfinite(scale) || scale <= 0; break; end
    huberK = 1.5 * scale;
    weights = min(1, huberK ./ max(abs(residual), eps));
    weights(end - numGaugeRows + 1:end) = 1;    % never down-weight the gauge rows
end

fieldCoefficients = solution(1:numBasis);
logGains          = solution(numBasis + 1:end);

end

% =========================================================================
function heldOutError = heldOutSeamError(samples, fieldCoefficients, degree, testMask)
% HELDOUTSEAMERROR - How well the field predicts seams it was not fitted on.
%
% Scored on the MEAN-REMOVED residual per seam: the constant part of a seam's
% mismatch belongs to the two tiles' gains, and a tile whose only seam is in the
% held-out fold has no gain estimate at all. Removing the mean measures what the
% field is actually responsible for - the way the mismatch varies ALONG the seam.
predicted = polynomialBasis(samples.coordsI(testMask, :), degree) * fieldCoefficients - ...
            polynomialBasis(samples.coordsJ(testMask, :), degree) * fieldCoefficients;
residual = samples.logRatio(testMask) - predicted;

seamIds = samples.seamId(testMask);
uniqueSeams = unique(seamIds);
perSeam = zeros(numel(uniqueSeams), 1);
for k = 1:numel(uniqueSeams)
    seamResidual = residual(seamIds == uniqueSeams(k));
    perSeam(k) = std(seamResidual - mean(seamResidual));
end
heldOutError = mean(perSeam);

end

% =========================================================================
function illuminationField = evaluateField(fieldCoefficients, degree, tileHeight, tileWidth)
% EVALUATEFIELD - Expand the fitted coefficients over a whole tile, mean 1.
[allCols, allRows] = meshgrid(1:tileWidth, 1:tileHeight);
logField = polynomialBasis(normalizeCoords(allRows(:), allCols(:), tileHeight, tileWidth), ...
    degree) * fieldCoefficients;
illuminationField = reshape(exp(logField), tileHeight, tileWidth);
fieldMean = mean(illuminationField, 'all');
if ~isfinite(fieldMean) || fieldMean <= 0
    illuminationField = [];
    return;
end
illuminationField = illuminationField / fieldMean;
end

% =========================================================================
function ratio = interiorToBorderRatio(illuminationField)
% INTERIORTOBORDERRATIO - Fitted field in the tile CENTRE versus at its BORDERS.
%
% Seams pin the field near the borders only, so this ratio is the one number that
% exposes a polynomial bowing where nothing observes it. It cannot be derived from
% any seam residual - the fit minimises those - which is why it is checked apart.
[tileHeight, tileWidth] = size(illuminationField);
borderWidth = max(8, round(0.1 * min(tileHeight, tileWidth)));
borderMask = false(tileHeight, tileWidth);
borderMask([1:borderWidth, end-borderWidth+1:end], :) = true;
borderMask(:, [1:borderWidth, end-borderWidth+1:end]) = true;
centreRows = round(tileHeight/2) + (-round(tileHeight/8):round(tileHeight/8));
centreCols = round(tileWidth/2)  + (-round(tileWidth/8):round(tileWidth/8));
ratio = mean(illuminationField(centreRows, centreCols), 'all') / ...
        mean(illuminationField(borderMask));
end

% =========================================================================
function pairList = overlappingPairs(layout, positions, edges, tileHeight, tileWidth)
% OVERLAPPINGPAIRS - Tile pairs whose placed rectangles share enough pixels.
% Supplied edges win: a seam excluded in the inspector is one the user judged
% wrong, and a wrong seam should not steer the intensity fit either.
minOverlapPx = 16;
if ~isempty(edges) && isstruct(edges)
    validEdges = edges(logical([edges.valid]));
    pairList = [[validEdges.i]', [validEdges.j]'];
    return;
end
numTiles = numel(layout);
pairList = zeros(0, 2);
for tileI = 1:numTiles - 1
    for tileJ = tileI + 1:numTiles
        overlapRows = tileHeight - abs(positions(tileI, 1) - positions(tileJ, 1));
        overlapCols = tileWidth  - abs(positions(tileI, 2) - positions(tileJ, 2));
        if overlapRows >= minOverlapPx && overlapCols >= minOverlapPx
            pairList(end+1, :) = [tileI, tileJ]; %#ok<AGROW>
        end
    end
end
end

% =========================================================================
function plane = flattenToPlane(tileData)
% FLATTENTOPLANE - [H W D C] -> [H W], averaging depth and colour.
plane = single(tileData);
plane = mean(reshape(plane, size(plane, 1), size(plane, 2), []), 3);
end

% =========================================================================
function blockSize = chooseBlockSize(cropSize, targetSamples)
% CHOOSEBLOCKSIZE - Block edge that yields roughly `targetSamples` blocks.
blockSize = sqrt(prod(cropSize) / max(1, targetSamples));
blockSize = max(4, min([floor(blockSize), floor(cropSize / 2)]));
end

% =========================================================================
function [blocked, rowCentres, colCentres] = blockMean(plane, blockSize)
% BLOCKMEAN - Non-overlapping block means, plus each block's centre coordinate.
numRowBlocks = floor(size(plane, 1) / blockSize);
numColBlocks = floor(size(plane, 2) / blockSize);
trimmed = plane(1:numRowBlocks * blockSize, 1:numColBlocks * blockSize);
blocked = reshape(trimmed, blockSize, numRowBlocks, blockSize, numColBlocks);
blocked = squeeze(mean(mean(blocked, 1), 3));
if numRowBlocks == 1 || numColBlocks == 1
    blocked = reshape(blocked, numRowBlocks, numColBlocks);
end
rowCentres = ((1:numRowBlocks) - 0.5) * blockSize;
colCentres = ((1:numColBlocks) - 0.5) * blockSize;
end

% =========================================================================
function coords = normalizeCoords(rows, cols, tileHeight, tileWidth)
% NORMALIZECOORDS - Tile pixel coordinates onto [-1, 1], as [x y] columns.
coords = [(cols(:) - (tileWidth  + 1) / 2) / (tileWidth  / 2), ...
          (rows(:) - (tileHeight + 1) / 2) / (tileHeight / 2)];
end

% =========================================================================
function termCount = polynomialTermCount(degree)
% POLYNOMIALTERMCOUNT - Terms of a 2-D polynomial up to `degree`, no constant.
termCount = (degree + 1) * (degree + 2) / 2 - 1;
end

% =========================================================================
function basis = polynomialBasis(coords, degree)
% POLYNOMIALBASIS - 2-D polynomial terms up to `degree`, EXCLUDING the constant.
%
% The constant is left out deliberately: it cancels in every seam difference, so
% it carries no information and would make the system rank-deficient. The field's
% overall level is restored afterwards by normalising it to mean 1.
%
% A LOW degree is the point, not a limitation to work around. Seams only observe
% the field near the tile borders, and the polynomial is what carries that into
% the tile centre; a flexible basis would fit noise at the edges and extrapolate
% it wildly through the middle.
xCoord = coords(:, 1);
yCoord = coords(:, 2);
basis = zeros(numel(xCoord), polynomialTermCount(degree));
columnIdx = 0;
for totalDegree = 1:degree
    for xPower = totalDegree:-1:0
        columnIdx = columnIdx + 1;
        basis(:, columnIdx) = xCoord.^xPower .* yCoord.^(totalDegree - xPower);
    end
end
end
