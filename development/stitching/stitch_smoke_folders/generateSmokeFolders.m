function generateSmokeFolders()
% GENERATESMOKEFOLDERS - Create a folder-per-tile 3D stitching smoke example.
%
% Each tile is a Z-stack stored as a FOLDER of single-slice images. Tiles are
% arranged in a 2x2 XY grid (each tile propagates through the full Z range) and
% cut from a textured 3D volume at jittered XY positions. This exercises the
% "Tiles are folders (Z-stacks)" modifier with the Grid layout source.
%
% Outputs (in <repoRoot>\temp\stitch_smoke_folders):
%   tile_r1c1 .. tile_r2c2   - four folders of slice_###.tif images
%
% Load in MIB:
%   Stitch ribbon -> Layout source = "Grid", check "Tiles are folders (Z-stacks)"
%   -> Browse (multi-select tile_r1c1 ... tile_r2c2, or pick the parent folder)
%   -> Rows 2, Cols 2 -> Measure overlaps -> Optimize positions -> Stitch.

% Generator lives in development\stitching\stitch_smoke_folders; output goes to
% the project temp folder so test data never lands in the tracked docs tree.
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
outputFolder = fullfile(repoRoot, 'temp', 'stitch_smoke_folders');
if ~isfolder(outputFolder); mkdir(outputFolder); end

volumeH = 300; volumeW = 300; volumeD = 40;
tileH = 190; tileW = 190;
xyOverlapPx = 60;
xyJitter = 4;
stepY = tileH - xyOverlapPx;   % 130
stepX = tileW - xyOverlapPx;   % 130

% ---- textured 3D volume + tilted planes (broken planes reveal bad seams) --
rng(51, 'twister');
volume = imgaussfilt3(randn(volumeH, volumeW, volumeD), 2.0);
volume = volume + 0.5 * imgaussfilt3(randn(volumeH, volumeW, volumeD), 5.0);
volume = rescale(volume);
[xx, yy, zz] = meshgrid(1:volumeW, 1:volumeH, 1:volumeD);
rng(9, 'twister');
for planeIdx = 1:6
    normalVec = randn(1, 3); normalVec = normalVec / norm(normalVec);
    offset = rand() * (volumeH + volumeW) * 0.5;
    distance = abs(normalVec(1) * yy + normalVec(2) * xx + normalVec(3) * zz * 4 - offset);
    mask = distance < 1.5;
    volume(mask) = (mod(planeIdx, 2) == 0) * min(volume(mask) + 0.5, 1) + ...
                   (mod(planeIdx, 2) == 1) * max(volume(mask) - 0.5, 0);
end
volume = uint8(230 * volume + 15);

% ---- cut 2x2 folder tiles -------------------------------------------------
clampOrigin = @(o, tileSize, volSize) min(max(o, 1), volSize - tileSize + 1);
rng(23, 'twister');
gridNames = {'tile_r1c1', 'tile_r1c2', 'tile_r2c1', 'tile_r2c2'};
rowCol = [1 1; 1 2; 2 1; 2 2];
for k = 1:4
    r = rowCol(k, 1); c = rowCol(k, 2);
    oy = clampOrigin(1 + (r - 1) * stepY + randi([-xyJitter xyJitter]), tileH, volumeH);
    ox = clampOrigin(1 + (c - 1) * stepX + randi([-xyJitter xyJitter]), tileW, volumeW);
    tileVolume = volume(oy:oy + tileH - 1, ox:ox + tileW - 1, :);

    tileFolder = fullfile(outputFolder, gridNames{k});
    if ~isfolder(tileFolder); mkdir(tileFolder); end
    for z = 1:volumeD
        imwrite(tileVolume(:, :, z), fullfile(tileFolder, sprintf('slice_%03d.tif', z)));
    end
end

fprintf('Generated 4 folder tiles (%dx%dx%d each) in %s\n', tileH, tileW, volumeD, outputFolder);
fprintf('Folders: %s\n', strjoin(gridNames, ', '));
end
