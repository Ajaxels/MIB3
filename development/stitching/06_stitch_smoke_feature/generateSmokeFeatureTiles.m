function generateSmokeFeatureTiles()
% GENERATESMOKEFEATURETILES - Large-jitter tile set where Feature-based wins.
%
% Creates a 3x3 grid of tiles with 25% nominal overlap but LARGE (+-55 px)
% jitter on the true cut positions. The restricted-search phase correlation
% measures only the nominal overlap strip, so with jitter comparable to the
% overlap most of its edges come out invalid or wrong - while the Feature-based
% method matches descriptors across the FULL tiles and recovers the offsets.
% This is the dataset for comparing the two registration methods side by side.
%
% Outputs (in <repoRoot>\temp\stitching_test\06_stitch_smoke_feature):
%   tiles\tile_01..09.tif  - the jittered tiles, Horizontal (raster) order
%   groundTruth.tif        - the full mosaic ground truth
%   trueOrigins.mat        - 9x2 [y x] true cut origins (1-based)
%
% Load in MIB (smoke_tests.md tests 6 and 10; run TWICE to compare):
%   Stitch ribbon -> Layout source = "Grid"
%   -> Browse to temp\stitching_test\06_stitch_smoke_feature\tiles
%   -> Rows 3, Cols 3, Overlap 25, UNTICK "Estimate overlap"
%   A) Registration method = "Phase correlation"  -> Measure overlaps
%      (expect few valid edges / visible seam breaks after Stitch)
%   B) Registration method = "Feature-based" (SURF) -> Measure overlaps
%      -> Optimize positions -> Stitch (expect clean seams)

% Generator lives in development\stitching\06_stitch_smoke_feature; output goes to
% the project temp folder so test data never lands in the tracked tree. The
% output folder is prefixed with its smoke_tests.md test number.
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
outputFolder = fullfile(repoRoot, 'temp', 'stitching_test', '06_stitch_smoke_feature');
tilesFolder  = fullfile(outputFolder, 'tiles');
if ~isfolder(tilesFolder); mkdir(tilesFolder); end

canvasH = 880; canvasW = 880;
tileSize = 300;
overlapFraction = 0.25;
jitterPx = 55;                       % comparable to the 75 px overlap strip
step = round(tileSize * (1 - overlapFraction));   % 225

% ---- ground truth: 3-scale noise + gradient + lines + circles -------------
% Same recipe as stitch_smoke; the coarse blobs and line/circle crossings give
% SURF-class detectors plenty of distinctive keypoints across the whole tile.
rng(7, 'twister');
pixelNoise    = randn(canvasH, canvasW);
fineTexture   = imfilter(randn(canvasH, canvasW), fspecial('gaussian', [7 7], 1.2), 'replicate');
coarseTexture = imfilter(randn(canvasH, canvasW), fspecial('gaussian', [21 21], 4.0), 'replicate');
pixelNoise    = pixelNoise / std(pixelNoise(:));
fineTexture   = fineTexture / std(fineTexture(:));
coarseTexture = coarseTexture / std(coarseTexture(:));
background = 0.25 * pixelNoise + 0.35 * fineTexture + 0.40 * coarseTexture;
background = (background - min(background(:))) / (max(background(:)) - min(background(:)));
[xx, yy] = meshgrid(1:canvasW, 1:canvasH);
img = 0.60 * background + 0.12 * (xx / canvasW) + 0.08 * (yy / canvasH) + 0.10;

numLines = 22;
lineHalfWidth = 1.3;
lineOpacity = 0.45;
for lineIdx = 1:numLines
    theta = rand() * pi;
    rho   = rand() * hypot(canvasH, canvasW) * 0.9;
    distanceToLine = abs(xx * cos(theta) + yy * sin(theta) - rho);
    lineMask = distanceToLine < lineHalfWidth;
    if mod(lineIdx, 2) == 0
        img(lineMask) = img(lineMask) * (1 - lineOpacity) + lineOpacity;
    else
        img(lineMask) = img(lineMask) * (1 - lineOpacity);
    end
end
circleSpec = [220 260 130; 620 560 170; 420 760 100; 140 700 80];   % [cy cx radius]
for circleIdx = 1:size(circleSpec, 1)
    distanceToCircle = abs(hypot(xx - circleSpec(circleIdx, 2), ...
                                 yy - circleSpec(circleIdx, 1)) - circleSpec(circleIdx, 3));
    circleMask = distanceToCircle < lineHalfWidth;
    img(circleMask) = img(circleMask) * (1 - lineOpacity) + lineOpacity;
end

groundTruth = uint8(255 * max(min(img, 1), 0));
imwrite(groundTruth, fullfile(outputFolder, 'groundTruth.tif'));

% ---- cut tiles with LARGE jitter ------------------------------------------
rng(42, 'twister');
trueOrigins = zeros(9, 2);
tileIdx = 0;
for row = 1:3
    for col = 1:3
        tileIdx = tileIdx + 1;
        originY = 1 + (row - 1) * step + randi([-jitterPx, jitterPx]);
        originX = 1 + (col - 1) * step + randi([-jitterPx, jitterPx]);
        originY = min(max(originY, 1), canvasH - tileSize + 1);
        originX = min(max(originX, 1), canvasW - tileSize + 1);
        trueOrigins(tileIdx, :) = [originY, originX];
        tileImage = groundTruth(originY:originY + tileSize - 1, originX:originX + tileSize - 1);
        imwrite(tileImage, fullfile(tilesFolder, sprintf('tile_%02d.tif', tileIdx)));
    end
end

save(fullfile(outputFolder, 'trueOrigins.mat'), 'trueOrigins');
fprintf('Generated 9 tiles (%dx%d, step %d, jitter +-%d px) into %s\n', ...
    tileSize, tileSize, step, jitterPx, tilesFolder);
disp(trueOrigins);
end
