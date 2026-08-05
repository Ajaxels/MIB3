function montage = makeMdocMontage(folderPath, options)
% MAKEMDOCMONTAGE - Write a synthetic SerialEM 2x2 montage (MRC stack + .mdoc).
%
% Syntax:
%   .. code-block:: matlab
%
%      montage = mibtest.helpers.makeMdocMontage(folderPath)
%      montage = mibtest.helpers.makeMdocMontage(folderPath, options)
%
% Produces the two files a SerialEM montage acquisition leaves behind - one MRC
% stack whose SLICES are the tiles, and the ``.mdoc`` placing them - reproducing
% the format's traps rather than an idealised version of it:
%
%   - the montage frame's Y axis runs UP, so grid row 1 has the LARGEST
%     ``PieceCoordinates`` Y and slice order does not follow row order;
%   - slices are written in SerialEM's acquisition order (Y fastest within each
%     X column), so a reader that assumes row-major numbering mixes the tiles up;
%   - the edge shifts are stated for the LOWER piece and are therefore NEGATED
%     relative to the correction they imply;
%   - ``XedgeDxy`` is absent on the last column and ``YedgeDxy`` on the last row,
%     because a piece records only the seams to its higher neighbours;
%   - the ``.mdoc`` is named after the image INCLUDING its extension
%     (``montage.mrc.mdoc``).
%
% Geometry: 64 px tiles on a NOMINAL 48 px step, while the true step is 44 px in
% X and 42 px in Y - deliberately different per axis, so an axis swap or a sign
% error cannot pass unnoticed. The tiles are CUT FROM ONE TEXTURED IMAGE at the
% true offsets, which is what makes the montage testable end to end: the
% ``AlignedPieceCoords`` / edge-shift placement is the pixel-correct one (seams
% score ~1) while ``PieceCoordinates`` is wrong by 4 px in X and 6 px in Y - the
% same shape of error that makes SerialEM's rough placement unusable on real data.
%
% Input Arguments:
%   - **folderPath** - [char] folder to write into; created when absent.
%   - **options** *(optional)* - struct with fields:
%
%     - ``.writeEdges`` - [logical] write ``XedgeDxy``/``YedgeDxy`` (default: ``true``)
%     - ``.writeAligned`` - [logical] write ``AlignedPieceCoords`` (default: ``true``)
%     - ``.asFloat`` - [logical] write the stack as float32 (MRC mode 2), so the
%       header-based intensity scaling is exercised; ``false`` writes uint8
%       (mode 0, passthrough) (default: ``false``)
%     - ``.shadingPercent`` - [double] peak-to-peak per-tile illumination gradient
%       to bake in, as a TEM beam off centre produces: bright on one side, dark on
%       the other, IDENTICAL in every tile. ``0`` (default) leaves the tiles flat.
%       The gradient is applied AFTER the tiles are cut, so the geometry is
%       untouched and only the intensities differ - which is what makes it a fair
%       test of :func:`utils.stitch.estimateIntensityCorrection`
%     - ``.tileGains`` - [1xN double] per-tile flat multiplier applied on top,
%       for exercising ``'Match tile means'``. ``[]`` (default) leaves them equal
%     - ``.plainTexture`` - [logical] cut the tiles from HIGH-FREQUENCY noise with
%       no global ramp, instead of :func:`mibtest.helpers.stitchTextureImage`
%       (which deliberately adds one to help phase correlation). Needed when
%       testing illumination-field estimation: with only four heavily-overlapping
%       tiles the specimen's own low-frequency structure does NOT average out, so
%       a ramped source makes the estimate unrecoverable by construction
%       (default: ``false``)
%     - ``.montageKey`` - [logical] write the ``Montage = 1`` global (default: ``true``)
%     - ``.writePieceCoords`` - [logical] write ``PieceCoordinates`` at all; set
%       ``false`` to synthesise a TILT SERIES, which is not stitchable
%       (default: ``true``)
%     - ``.baseName`` - [char] image file name (default: ``'montage.mrc'``)
%     - ``.textureSeed`` - [double] seed for the source texture (default: ``91``)
%
% Output Arguments:
%   - **montage** - struct with ``.folder``, ``.mdocPath``, ``.imagePath``,
%     ``.tileSizePx``, ``.nominalStepPx``, ``.trueStepXpx``, ``.trueStepYpx``,
%     ``.gridRowColOfSlice`` (``[numTiles x 2]``, grid position of each slice) and
%     ``.expectedOriginRC`` (``[numTiles x 2]``, the TRUE 1-based ``[row col]``
%     origin of each slice, in layout order).
%
% **Example** - a montage SerialEM never stitched:
%
%   .. code-block:: matlab
%
%      montage = mibtest.helpers.makeMdocMontage(tempFolder, ...
%          struct('writeEdges', false, 'writeAligned', false));
%      layout = utils.stitch.buildLayoutMdoc(montage.mdocPath);
%
% See also utils.stitch.buildLayoutMdoc, utils.stitch.findMdocSidecar,
% mibtest.helpers.makeAtlasMosaic

