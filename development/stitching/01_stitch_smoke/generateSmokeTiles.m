function generateSmokeTiles()
% GENERATESMOKETILES - Create the synthetic 3x3 tile set for stitching smoke tests.
%
% Ground truth: 900x1200 uint8 image = smoothed noise background (texture for
% phase correlation) + randomly oriented straight lines and circles spanning the
% whole canvas. The lines make stitching quality visible at a glance: any
% misplacement breaks a line at the tile seam.
%
% Tiles: 3x3 grid of 340x460 tiles, nominal 15% overlap, +-5 px jitter on the
% true cut positions, clamped to the canvas (right/bottom tiles end up to ~42 px
% away from their nominal grid positions - a deliberate stress test).
%
% Outputs (in <repoRoot>\temp\stitching_test\01_stitch_smoke):
%   tiles\tile_01..09.tif  - the jittered tiles, Horizontal (raster) order
%   groundTruth.tif        - the full mosaic ground truth
%   trueOrigins.mat        - 9x2 [y x] true cut origins (1-based)
%
% Load in MIB (smoke_tests.md tests 1, 2, 8, 9):
%   Stitch ribbon -> Layout source = "Grid"
%   -> Browse to temp\stitching_test\01_stitch_smoke\tiles
%   -> Rows 3, Cols 3, Overlap ~15 (or tick "Estimate overlap")
%   -> Measure overlaps -> Optimize positions -> Stitch.

% Generator lives in development\stitching\01_stitch_smoke; output goes to the
% project temp folder so test data never lands in the tracked docs tree. The
% output folder is prefixed with its smoke_tests.md test number.
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
outputFolder = fullfile(repoRoot, 'temp', 'stitching_test', '01_stitch_smoke');
tilesFolder  = fullfile(outputFolder, 'tiles');
if ~isfolder(tilesFolder); mkdir(tilesFolder); end

canvasH = 900; canvasW = 1200;
tileH = 340; tileW = 460;
overlapFraction = 0.15;
jitterPx = 5;

% ---- background: two-scale smoothed noise + gentle gradient --------------
% Fine scale gives phase correlation a sharp autocorrelation peak; coarse
% scale adds visible cloudy texture.
rng(7, 'twister');
pixelNoise    = randn(canvasH, canvasW);                   % unsmoothed: sharp correlation peak
fineTexture   = imfilter(randn(canvasH, canvasW), fspecial('gaussian', [7 7], 1.2), 'replicate');
coarseTexture = imfilter(randn(canvasH, canvasW), fspecial('gaussian', [21 21], 4.0), 'replicate');
pixelNoise    = pixelNoise / std(pixelNoise(:));
fineTexture   = fineTexture / std(fineTexture(:));
coarseTexture = coarseTexture / std(coarseTexture(:));
background = 0.25 * pixelNoise + 0.35 * fineTexture + 0.40 * coarseTexture;
background = (background - min(background(:))) / (max(background(:)) - min(background(:)));
[xx, yy] = meshgrid(1:canvasW, 1:canvasH);
img = 0.60 * background + 0.12 * (xx / canvasW) + 0.08 * (yy / canvasH) + 0.10;

% ---- embedded lines: random orientation and offset (non-periodic!) ------
% Periodic line grids would create repeated-pattern ambiguity for the phase
% correlation; random lines keep every overlap unique. Lines are BLENDED (not
% saturated) on purpose: a single dominant line in a thin overlap strip makes
% the translation ambiguous along the line direction - enough lines at varied
% angles plus visible background texture pin the registration, while broken
% lines at seams still expose stitching errors immediately.
numLines = 22;
lineHalfWidth = 1.3;
lineOpacity = 0.45;
for lineIdx = 1:numLines
    theta = rand() * pi;                                   % line normal angle
    rho   = rand() * hypot(canvasH, canvasW) * 0.9;        % distance from origin
    distanceToLine = abs(xx * cos(theta) + yy * sin(theta) - rho);
    lineMask = distanceToLine < lineHalfWidth;
    if mod(lineIdx, 2) == 0
        img(lineMask) = img(lineMask) * (1 - lineOpacity) + lineOpacity;   % bright
    else
        img(lineMask) = img(lineMask) * (1 - lineOpacity);                 % dark
    end
end

% ---- embedded circles (curvature pins translation in both axes) ----------
circleSpec = [250 300 140; 700 620 200; 480 1000 110; 150 900 90];  % [cy cx radius]
for circleIdx = 1:size(circleSpec, 1)
    distanceToCircle = abs(hypot(xx - circleSpec(circleIdx, 2), ...
                                 yy - circleSpec(circleIdx, 1)) - circleSpec(circleIdx, 3));
    circleMask = distanceToCircle < lineHalfWidth;
    img(circleMask) = img(circleMask) * (1 - lineOpacity) + lineOpacity;
end

groundTruth = uint8(255 * max(min(img, 1), 0));
imwrite(groundTruth, fullfile(outputFolder, 'groundTruth.tif'));

% ---- cut jittered tiles ---------------------------------------------------
stepY = round(tileH * (1 - overlapFraction));   % 289
stepX = round(tileW * (1 - overlapFraction));   % 391
rng(42, 'twister');
trueOrigins = zeros(9, 2);
tileIdx = 0;
for row = 1:3
    for col = 1:3
        tileIdx = tileIdx + 1;
        originY = 1 + (row - 1) * stepY + randi([-jitterPx, jitterPx]);
        originX = 1 + (col - 1) * stepX + randi([-jitterPx, jitterPx]);
        originY = min(max(originY, 1), canvasH - tileH + 1);
        originX = min(max(originX, 1), canvasW - tileW + 1);
        trueOrigins(tileIdx, :) = [originY, originX];
        tileImage = groundTruth(originY:originY + tileH - 1, originX:originX + tileW - 1);
        imwrite(tileImage, fullfile(tilesFolder, sprintf('tile_%02d.tif', tileIdx)));
    end
end

save(fullfile(outputFolder, 'trueOrigins.mat'), 'trueOrigins');
fprintf('Generated 9 tiles (%dx%d, step [%d %d], jitter +-%d px) into %s\n', ...
    tileH, tileW, stepY, stepX, jitterPx, tilesFolder);
disp(trueOrigins);
end
