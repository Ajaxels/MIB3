function generateSmokeSabotageTiles()
% GENERATESMOKESABOTAGETILES - The "confidently wrong edge" dataset for the seam inspector.
%
% Creates a 1x3 tile CHAIN (no graph redundancy), measures it properly, then
% CORRUPTS the 2-3 edge by +24 px with quality 0.95 — emulating a repetitive-
% content lock one period off — solves, and saves everything as a
% ``sabotage.mibstitch.json`` project. On a chain there is no loop to
% contradict the corruption: the global solve satisfies every edge EXACTLY
% (residual RMSE ~0, rating chip green) while tile 3 sits 24 px off. Solver
% residuals cannot see this failure; only re-checking actual pixels at the
% solved placement (utils.stitch.scoreSeams — the seam inspector's ranking)
% catches it. See development/stitching/plan_inspector.md.
%
% Why corrupt the edge instead of the imagery: phase correlation whitens the
% spectrum and RANSAC ratio-tests repeated descriptors, so both estimators
% resist deterministic image-level sabotage (verified: a 55%-stripe band with
% a 12 px phase shift is STILL measured correctly by phase correlation). The
% corrupted-edge project reproduces the failure state itself, whatever
% real-world content caused it.
%
% Requires the mib folder on the path (uses utils.stitch.*).
%
% Outputs (in <repoRoot>\temp\stitching_test\12_stitch_smoke_sabotage):
%   tiles\tile_01..03.tif    - the tiles (Horizontal order)
%   sabotage.mibstitch.json  - project with the corrupted 2-3 edge + solved positions
%   groundTruth.tif          - the full ground truth
%   trueOrigins.mat          - 3x2 [y x] true cut origins (1-based)
%
% Inspector smoke (smoke_tests.md test 12):
%   Stitch ribbon -> Load project ->
%   temp\stitching_test\12_stitch_smoke_sabotage\sabotage.mibstitch.json
%   -> Optimize positions (rating comes out GOOD — the corruption is
%   residual-invisible) -> Inspect and fix...
%   The 2-3 seam must rank first with a low seam score (pixels disagree at the
%   solved placement); the lines/circles across that seam appear broken by
%   ~24 px. Exclude (X) + Re-solve pulls tile 3 back to its nominal-spring
%   position (within the ~5 px cut jitter of truth — the seam score IMPROVES
%   but stays modest, because exclusion recovers only coarsely). Phase C's
%   click-to-correlate FIXES the edge instead, recovering to sub-pixel.

% Generator lives in development\stitching\12_stitch_smoke_sabotage; output goes
% to the project temp folder so test data never lands in the tracked tree. The
% output folder is prefixed with its smoke_tests.md test number.
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
outputFolder = fullfile(repoRoot, 'temp', 'stitching_test', '12_stitch_smoke_sabotage');
tilesFolder  = fullfile(outputFolder, 'tiles');
if ~isfolder(tilesFolder); mkdir(tilesFolder); end

tileSize = 300;
overlapFraction = 0.25;
step = round(tileSize * (1 - overlapFraction));   % 225
canvasW = 2 * step + tileSize + 20;
canvasH = tileSize + 20;
corruptionPx = 24;                                % the injected "period" error

% ---- ground truth: 3-scale noise + gradient + lines + circles ---------------
% Feature-smoke recipe: the lines/circles make a broken seam obvious by eye.
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

numLines = 16;
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
circleSpec = [160 250 100; 200 480 120; 120 620 70];   % [cy cx radius]
for circleIdx = 1:size(circleSpec, 1)
    distanceToCircle = abs(hypot(xx - circleSpec(circleIdx, 2), ...
                                 yy - circleSpec(circleIdx, 1)) - circleSpec(circleIdx, 3));
    circleMask = distanceToCircle < lineHalfWidth;
    img(circleMask) = img(circleMask) * (1 - lineOpacity) + lineOpacity;
end

groundTruth = uint8(255 * min(max(img, 0), 1));
imwrite(groundTruth, fullfile(outputFolder, 'groundTruth.tif'));

% ---- cut the 1x3 chain with small jitter -------------------------------------
rng(42, 'twister');
trueOrigins = zeros(3, 2);
tileFiles = cell(1, 3);
for tileIdx = 1:3
    originY = 1 + randi([0 8]);
    originX = 1 + (tileIdx - 1) * step + randi([-4 4]);
    originX = min(max(originX, 1), canvasW - tileSize + 1);
    trueOrigins(tileIdx, :) = [originY, originX];
    tileFiles{tileIdx} = fullfile(tilesFolder, sprintf('tile_%02d.tif', tileIdx));
    imwrite(groundTruth(originY:originY + tileSize - 1, originX:originX + tileSize - 1), ...
        tileFiles{tileIdx});
end
save(fullfile(outputFolder, 'trueOrigins.mat'), 'trueOrigins');

% ---- measure honestly, then corrupt the 2-3 edge ------------------------------
layout = utils.stitch.buildLayoutGrid(tileFiles, struct('rows', 1, 'cols', 3, ...
    'tileOrder', 'Horizontal', 'overlapX', 100 * overlapFraction, 'overlapY', 100 * overlapFraction));
pairs = utils.stitch.findNeighborPairs(layout, struct('minOverlapPx', 16));
edges = utils.stitch.measureAllPairs(layout, pairs, struct('qualityThreshold', 0.3));

edge23 = find([edges.i] == 2 & [edges.j] == 3, 1);
edges(edge23).measured = edges(edge23).measured + [0, corruptionPx, 0];
edges(edge23).quality  = 0.95;   % confidently wrong
edges(edge23).valid    = true;

positions = utils.stitch.solveGlobalLeastSquares(layout, edges);

projectPath = fullfile(outputFolder, 'sabotage.mibstitch.json');
utils.stitch.saveProject(projectPath, layout, edges, positions, ...
    struct('note', 'edge 2-3 corrupted by +24 px at quality 0.95 (see generator)'), ...
    struct('outputMode', 'In memory', 'blendMode', 'Feather'));

fprintf(['Generated the 1x3 sabotage chain (edge 2-3 corrupted by +%d px, quality 0.95).\n' ...
    'Load in MIB: Stitch -> Load project -> %s\n'], corruptionPx, projectPath);
end