arguments
    folderPath (1,:) char
    options    struct = struct()
end

if ~isfield(options, 'writeEdges');       options.writeEdges = true; end
if ~isfield(options, 'writeAligned');     options.writeAligned = true; end
if ~isfield(options, 'asFloat');          options.asFloat = false; end
if ~isfield(options, 'montageKey');       options.montageKey = true; end
if ~isfield(options, 'writePieceCoords'); options.writePieceCoords = true; end
if ~isfield(options, 'baseName');         options.baseName = 'montage.mrc'; end
if ~isfield(options, 'textureSeed');      options.textureSeed = 91; end
if ~isfield(options, 'shadingPercent');   options.shadingPercent = 0; end
if ~isfield(options, 'tileGains');        options.tileGains = []; end
if ~isfield(options, 'plainTexture');     options.plainTexture = false; end

if ~isfolder(folderPath); mkdir(folderPath); end

tileSizePx    = 64;
nominalStepPx = 48;
trueStepXpx   = 44;      % nominal is 4 px too wide
trueStepYpx   = 42;      % nominal is 6 px too tall
numRows       = 2;
numCols       = 2;
pixelSpacingA = 18.38;   % Angstroms, as SerialEM writes it

% ---- Slices in SerialEM's acquisition order: Y fastest within each X ----
% PieceCoordinates Y runs UP, so the LARGEST Y is grid row 1.
sliceGridRowCol = zeros(numRows * numCols, 2);
piecePosition   = zeros(numRows * numCols, 2);   % [pieceX pieceY]
sliceIdx = 0;
for colIdx = 1:numCols
    for pieceYstep = 0:numRows - 1
        sliceIdx = sliceIdx + 1;
        % pieceY 0 is the BOTTOM of the montage = the LAST grid row.
        rowIdx = numRows - pieceYstep;
        sliceGridRowCol(sliceIdx, :) = [rowIdx, colIdx];
        piecePosition(sliceIdx, :)   = [(colIdx - 1) * nominalStepPx, pieceYstep * nominalStepPx];
    end
end
numTiles = sliceIdx;

% Solved placement: the same frame, but on the TRUE step.
alignedPosition = zeros(numTiles, 2);
for tileIdx = 1:numTiles
    rowIdx = sliceGridRowCol(tileIdx, 1);
    colIdx = sliceGridRowCol(tileIdx, 2);
    alignedPosition(tileIdx, :) = [(colIdx - 1) * trueStepXpx, (numRows - rowIdx) * trueStepYpx];
end

% ---- Tiles cut from one texture at the TRUE offsets ----
sourceHeight = tileSizePx + trueStepYpx;
sourceWidth  = tileSizePx + trueStepXpx;
if options.plainTexture
    % High-frequency content only. stitchTextureImage adds a global ramp on
    % purpose; here it would be indistinguishable from the illumination field the
    % test is trying to recover.
    rng(options.textureSeed, 'twister');
    plainNoise = imfilter(randn(sourceHeight, sourceWidth), ...
        fspecial('gaussian', [7 7], 1.4), 'replicate');
    plainNoise = plainNoise / std(plainNoise(:));
    sourceImage = uint8(min(255, max(0, 128 + 28 * plainNoise)));
else
    sourceImage = mibtest.helpers.stitchTextureImage(sourceHeight, sourceWidth, ...
        options.textureSeed);
end

% The same gradient in every tile, applied AFTER cutting: geometry untouched,
% only the intensities differ. A diagonal (not pure X or Y) so a transposed
% field cannot pass.
shadingField = ones(tileSizePx, tileSizePx, 'single');
if options.shadingPercent ~= 0
    [shadeXX, shadeYY] = meshgrid(linspace(-1, 1, tileSizePx), linspace(-1, 1, tileSizePx));
    shadingField = 1 + (options.shadingPercent / 100) * (0.62 * shadeXX + 0.38 * shadeYY) / 2;
end

stack = zeros(tileSizePx, tileSizePx, numTiles, 'single');
for tileIdx = 1:numTiles
    topRow  = (sliceGridRowCol(tileIdx, 1) - 1) * trueStepYpx + 1;
    leftCol = (sliceGridRowCol(tileIdx, 2) - 1) * trueStepXpx + 1;
    tilePixels = single(sourceImage(topRow:topRow + tileSizePx - 1, ...
                                    leftCol:leftCol + tileSizePx - 1));
    tilePixels = tilePixels .* shadingField;
    if ~isempty(options.tileGains)
        tilePixels = tilePixels * options.tileGains(tileIdx);
    end
    stack(:, :, tileIdx) = tilePixels;
