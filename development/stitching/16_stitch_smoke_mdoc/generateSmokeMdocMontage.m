function generateSmokeMdocMontage()
% GENERATESMOKEMDOCMONTAGE - A SerialEM montage: one MRC stack + its .mdoc.
%
% Creates a 3x3 montage in the shape SerialEM leaves on disk, so the "Position
% file" layout source can be exercised on SerialEM data without proprietary data.
% Unlike every other smoke dataset the tiles are NOT separate files: they are the
% SLICES of a single MRC stack, which is the whole point of this source.
%
% The format's real traps are reproduced:
%
%   - the montage frame's Y axis runs UP, so grid row 1 has the LARGEST
%     ``PieceCoordinates`` Y and the slice order does not follow row order;
%   - slices written in SerialEM's acquisition order (Y fastest within each X
%     column), so a reader that assumes row-major numbering mixes the tiles up;
%   - edge shifts stated for the LOWER piece, and therefore NEGATED relative to
%     the correction they imply;
%   - ``XedgeDxy`` absent on the last column, ``YedgeDxy`` absent on the last row;
%   - the sidecar named after the image INCLUDING its extension
%     (``Montage_SMOKE.mrc.mdoc``);
%   - float32 pixels on an offset range, so the header-based intensity rescale is
%     exercised rather than a passthrough.
%
% **The nominal piece grid is deliberately wrong.** As on real SerialEM data the
% recorded step does not match the pixels - here 6 px too long in Y and 4 px in X
% - while ``XedgeDxy``/``YedgeDxy`` and ``AlignedPieceCoords`` describe the CORRECT
% placement, so:
%
%   Nominal grid only                 -> visible seam steps until MIB re-measures
%   SerialEM seam measurements        -> MIB solves to the truth without registering
%   SerialEM seams + solved positions -> already correct; Stitch fuses as it stands
%
% A per-tile ILLUMINATION GRADIENT is baked in as well (bright on one side, dark
% on the other, as a poorly centred TEM beam produces). It does not affect the
% geometry, but it makes the seams visible as intensity steps even when the
% alignment is perfect - the effect that per-tile mean matching cannot fix.
%
% Outputs (in <repoRoot>\temp\stitching_test\16_stitch_smoke_mdoc):
%   Montage_SMOKE.mrc            - the 9 tiles, one per slice (float32)
%   Montage_SMOKE.mrc.mdoc       - piece coordinates, edge shifts, aligned coords
%   trueOrigins.mat              - trueOrigins 9x2 [y x] true cut origins, in
%                                  layout order (by grid row then column)
%
% Load in MIB (smoke_tests.md test 16):
%   Stitch ribbon -> Layout source = "Position file"
%   -> Browse (pick Montage_SMOKE.mrc.mdoc OR Montage_SMOKE.mrc)
%   -> answer the import dialog.

repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
outputFolder = fullfile(repoRoot, 'temp', 'stitching_test', '16_stitch_smoke_mdoc');
if ~isfolder(outputFolder); mkdir(outputFolder); end

numRows   = 3;
numCols   = 3;
tileSize  = 240;
trueStepX = 180;            % 25% overlap - what the pixels actually show
trueStepY = 180;
nominalErrorXpx = 4;        % the recorded step is this much too long
nominalErrorYpx = 6;
pixelSpacingA   = 18.38;    % Angstroms, as SerialEM writes it
shadingPercent  = 6;        % peak-to-peak per-tile illumination gradient

canvasH = tileSize + (numRows - 1) * trueStepY;
canvasW = tileSize + (numCols - 1) * trueStepX;

