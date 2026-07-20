function generateSmokeBioFormatsTiles()
% GENERATESMOKEBIOFORMATSTILES - OME-TIFF tiles with stage coordinates in metadata.
%
% Creates a 2x2 set of single-plane OME-TIFF tiles whose OME metadata carries
% stage coordinates (Plane PositionX/PositionY in micrometers) + the physical
% pixel size — the fields the "Bio-Formats metadata" layout source reads via
% ``utils.stitch.buildLayoutBioFormats``. The metadata carries the CLEAN nominal
% grid while the tiles are cut at JITTERED positions, so Measure + Optimize have
% real work to do; embedded lines/circles expose any seam misplacement.
%
% Requires the Bio-Formats Java library (bundled in mib\external\bioformats);
% the function adds it to the path automatically when missing.
%
% Outputs (in <repoRoot>\temp\stitch_smoke_bioformats):
%   tile_01..04.ome.tiff   - OME-TIFF tiles with stage coordinates
%   trueOrigins.mat        - 4x2 [y x] true cut origins (1-based)
%
% Load in MIB:
%   Stitch ribbon -> Layout source = "Bio-Formats metadata"
%   -> Browse (multi-select tile_01..tile_04.ome.tiff)
%   -> Measure overlaps -> Optimize positions -> Stitch.

% Generator lives in development\stitching\stitch_smoke_bioformats; output goes
% to the project temp folder so test data never lands in the tracked tree.
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
outputFolder = fullfile(repoRoot, 'temp', 'stitch_smoke_bioformats');
if ~isfolder(outputFolder); mkdir(outputFolder); end

if ~exist('bfsave', 'file')
    addpath(fullfile(repoRoot, 'mib', 'external', 'bioformats'));
end
utils.ensureJavaLibraries({'bioformats'});

canvasH = 560; canvasW = 560;
tileSize = 240;
overlapFraction = 0.25;
xyJitter = 5;
pixSizeUm = 0.5;
step = round(tileSize * (1 - overlapFraction));   % 180

% ---- 2D ground-truth pattern: 3-scale noise + gradient + lines + circles ----
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
circleSpec = [150 180 100; 400 380 130; 260 480 80; 460 110 70];   % [cy cx radius]
for circleIdx = 1:size(circleSpec, 1)
    distanceToCircle = abs(hypot(xx - circleSpec(circleIdx, 2), ...
                                 yy - circleSpec(circleIdx, 1)) - circleSpec(circleIdx, 3));
    circleMask = distanceToCircle < lineHalfWidth;
    img(circleMask) = img(circleMask) * (1 - lineOpacity) + lineOpacity;
end
groundTruth = uint8(255 * max(min(img, 1), 0));

% ---- cut 2x2 jittered tiles; metadata carries the CLEAN nominal grid --------
clampOrigin = @(o) min(max(o, 1), canvasH - tileSize + 1);
rowCol = [1 1; 1 2; 2 1; 2 2];
rng(23, 'twister');
trueOrigins = zeros(4, 2);
for k = 1:4
    r = rowCol(k, 1); c = rowCol(k, 2);
    oy = clampOrigin(1 + (r - 1) * step + randi([-xyJitter xyJitter]));
    ox = clampOrigin(1 + (c - 1) * step + randi([-xyJitter xyJitter]));
    trueOrigins(k, :) = [oy, ox];
    tile = groundTruth(oy:oy + tileSize - 1, ox:ox + tileSize - 1);

    % Nominal (clean-grid) stage position in micrometers, 0-based.
    nomXUm = (c - 1) * step * pixSizeUm;
    nomYUm = (r - 1) * step * pixSizeUm;

    filePath = fullfile(outputFolder, sprintf('tile_%02d.ome.tiff', k));
    if isfile(filePath); delete(filePath); end   % bfsave appends to existing files
    meta = createMinimalOMEXMLMetadata(tile);
    meta.setPlanePositionX(ome.units.quantity.Length(java.lang.Double(nomXUm), ome.units.UNITS.MICROMETER), 0, 0);
    meta.setPlanePositionY(ome.units.quantity.Length(java.lang.Double(nomYUm), ome.units.UNITS.MICROMETER), 0, 0);
    meta.setPixelsPhysicalSizeX(ome.units.quantity.Length(java.lang.Double(pixSizeUm), ome.units.UNITS.MICROMETER), 0);
    meta.setPixelsPhysicalSizeY(ome.units.quantity.Length(java.lang.Double(pixSizeUm), ome.units.UNITS.MICROMETER), 0);
    bfsave(tile, filePath, 'metadata', meta);
end

save(fullfile(outputFolder, 'trueOrigins.mat'), 'trueOrigins');
fprintf('Generated 4 OME-TIFF tiles (%dx%d, step %d px = %.1f um, jitter +-%d px) in %s\n', ...
    tileSize, tileSize, step, step * pixSizeUm, xyJitter, outputFolder);
end