end
if ~options.asFloat
    stack = uint8(max(0, min(255, stack)));
end
if options.asFloat
    % An offset range no unsigned class would produce, so a reader that skips
    % the header-based rescale gives visibly wrong pixels.
    stack = single(stack) * 37.5 + 12000;
end

imagePath = fullfile(folderPath, options.baseName);
saveOptions.volumeFilename = imagePath;
saveOptions.pixSize     = struct('x', pixelSpacingA / 10000, 'y', pixelSpacingA / 10000, ...
                                 'z', pixelSpacingA / 10000, 'units', 'um');
saveOptions.showWaitbar = false;
io.mibImage2mrc(stack, saveOptions);

% ---- The .mdoc ----
% SerialEM appends .mdoc to the whole image name, extension included.
mdocPath = [imagePath, '.mdoc'];
fileId = fopen(mdocPath, 'w');
closeFile = onCleanup(@() fclose(fileId));

fprintf(fileId, 'PixelSpacing = %.2f\n', pixelSpacingA);
fprintf(fileId, 'Voltage = 100\n');
fprintf(fileId, 'ImageFile = %s\n', ['E:\acquired\session\', options.baseName]);
fprintf(fileId, 'ImageSize = %d %d\n', tileSizePx, tileSizePx);
if options.montageKey
    fprintf(fileId, 'Montage = 1\n');
end
fprintf(fileId, 'DataMode = %d\n\n', 6 * ~options.asFloat + 2 * options.asFloat);
fprintf(fileId, '[T = SerialEM: synthetic montage for MIB tests]\n\n');

for tileIdx = 1:numTiles
    fprintf(fileId, '[ZValue = %d]\n', tileIdx - 1);
    if options.writePieceCoords
        fprintf(fileId, 'PieceCoordinates = %d %d 0\n', piecePosition(tileIdx, :));
    end
    fprintf(fileId, 'TiltAngle = 0\n');
    fprintf(fileId, 'PixelSpacing = %.2f\n', pixelSpacingA);
    fprintf(fileId, 'Magnification = 6000\n');
    if options.writeAligned && options.writePieceCoords
        fprintf(fileId, 'AlignedPieceCoords = %d %d 0\n', alignedPosition(tileIdx, :));
    end
    if options.writeEdges && options.writePieceCoords
        % The shift is stated for the LOWER piece, so it is the NEGATION of the
        % correction the nominal step needs: nominal + [dy_key, -dx_key] = true.
        % X seam: true - nominal = trueStepX - nominalStepX along the column axis.
        if sliceGridRowCol(tileIdx, 2) < numCols
            fprintf(fileId, 'XedgeDxy = %.1f %.1f\n', nominalStepPx - trueStepXpx, 0);
        end
        % Y seam: the neighbour at higher pieceY is one grid row UP.
        if sliceGridRowCol(tileIdx, 1) > 1
            fprintf(fileId, 'YedgeDxy = %.1f %.1f\n', 0, nominalStepPx - trueStepYpx);
        end
    end
    fprintf(fileId, '\n');
end

fprintf(fileId, '[MontSection = 0]\n');
fprintf(fileId, 'TiltAngle = 0\n');
fprintf(fileId, 'FullMontSize = %d %d\n', ...
    (numCols - 1) * nominalStepPx + tileSizePx, (numRows - 1) * nominalStepPx + tileSizePx);

% ---- What a correct read should produce ----
% Layout order is by grid row then column; the true origin follows the true step.
[~, layoutOrder] = sortrows(sliceGridRowCol);
expectedOriginRC = zeros(numTiles, 2);
for outIdx = 1:numTiles
    tileIdx = layoutOrder(outIdx);
    expectedOriginRC(outIdx, :) = [ ...
        (sliceGridRowCol(tileIdx, 1) - 1) * trueStepYpx + 1, ...
        (sliceGridRowCol(tileIdx, 2) - 1) * trueStepXpx + 1];
end

montage = struct();
montage.folder             = folderPath;
montage.mdocPath           = mdocPath;
montage.imagePath          = imagePath;
montage.tileSizePx         = tileSizePx;
montage.nominalStepPx      = nominalStepPx;
montage.trueStepXpx        = trueStepXpx;
montage.trueStepYpx        = trueStepYpx;
montage.numTiles           = numTiles;
montage.gridRowColOfSlice  = sliceGridRowCol;
montage.layoutOrder        = layoutOrder;
montage.expectedOriginRC   = expectedOriginRC;
montage.shadingField       = shadingField;   % normalised to 1 at the centre
montage.tileGains          = options.tileGains;

end
