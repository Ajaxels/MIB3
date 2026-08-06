function generateSmokeAffine3DTiles()
% GENERATESMOKEAFFINE3DTILES - Rotated/scaled Z-STACK tile set for 3D affine stitching.
%
% The 3D analogue of generateSmokeAffineTiles: a 2x2 XY grid over 2 Z-layers
% (8 Z-stack tiles, multi-page TIFFs) cut from a textured volume whose slices
% share a strong in-plane texture. Every tile except the first is cut with its
% OWN small IN-PLANE affine warp - +-1 degree rotation, +-1% scale, +-8 px XY
% jitter - applied identically to every slice of the tile (the 3D-affine scope:
% 2D in-plane model on depth>1 data, z stays translational). The layer Z
% positions are jittered by +-2 slices against the nominal grid in the position
% file, so the solve has to recover rotation/scale in-plane AND dz across layers.
%
% Outputs (in <repoRoot>\temp\stitching_test\13_stitch_smoke_affine3d):
%   tiles\tile_01..08.tif  - multi-page TIFF Z-stack tiles (warped)
%   positions.txt          - nominal grid position file (filename X Y Z, 0-based)
%   truth.mat              - trueTforms {8x1} tile-local -> volume 3x3 xy maps,
%                            trueLayerZ [1x2] true layer start slices (1-based)
%
% Load in MIB (smoke_tests.md test 13; run TWICE to compare):
%   Stitch ribbon -> Layout source = "Position file"
%   -> Browse to temp\stitching_test\13_stitch_smoke_affine3d\positions.txt
%   A) Transform type = "Translation" -> Measure -> Optimize -> Stitch
%      (scroll Z: seams show rotated/doubled lines on every slice)
%   B) Transform type = "Affine", tick "Allow rotation" -> Measure overlaps
%      (switches to feature-based automatically) -> Optimize positions -> Stitch
%      (lines/circles continuous across every seam on EVERY slice; planes
%      continuous across the layer boundary)

% Generator lives in development\stitching\13_stitch_smoke_affine3d; output goes to
% the project temp folder so test data never lands in the tracked tree. The
% output folder is prefixed with its smoke_tests.md test number.
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
outputFolder = fullfile(repoRoot, 'temp', 'stitching_test', '13_stitch_smoke_affine3d');
tilesFolder  = fullfile(outputFolder, 'tiles');
if ~isfolder(tilesFolder); mkdir(tilesFolder); end

canvasH = 640; canvasW = 640; canvasD = 30;
tileSize = 300;
tileDepth = 16;
overlapFraction = 0.25;
step = round(tileSize * (1 - overlapFraction));   % 225
stepZ = 10;                                       % 6 slices of Z overlap
maxRotationDeg = 1.0;
maxScaleFraction = 0.01;
jitterPx = 8;
zJitterSlices = 2;

% ---- in-plane texture: 3-scale noise + gradient + lines + circles ----------
% Same recipe as stitch_smoke_affine - SURF-friendly blobs and line/circle
% crossings. This 2D base is shared by all slices so the depth-flattened
% projections the measurer matches keep the full feature content.
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
base = 0.60 * background + 0.12 * (xx / canvasW) + 0.08 * (yy / canvasH) + 0.10;

numLines = 18;
lineHalfWidth = 1.3;
lineOpacity = 0.45;
for lineIdx = 1:numLines
    theta = rand() * pi;
    rho   = rand() * hypot(canvasH, canvasW) * 0.9;
    distanceToLine = abs(xx * cos(theta) + yy * sin(theta) - rho);
    lineMask = distanceToLine < lineHalfWidth;
    if mod(lineIdx, 2) == 0
        base(lineMask) = base(lineMask) * (1 - lineOpacity) + lineOpacity;
    else
        base(lineMask) = base(lineMask) * (1 - lineOpacity);
    end
end
circleSpec = [180 220 110; 460 420 130; 320 540 80];   % [cy cx radius]
for circleIdx = 1:size(circleSpec, 1)
    distanceToCircle = abs(hypot(xx - circleSpec(circleIdx, 2), ...
                                 yy - circleSpec(circleIdx, 1)) - circleSpec(circleIdx, 3));
    circleMask = distanceToCircle < lineHalfWidth;
    base(circleMask) = base(circleMask) * (1 - lineOpacity) + lineOpacity;
end

