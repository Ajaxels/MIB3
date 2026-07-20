function generateSmokeTiles3D()
% GENERATESMOKETILES3D - Create a 3D multi-layer tile set for stitching smoke tests.
%
% Cuts a textured 3D volume into a 2x2 XY grid over 3 Z-layers (12 Z-stack tiles,
% each a multi-page TIFF) at JITTERED 3D positions, and writes a position file
% carrying the CLEAN nominal grid — so the tool has to recover the jitter in all
% three axes. Embedded lines/planes make misplacement visible at every seam.
%
% Outputs (in <repoRoot>\temp\stitch_smoke_3d):
%   tiles\tile_01..12.tif  - multi-page TIFF Z-stack tiles
%   positions.txt          - nominal grid position file (filename X Y Z, 0-based)
%   trueOrigins3D.mat      - 12x3 [y x z] true cut origins (1-based)
%
% Load in MIB:
%   Stitch ribbon button -> Layout source = "Position file"
%   -> Browse to temp\stitch_smoke_3d\positions.txt -> Measure overlaps ->
%   Optimize positions -> Stitch. Output "In memory" gives a 3D dataset you can
%   scroll through; broken lines across a seam mean a bad stitch.

% Generator lives in development\stitching\stitch_smoke_3d; output goes to the
% project temp folder so test data never lands in the tracked docs tree.
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
outputFolder = fullfile(repoRoot, 'temp', 'stitch_smoke_3d');
tilesFolder  = fullfile(outputFolder, 'tiles');
if ~isfolder(tilesFolder); mkdir(tilesFolder); end

volumeH = 320; volumeW = 320; volumeD = 70;
tileH = 190; tileW = 190; tileD = 32;
xyOverlapPx = 60;
zOverlapSlices = 12;
xyJitter = 4;

stepY = tileH - xyOverlapPx;          % 130
stepX = tileW - xyOverlapPx;          % 130
stepZ = tileD - zOverlapSlices;       % 20

% ---- textured 3D volume: 3-scale noise + planar structures --------------
rng(77, 'twister');
volume = imgaussfilt3(randn(volumeH, volumeW, volumeD), 2.0);
volume = volume + 0.5 * imgaussfilt3(randn(volumeH, volumeW, volumeD), 5.0);
volume = rescale(volume);

% Embedded tilted planes (the 3D analogue of the 2D lines): a plane broken at a
% seam is the clearest visual cue that a tile is misplaced in Z or XY.
[xx, yy, zz] = meshgrid(1:volumeW, 1:volumeH, 1:volumeD);
rng(3, 'twister');
for planeIdx = 1:6
    normalVec = randn(1, 3); normalVec = normalVec / norm(normalVec);
    offset = rand() * (volumeH + volumeW) * 0.5;
    distance = abs(normalVec(1) * yy + normalVec(2) * xx + normalVec(3) * zz * 4 - offset);
    planeMask = distance < 1.5;
    if mod(planeIdx, 2) == 0
        volume(planeMask) = min(volume(planeMask) + 0.5, 1);
    else
        volume(planeMask) = max(volume(planeMask) - 0.5, 0);
    end
end
volume = uint8(230 * volume + 15);

% ---- cut jittered tiles + build the nominal position file ---------------
clampOrigin = @(origin, tileSize, volSize) min(max(origin, 1), volSize - tileSize + 1);
rng(23, 'twister');
% Per-layer Z (one focal plane per layer — within-layer tiles share z).
layerOz = arrayfun(@(zl) clampOrigin(1 + (zl - 1) * stepZ + randi([-2 2]), tileD, volumeD), 1:3);

positionLines = {};
trueOrigins = zeros(12, 3);
k = 0;
for zl = 1:3
    for r = 1:2
        for c = 1:2
            k = k + 1;
            oy = clampOrigin(1 + (r - 1) * stepY + randi([-xyJitter xyJitter]), tileH, volumeH);
            ox = clampOrigin(1 + (c - 1) * stepX + randi([-xyJitter xyJitter]), tileW, volumeW);
            oz = layerOz(zl);
            trueOrigins(k, :) = [oy, ox, oz];

            tileVolume = volume(oy:oy + tileH - 1, ox:ox + tileW - 1, oz:oz + tileD - 1);
            tileName = sprintf('tile_%02d.tif', k);
            tilePath = fullfile(tilesFolder, tileName);
            imwrite(tileVolume(:, :, 1), tilePath);
            for z = 2:tileD
                imwrite(tileVolume(:, :, z), tilePath, 'WriteMode', 'append');
            end

            % Position file carries the CLEAN nominal grid (0-based), relative
            % path so the folder can be moved. X = column, Y = row, Z = slice.
            nomX = (c - 1) * stepX;
            nomY = (r - 1) * stepY;
            nomZ = (zl - 1) * stepZ;
            positionLines{end+1} = sprintf('tiles/%s %d %d %d', tileName, nomX, nomY, nomZ); %#ok<AGROW>
        end
    end
end

positionFilePath = fullfile(outputFolder, 'positions.txt');
fileId = fopen(positionFilePath, 'w');
fprintf(fileId, '# filename X Y Z  (0-based nominal grid; true tile positions are jittered)\n');
fprintf(fileId, '%s\n', positionLines{:});
fclose(fileId);

save(fullfile(outputFolder, 'trueOrigins3D.mat'), 'trueOrigins');
fprintf('Generated 12 Z-stack tiles (%dx%dx%d) + %s\n', tileH, tileW, tileD, positionFilePath);
fprintf('Nominal grid: stepY %d stepX %d stepZ %d (XY overlap %d px, Z overlap %d slices)\n', ...
    stepY, stepX, stepZ, xyOverlapPx, zOverlapSlices);
end
