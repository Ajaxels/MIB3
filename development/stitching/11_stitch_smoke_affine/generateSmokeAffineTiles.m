function generateSmokeAffineTiles()
% GENERATESMOKEAFFINETILES - Rotated/scaled tile set for the Affine transform type.
%
% Creates a 2x2 grid of 300 px tiles (25% nominal overlap) where every tile
% except the first is cut from the ground-truth image with its OWN small affine
% warp: +-1 degree rotation, +-1% scale, and +-8 px XY jitter. A translation
% solve cannot make these tiles agree — the seams stay visibly rotated/doubled
% (note the residual rating can still look good: on a small grid the rotation
% shows up as in-overlap misalignment, not loop inconsistency). TransformType =
% Affine measures full pairwise affine transforms, solves them globally, and
% warp-fuses the tiles back into a seamless mosaic.
%
% Outputs (in <repoRoot>\temp\stitching_test\11_stitch_smoke_affine):
%   tiles\tile_01..04.tif  - the warped tiles, Horizontal (raster) order
%   groundTruth.tif        - the full mosaic ground truth
%   trueTforms.mat         - {4x1} true tile-local -> global 3x3 maps (xy)
%
% Load in MIB (smoke_tests.md test 11; run TWICE to compare):
%   Stitch ribbon -> Layout source = "Grid"
%   -> Browse to temp\stitching_test\11_stitch_smoke_affine\tiles
%   -> Rows 2, Cols 2, Overlap 25, UNTICK "Estimate overlap"
%   A) Transform type = "Translation" -> Measure overlaps -> Optimize positions
%      (the rating may still look good, but Stitch shows rotated/doubled seams)
%   B) Transform type = "Affine" -> Measure overlaps -> Optimize positions
%      -> Stitch (expect an Excellent rating and clean seams)

% Generator lives in development\stitching\11_stitch_smoke_affine; output goes to
% the project temp folder so test data never lands in the tracked tree. The
% output folder is prefixed with its smoke_tests.md test number.
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
outputFolder = fullfile(repoRoot, 'temp', 'stitching_test', '11_stitch_smoke_affine');
tilesFolder  = fullfile(outputFolder, 'tiles');
if ~isfolder(tilesFolder); mkdir(tilesFolder); end

canvasH = 640; canvasW = 640;
tileSize = 300;
overlapFraction = 0.25;
step = round(tileSize * (1 - overlapFraction));   % 225
maxRotationDeg = 1.0;
maxScaleFraction = 0.01;
jitterPx = 8;

% ---- ground truth: 3-scale noise + gradient + lines + circles -------------
% Same recipe as stitch_smoke_feature: the blobs and line/circle crossings give
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

numLines = 18;
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
circleSpec = [180 220 110; 460 420 130; 320 540 80];   % [cy cx radius]
for circleIdx = 1:size(circleSpec, 1)
    distanceToCircle = abs(hypot(xx - circleSpec(circleIdx, 2), ...
                                 yy - circleSpec(circleIdx, 1)) - circleSpec(circleIdx, 3));
    circleMask = distanceToCircle < lineHalfWidth;
    img(circleMask) = img(circleMask) * (1 - lineOpacity) + lineOpacity;
end

groundTruth = uint8(255 * max(min(img, 1), 0));
imwrite(groundTruth, fullfile(outputFolder, 'groundTruth.tif'));

% ---- cut tiles, each with its own affine warp ------------------------------
% trueTforms{t} maps tile-local 1-based xy pixel coordinates to ground-truth
% coordinates; the tile is produced by the inverse warp tile(v) = truth(G*v).
rng(42, 'twister');
trueTforms = cell(4, 1);
tileIdx = 0;
for row = 1:2
    for col = 1:2
        tileIdx = tileIdx + 1;
        nominalXY = [1 + (col - 1) * step; 1 + (row - 1) * step];
        if tileIdx == 1
            % anchor tile: identity at nominal, matching the solver's gauge
            linearPart = eye(2);
            translation = nominalXY - 1;
        else
            angleRad = deg2rad((rand() - 0.5) * 2 * maxRotationDeg);
            scale = 1 + (rand() - 0.5) * 2 * maxScaleFraction;
            linearPart = scale * [cos(angleRad), -sin(angleRad); sin(angleRad), cos(angleRad)];
            translation = nominalXY - 1 + (rand(2, 1) - 0.5) * 2 * jitterPx;
        end
        trueTform = [linearPart, translation; 0 0 1];
        trueTforms{tileIdx} = trueTform;
        tileImage = imwarp(groundTruth, affinetform2d(inv(trueTform)), 'linear', ...
            'OutputView', imref2d([tileSize tileSize]), 'FillValues', 0);
        imwrite(tileImage, fullfile(tilesFolder, sprintf('tile_%02d.tif', tileIdx)));
    end
end

save(fullfile(outputFolder, 'trueTforms.mat'), 'trueTforms');
fprintf('Generated 4 affine-warped tiles (%dx%d, step %d, rot +-%.1f deg, scale +-%.0f%%, jitter +-%d px) into %s\n', ...
    tileSize, tileSize, step, maxRotationDeg, maxScaleFraction * 100, jitterPx, tilesFolder);
end