% ---- Ground truth: texture + lines + circles, so a bad seam is visible ----
rng(16, 'twister');
pixelNoise    = randn(canvasH, canvasW);
fineTexture   = imfilter(randn(canvasH, canvasW), fspecial('gaussian', [7 7], 1.2), 'replicate');
coarseTexture = imfilter(randn(canvasH, canvasW), fspecial('gaussian', [21 21], 4.0), 'replicate');
pixelNoise    = pixelNoise / std(pixelNoise(:));
fineTexture   = fineTexture / std(fineTexture(:));
coarseTexture = coarseTexture / std(coarseTexture(:));
background = 0.25 * pixelNoise + 0.35 * fineTexture + 0.40 * coarseTexture;
background = (background - min(background(:))) / (max(background(:)) - min(background(:)));
[xx, yy] = meshgrid(1:canvasW, 1:canvasH);
% NO monotonic ramp across the canvas - unlike the other smoke generators. A
% ramp is indistinguishable from an illumination field to a mean-based estimator
% (every tile would show the same slope, which is exactly what it calls
% illumination), so a ramped canvas makes this dataset useless for testing the
% Intensity correction correction. The coarse random texture in `background` supplies
% the large-scale variation instead, and that DOES average out across tiles.
img = 0.60 * background + 0.20;

lineHalfWidth = 1.3;
lineOpacity = 0.45;
for lineIdx = 1:20
    theta = rand() * pi;
    rho   = rand() * hypot(canvasH, canvasW) * 0.9;
    lineMask = abs(xx * cos(theta) + yy * sin(theta) - rho) < lineHalfWidth;
    if mod(lineIdx, 2) == 0
        img(lineMask) = img(lineMask) * (1 - lineOpacity) + lineOpacity;
    else
        img(lineMask) = img(lineMask) * (1 - lineOpacity);
    end
end
circleSpec = [180 200 120; 460 430 150; 300 540 90; 520 150 80];   % [cy cx radius]
for circleIdx = 1:size(circleSpec, 1)
    circleMask = abs(hypot(xx - circleSpec(circleIdx, 2), ...
                           yy - circleSpec(circleIdx, 1)) - circleSpec(circleIdx, 3)) < lineHalfWidth;
    img(circleMask) = img(circleMask) * (1 - lineOpacity) + lineOpacity;
end
groundTruth = max(min(img, 1), 0);

% ---- Per-tile illumination gradient (the TEM beam-profile effect) ----
[tileXX, tileYY] = meshgrid(linspace(-1, 1, tileSize), linspace(-1, 1, tileSize));
shadingField = 1 + (shadingPercent / 100) * (0.62 * tileXX + 0.38 * tileYY) / 2;

% ---- Slices in SerialEM's acquisition order: Y fastest within each X ----
% PieceCoordinates Y runs UP, so the LARGEST Y is grid row 1.
nominalStepX = trueStepX + nominalErrorXpx;
nominalStepY = trueStepY + nominalErrorYpx;

sliceGridRowCol = zeros(numRows * numCols, 2);
piecePosition   = zeros(numRows * numCols, 2);   % [pieceX pieceY], nominal
alignedPosition = zeros(numRows * numCols, 2);   % [pieceX pieceY], true
sliceIdx = 0;
for colIdx = 1:numCols
    for pieceYstep = 0:numRows - 1
        sliceIdx = sliceIdx + 1;
        rowIdx = numRows - pieceYstep;           % pieceY 0 is the LAST grid row
        sliceGridRowCol(sliceIdx, :) = [rowIdx, colIdx];
        piecePosition(sliceIdx, :)   = [(colIdx - 1) * nominalStepX, pieceYstep * nominalStepY];
        alignedPosition(sliceIdx, :) = [(colIdx - 1) * trueStepX,    pieceYstep * trueStepY];
    end
end
numTiles = sliceIdx;

% ---- Cut the tiles at the TRUE offsets, shade them, stack them ----
stack = zeros(tileSize, tileSize, numTiles, 'single');
trueOriginsBySlice = zeros(numTiles, 2);
for tileIdx = 1:numTiles
    originY = 1 + (sliceGridRowCol(tileIdx, 1) - 1) * trueStepY;
    originX = 1 + (sliceGridRowCol(tileIdx, 2) - 1) * trueStepX;
    trueOriginsBySlice(tileIdx, :) = [originY, originX];
    tile = groundTruth(originY:originY + tileSize - 1, originX:originX + tileSize - 1);
    % Offset float range no unsigned class would produce, so a reader that skips
    % the header-based rescale gives visibly wrong pixels.
    stack(:, :, tileIdx) = single(tile .* shadingField) * 24000 + 180000;
