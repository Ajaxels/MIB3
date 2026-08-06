function generateSmokeBioFormatsTiles()
% GENERATESMOKEBIOFORMATSTILES - OME-TIFF tiles with stage coordinates in metadata.
%
% Creates a 2x2 set of single-plane OME-TIFF tiles whose OME metadata carries
% stage coordinates (Plane PositionX/PositionY in micrometers) + the physical
% pixel size - the fields the "Bio-Formats metadata" layout source reads via
% ``utils.stitch.buildLayoutBioFormats``.
%
% The tiles are cut on a PERFECT grid, and the stage coordinates written into the
% metadata are that grid plus a small random JITTER - real stages never land
% exactly where they were told (backlash, drift, encoder error). So the mosaic
% built straight from the metadata already looks good but shows sub-tile seam
% offsets, and only Measure overlaps + Optimize positions recovers the exact
% grid; embedded lines/circles make the residual misplacement visible at seams.
%
% Requires the Bio-Formats Java library (bundled in mib\external\bioformats);
% the function adds it to the path automatically when missing.
%
% Outputs (in <repoRoot>\temp\stitching_test\07_stitch_smoke_bioformats):
%   tile_01..04.ome.tiff   - OME-TIFF tiles with jittered stage coordinates
%   trueOrigins.mat        - trueOrigins  4x2 [y x] true cut origins (1-based,
%                                         the perfect grid Optimize must recover)
%                            stageJitterPx 4x2 [y x] jitter baked into the
%                                         metadata, in pixels (signed)
%
% Load in MIB (smoke_tests.md test 7):
%   Stitch ribbon -> Layout source = "Bio-Formats metadata"
%   -> Browse (multi-select tile_01..tile_04.ome.tiff)
%   -> Measure overlaps -> Optimize positions -> Stitch.

% Generator lives in development\stitching\07_stitch_smoke_bioformats; output goes
% to the project temp folder so test data never lands in the tracked tree. The
% output folder is prefixed with its smoke_tests.md test number.
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
outputFolder = fullfile(repoRoot, 'temp', 'stitching_test', '07_stitch_smoke_bioformats');
if ~isfolder(outputFolder); mkdir(outputFolder); end

if ~exist('bfsave', 'file')
    addpath(fullfile(repoRoot, 'mib', 'external', 'bioformats'));
end
utils.ensureJavaLibraries({'bioformats'});

canvasH = 560; canvasW = 560;
tileSize = 240;
overlapFraction = 0.25;
stageJitterPxMax = 10;      % worst-case stage error, in pixels (sub-pixel values included)
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

% ---- cut 2x2 tiles on the PERFECT grid; metadata carries JITTERED coordinates
% Ground truth = the clean grid, so a successful Optimize reproduces the source
% image exactly. The stage coordinates are that grid plus a per-tile, per-axis
% error of up to +-stageJitterPxMax pixels - the mechanical reality the layout
% source has to swallow. The error is continuous (not whole pixels): a stage
% does not snap to the camera's pixel raster.
rowCol = [1 1; 1 2; 2 1; 2 2];
rng(23, 'twister');
trueOrigins = zeros(4, 2);
stageJitterPx = zeros(4, 2);
for k = 1:4
    r = rowCol(k, 1); c = rowCol(k, 2);
    oy = 1 + (r - 1) * step;
    ox = 1 + (c - 1) * step;
    trueOrigins(k, :) = [oy, ox];
    tile = groundTruth(oy:oy + tileSize - 1, ox:ox + tileSize - 1);

    % Reported (jittered) stage position in micrometers, 0-based.
    jitterYPx = (2 * rand() - 1) * stageJitterPxMax;
    jitterXPx = (2 * rand() - 1) * stageJitterPxMax;
    stageJitterPx(k, :) = [jitterYPx, jitterXPx];
    stageXUm = ((c - 1) * step + jitterXPx) * pixSizeUm;
    stageYUm = ((r - 1) * step + jitterYPx) * pixSizeUm;

    filePath = fullfile(outputFolder, sprintf('tile_%02d.ome.tiff', k));
    if isfile(filePath); delete(filePath); end   % bfsave appends to existing files
    meta = createMinimalOMEXMLMetadata(tile);
    meta.setPlanePositionX(ome.units.quantity.Length(java.lang.Double(stageXUm), ome.units.UNITS.MICROMETER), 0, 0);
    meta.setPlanePositionY(ome.units.quantity.Length(java.lang.Double(stageYUm), ome.units.UNITS.MICROMETER), 0, 0);
    meta.setPixelsPhysicalSizeX(ome.units.quantity.Length(java.lang.Double(pixSizeUm), ome.units.UNITS.MICROMETER), 0);
    meta.setPixelsPhysicalSizeY(ome.units.quantity.Length(java.lang.Double(pixSizeUm), ome.units.UNITS.MICROMETER), 0);
    bfsave(tile, filePath, 'metadata', meta);
end

save(fullfile(outputFolder, 'trueOrigins.mat'), 'trueOrigins', 'stageJitterPx');
fprintf(['Generated 4 OME-TIFF tiles (%dx%d, step %d px = %.1f um) in %s\n' ...
         'Stage coordinates jittered by up to +-%d px; worst axis error %.2f px ' ...
         '(%.2f um) - Optimize positions must remove it.\n'], ...
    tileSize, tileSize, step, step * pixSizeUm, outputFolder, ...
    stageJitterPxMax, max(abs(stageJitterPx(:))), max(abs(stageJitterPx(:))) * pixSizeUm);
end
