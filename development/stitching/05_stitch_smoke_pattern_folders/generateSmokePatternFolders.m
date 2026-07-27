function generateSmokePatternFolders()
% GENERATESMOKEPATTERNFOLDERS - Filename-pattern + folder-Z-stack smoke example.
%
% Creates a 2x2 set of tiles where each tile is a FOLDER of slice images (a
% Z-stack) and each FOLDER is named with the MIB2 chop pattern
% ``_Z##-X##-Y##`` — the tokens the "Filename pattern" layout source parses.
% This exercises the "Tiles are folders (Z-stacks)" modifier with the Filename
% pattern source (the combination that fails when folders are named grid-style,
% e.g. ``tile_r1c1``, because those carry no Z/X/Y tokens).
%
% Ground truth: a textured volume whose every Z-slice carries the SAME randomly
% oriented lines + circles as the 2D smoke case (``stitch_smoke``). The
% lines/circles make stitching quality visible at a glance — any XY misplacement
% breaks a line or circle at the tile seam on every slice. Tiles are cut with a
% real ~22% XY overlap and small jitter, so the Filename pattern source's overlap
% support is exercised end-to-end (measure + optimize actually register them).
%
% Outputs (in <repoRoot>\temp\stitching_test\05_stitch_smoke_pattern_folders):
%   stack_Z01-X01-Y01 .. stack_Z01-X02-Y02   - four folders of slice_###.tif
%
% Load in MIB (smoke_tests.md test 5):
%   Stitch ribbon -> Layout source = "Filename pattern", check "Tiles are folders
%   (Z-stacks)" -> set Overlap X/Y ~= 22 (or tick "Estimate overlap")
%   -> Browse (multi-select stack_Z01-X01-Y01 ... stack_Z01-X02-Y02, or pick the
%   parent folder) -> Measure overlaps -> Optimize positions -> Stitch.

% Generator lives in development\stitching\05_stitch_smoke_pattern_folders; output
% goes to the project temp folder so test data never lands in the tracked tree.
% The output folder is prefixed with its smoke_tests.md test number.
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
outputFolder = fullfile(repoRoot, 'temp', 'stitching_test', '05_stitch_smoke_pattern_folders');
if ~isfolder(outputFolder); mkdir(outputFolder); end

canvasH = 460; canvasW = 460; depth = 12;
tileH = 240; tileW = 240;
overlapFraction = 0.22;
xyJitter = 4;
stepY = round(tileH * (1 - overlapFraction));
stepX = round(tileW * (1 - overlapFraction));

% ---- 2D ground-truth pattern: 3-scale noise + gradient + lines + circles ----
% (same recipe as stitch_smoke\generateSmokeTiles.m; unsmoothed pixel noise
% gives phase correlation a sharp peak, blended lines/circles expose seams.)
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
patternXY = 0.60 * background + 0.12 * (xx / canvasW) + 0.08 * (yy / canvasH) + 0.10;

% Randomly oriented, blended lines (non-periodic → unique overlaps).
numLines = 16;
lineHalfWidth = 1.3;
lineOpacity = 0.45;
for lineIdx = 1:numLines
    theta = rand() * pi;
    rho   = rand() * hypot(canvasH, canvasW) * 0.9;
    distanceToLine = abs(xx * cos(theta) + yy * sin(theta) - rho);
    lineMask = distanceToLine < lineHalfWidth;
    if mod(lineIdx, 2) == 0
        patternXY(lineMask) = patternXY(lineMask) * (1 - lineOpacity) + lineOpacity;
    else
        patternXY(lineMask) = patternXY(lineMask) * (1 - lineOpacity);
    end
end

% Circles (curvature pins translation in both axes).
circleSpec = [130 150 90; 330 300 120; 210 400 70; 380 90 60];   % [cy cx radius]
for circleIdx = 1:size(circleSpec, 1)
    distanceToCircle = abs(hypot(xx - circleSpec(circleIdx, 2), ...
                                 yy - circleSpec(circleIdx, 1)) - circleSpec(circleIdx, 3));
    circleMask = distanceToCircle < lineHalfWidth;
    patternXY(circleMask) = patternXY(circleMask) * (1 - lineOpacity) + lineOpacity;
end

% ---- extrude into a volume: same pattern each slice + mild per-slice noise ----
% Consistent lines/circles through depth so a bad XY seam shows on every slice;
% the small per-slice noise keeps the stack from being a perfect extrusion.
volume = zeros(canvasH, canvasW, depth, 'uint8');
for z = 1:depth
    sliceNoise = 0.04 * imfilter(randn(canvasH, canvasW), fspecial('gaussian', [5 5], 1.0), 'replicate');
    slice = max(min(patternXY + sliceNoise, 1), 0);
    volume(:, :, z) = uint8(255 * slice);
end

% ---- cut 2x2 overlapping folder tiles, named with the _Z##-X##-Y## pattern ----
clampOrigin = @(o, tileSize, volSize) min(max(o, 1), volSize - tileSize + 1);
rng(23, 'twister');
for xIdx = 1:2
    for yIdx = 1:2
        oy = clampOrigin(1 + (yIdx - 1) * stepY + randi([-xyJitter xyJitter]), tileH, canvasH);
        ox = clampOrigin(1 + (xIdx - 1) * stepX + randi([-xyJitter xyJitter]), tileW, canvasW);
        tileVolume = volume(oy:oy + tileH - 1, ox:ox + tileW - 1, :);

        tileFolder = fullfile(outputFolder, sprintf('stack_Z01-X%02d-Y%02d', xIdx, yIdx));
        if ~isfolder(tileFolder); mkdir(tileFolder); end
        for z = 1:depth
            imwrite(tileVolume(:, :, z), fullfile(tileFolder, sprintf('slice_%03d.tif', z)));
        end
    end
end

fprintf('Generated 4 pattern-named folder tiles (%dx%dx%d each, ~%d%% overlap) in %s\n', ...
    tileH, tileW, depth, round(overlapFraction * 100), outputFolder);
fprintf('Folders: stack_Z01-X01-Y01, stack_Z01-X01-Y02, stack_Z01-X02-Y01, stack_Z01-X02-Y02\n');
end