% ---- extend into a volume: shared base + z-varying noise + tilted planes ---
% The z-varying component makes the dz NCC scan peak sharply at the true offset
% (a purely static volume scores every dz alike); the tilted planes are the
% at-a-glance visual cue for a Z misalignment when scrolling the fused stack.
rng(11, 'twister');
zNoise = imgaussfilt3(randn(canvasH, canvasW, canvasD), 2.0);
zNoise = zNoise / std(zNoise(:));
volume = 0.65 * repmat(base, 1, 1, canvasD) + 0.35 * rescale(zNoise);
[xx3, yy3, zz3] = meshgrid(1:canvasW, 1:canvasH, 1:canvasD);
rng(3, 'twister');
for planeIdx = 1:4
    normalVec = randn(1, 3); normalVec = normalVec / norm(normalVec);
    offset = rand() * (canvasH + canvasW) * 0.5;
    distance = abs(normalVec(1) * yy3 + normalVec(2) * xx3 + normalVec(3) * zz3 * 6 - offset);
    planeMask = distance < 1.5;
    if mod(planeIdx, 2) == 0
        volume(planeMask) = min(volume(planeMask) + 0.5, 1);
    else
        volume(planeMask) = max(volume(planeMask) - 0.5, 0);
    end
end
volume = uint8(255 * max(min(volume, 1), 0));

% ---- cut warped Z-stack tiles + build the nominal position file ------------
% trueTforms{t} maps tile-local 1-based xy pixel coordinates to volume xy; the
% tile slice is produced by the inverse warp tile(v) = volume(G*v) - the SAME
% 2D map on every slice of the tile (z composes additively, per the 3D scope).
% The linear part is shared per grid SLOT across the two layers (lens/stage
% distortion is per-position, not per-section - and the solver's translation-
% only cross-layer edges assume exactly that); only the XY translation jitters
% independently per tile.
rng(42, 'twister');
clampZ = @(oz) min(max(oz, 1), canvasD - tileDepth + 1);
trueLayerZ = arrayfun(@(zl) clampZ(1 + (zl - 1) * stepZ + randi([-zJitterSlices zJitterSlices])), 1:2);

slotLinearPart = cell(4, 1);
slotLinearPart{1} = eye(2);
for gridSlot = 2:4
    angleRad = deg2rad((rand() - 0.5) * 2 * maxRotationDeg);
    scale = 1 + (rand() - 0.5) * 2 * maxScaleFraction;
    slotLinearPart{gridSlot} = scale * [cos(angleRad), -sin(angleRad); sin(angleRad), cos(angleRad)];
end

trueTforms = cell(8, 1);
positionLines = {};
tileIdx = 0;
for zLayer = 1:2
    for row = 1:2
        for col = 1:2
            tileIdx = tileIdx + 1;
            gridSlot = (row - 1) * 2 + col;
            nominalXY = [1 + (col - 1) * step; 1 + (row - 1) * step];
            if tileIdx == 1
                % anchor tile: identity at nominal, matching the solver's gauge
                translation = nominalXY - 1;
            else
                translation = nominalXY - 1 + (rand(2, 1) - 0.5) * 2 * jitterPx;
            end
            trueTform = [slotLinearPart{gridSlot}, translation; 0 0 1];
            trueTforms{tileIdx} = trueTform;

            oz = trueLayerZ(zLayer);
            tileName = sprintf('tile_%02d.tif', tileIdx);
            tilePath = fullfile(tilesFolder, tileName);
            for sliceIdx = 1:tileDepth
                tileSlice = imwarp(volume(:, :, oz + sliceIdx - 1), ...
                    affinetform2d(inv(trueTform)), 'linear', ...
                    'OutputView', imref2d([tileSize tileSize]), 'FillValues', 0);
                if sliceIdx == 1
                    imwrite(tileSlice, tilePath);
                else
                    imwrite(tileSlice, tilePath, 'WriteMode', 'append');
                end
            end

            % Position file carries the CLEAN nominal grid (0-based), relative
            % path so the folder can be moved. X = column, Y = row, Z = slice.
            positionLines{end+1} = sprintf('tiles/%s %d %d %d', tileName, ...
                (col - 1) * step, (row - 1) * step, (zLayer - 1) * stepZ); %#ok<AGROW>
        end
    end
end

positionFilePath = fullfile(outputFolder, 'positions.txt');
fileId = fopen(positionFilePath, 'w');
fprintf(fileId, '# filename X Y Z  (0-based nominal grid; true tiles are affine-warped in-plane + Z-jittered)\n');
fprintf(fileId, '%s\n', positionLines{:});
fclose(fileId);

save(fullfile(outputFolder, 'truth.mat'), 'trueTforms', 'trueLayerZ');
fprintf(['Generated 8 affine-warped Z-stack tiles (%dx%dx%d, step %d/%d, rot +-%.1f deg, ' ...
    'scale +-%.0f%%, jitter +-%d px, z jitter +-%d) + %s\n'], ...
    tileSize, tileSize, tileDepth, step, stepZ, maxRotationDeg, ...
    maxScaleFraction * 100, jitterPx, zJitterSlices, positionFilePath);
end