end

imagePath = fullfile(outputFolder, 'Montage_SMOKE.mrc');
saveOptions.volumeFilename = imagePath;
saveOptions.pixSize     = struct('x', pixelSpacingA / 10000, 'y', pixelSpacingA / 10000, ...
                                 'z', pixelSpacingA / 10000, 'units', 'um');
saveOptions.showWaitbar = false;
io.mibImage2mrc(stack, saveOptions);

% ---- The .mdoc ----
mdocPath = [imagePath, '.mdoc'];
fileId = fopen(mdocPath, 'w');
closeFile = onCleanup(@() fclose(fileId));

fprintf(fileId, 'PixelSpacing = %.2f\n', pixelSpacingA);
fprintf(fileId, 'Voltage = 100\n');
fprintf(fileId, 'ImageFile = %s\n', 'E:\acquired\session\SMOKE\Montage_SMOKE.mrc');
fprintf(fileId, 'ImageSize = %d %d\n', tileSize, tileSize);
fprintf(fileId, 'Montage = 1\n');
fprintf(fileId, 'DataMode = 2\n\n');
fprintf(fileId, '[T = SerialEM: synthetic smoke montage for MIB]\n\n');

for tileIdx = 1:numTiles
    fprintf(fileId, '[ZValue = %d]\n', tileIdx - 1);
    fprintf(fileId, 'PieceCoordinates = %d %d 0\n', piecePosition(tileIdx, :));
    fprintf(fileId, 'TiltAngle = 0\n');
    fprintf(fileId, 'PixelSpacing = %.2f\n', pixelSpacingA);
    fprintf(fileId, 'Magnification = 6000\n');
    fprintf(fileId, 'AlignedPieceCoords = %d %d 0\n', alignedPosition(tileIdx, :));
    % The shift is stated for the LOWER piece, so it is the NEGATION of the
    % correction the nominal step needs: nominal + [dy_key, -dx_key] = true.
    if sliceGridRowCol(tileIdx, 2) < numCols          % has a neighbour at higher X
        fprintf(fileId, 'XedgeDxy = %.1f %.1f\n', nominalErrorXpx, 0);
    end
    if sliceGridRowCol(tileIdx, 1) > 1                % has a neighbour at higher Y
        fprintf(fileId, 'YedgeDxy = %.1f %.1f\n', 0, nominalErrorYpx);
    end
    fprintf(fileId, '\n');
end

fprintf(fileId, '[MontSection = 0]\n');
fprintf(fileId, 'TiltAngle = 0\n');
fprintf(fileId, 'FullMontSize = %d %d\n', ...
    (numCols - 1) * nominalStepX + tileSize, (numRows - 1) * nominalStepY + tileSize);
clear closeFile;   % flush and close before anything reads the file back

% ---- Ground truth in LAYOUT order (by grid row then column) ----
[~, layoutOrder] = sortrows(sliceGridRowCol);
trueOrigins = trueOriginsBySlice(layoutOrder, :);
save(fullfile(outputFolder, 'trueOrigins.mat'), 'trueOrigins');

fprintf('SerialEM smoke montage written to %s\n', outputFolder);
fprintf('  %d tiles as slices of Montage_SMOKE.mrc (%dx%d, float32)\n', ...
    numTiles, tileSize, tileSize);
fprintf('  nominal step is %d px too long in X and %d px in Y; the edges/aligned coords are correct\n', ...
    nominalErrorXpx, nominalErrorYpx);
fprintf('  per-tile illumination gradient: %g%% peak-to-peak\n', shadingPercent);

end
