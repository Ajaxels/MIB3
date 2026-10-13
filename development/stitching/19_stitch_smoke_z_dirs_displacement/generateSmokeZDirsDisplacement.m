function generateSmokeZDirsDisplacement()
% GENERATESMOKEZDIRSDISPLACEMENT - Folder Z-stacks of serial sections with stage-backlash jitter.
%
% A 2x2 grid of tiles, each a FOLDER holding the whole series of sections
% imaged at that stage position, all named with the MIB2 chop pattern as one
% Z-layer: ``stack_Z01-X##-Y##``. This is the natural layout of a serial-section
% montage (SBEM, array tomography): the stage visits the same four positions on
% every section, and every folder spans the full depth.
%
% Unlike 05_stitch_smoke_pattern_folders, the slices inside a folder are NOT
% registered to each other. The stage returns to each position on every
% section, and backlash makes the imaged area land slightly off each time:
%
%   - per tile, a fixed offset of up to +-4 px from the nominal grid (the usual
%     tile jitter, the same on every slice);
%   - per tile AND per slice, a backlash offset of +-backlashPx/2 on each axis,
%     its sign depending on which side the stage approached from (random per
%     slice and axis), plus +-repeatabilityPx of repeatability noise. With the
%     defaults that is 1-3 px per axis, independent from slice to slice (no
%     accumulation - the stage targets the same coordinates every time).
%
% The stitcher places each folder RIGIDLY (one origin per tile), so it can only
% find each tile's average position; the per-slice backlash survives as seams
% that are off by a few px, differently on every slice.
%
% Ground truth is one volume with three components:
%   - a z-CONSTANT 2D texture, so the depth mean-projection (what the in-plane
%     seams are measured on) keeps structure despite the per-slice jitter;
%   - a z-VARYING 3D texture (correlation length ~1-2 slices): every section is
%     a different physical slice;
%   - lines and circles that MOVE with z (tilted planes and cones), so a seam
%     that breaks on some slices and not others is visible when scrolling.
%
% Outputs (in <repoRoot>\temp\stitching_test\19_stitch_smoke_z_dirs_displacement):
%   stack_Z01-X01-Y01 .. stack_Z01-X02-Y02 - four folders of slice_###.tif
%   trueOrigins3D.mat - trueOrigins [4x3 y x z, 1-based, in the volume; the
%                       tile's window before the per-slice backlash],
%                       sliceOffsets [4 x tileD x 2 dy dx] - slice s of tile k
%                       was cut at trueOrigins(k,1:2) + sliceOffsets(k,s,:)
%                       from volume slice s, tileNames {4x1}
%
% Load in MIB (smoke_tests.md test 19):
%   Stitch ribbon -> Layout source = "Filename pattern", tick "Tiles are folders
%   (Z-stacks)" -> Overlap X/Y = 22 (or tick "Estimate overlap") -> Browse
%   (multi-select the four stack_Z01-X##-Y## folders, or pick the parent)
%   -> Measure overlaps -> Optimize positions -> Stitch. Output "In memory".
%   Expect the average placement to be found, and seams that still break by
%   1-6 px on individual slices. See README.md for the measured numbers.

% Generator lives in development\stitching\19_stitch_smoke_z_dirs_displacement;
% output goes to the project temp folder so test data never lands in the
% tracked tree.
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
outputFolder = fullfile(repoRoot, 'temp', 'stitching_test', '19_stitch_smoke_z_dirs_displacement');
if ~isfolder(outputFolder); mkdir(outputFolder); end

tileH = 240; tileW = 240; tileD = 24;
overlapFraction = 0.22;
xyJitter = 4;              % per tile, fixed for all slices, px
backlashPx = 4;            % full backlash; each slice lands at +-backlashPx/2
repeatabilityPx = 1;       % per-slice repeatability noise, px
stepY = round(tileH * (1 - overlapFraction));
stepX = round(tileW * (1 - overlapFraction));

% Margin keeps every jittered window inside the volume, so no origin is clamped
% (a clamped origin would silently cancel part of the intended displacement).
margin = xyJitter + backlashPx / 2 + repeatabilityPx + 2;
volumeH = 2 * margin + stepY + tileH;
volumeW = 2 * margin + stepX + tileW;
volumeD = tileD;

% ---- z-constant 2D texture (3 scales, as in the 2D smoke recipe) ---------
rng(7, 'twister');
pixelNoise    = randn(volumeH, volumeW);
fineTexture   = imfilter(randn(volumeH, volumeW), fspecial('gaussian', [7 7], 1.2), 'replicate');
coarseTexture = imfilter(randn(volumeH, volumeW), fspecial('gaussian', [21 21], 4.0), 'replicate');
constantTexture = 0.25 * pixelNoise / std(pixelNoise(:)) + ...
                  0.35 * fineTexture / std(fineTexture(:)) + ...
                  0.40 * coarseTexture / std(coarseTexture(:));
constantTexture = constantTexture / std(constantTexture(:));

% ---- z-varying 3D texture -------------------------------------------------
varyingTexture = imgaussfilt3(randn(volumeH, volumeW, volumeD), [1.5 1.5 1.0]);
varyingTexture = varyingTexture / std(varyingTexture(:));

volumeFloat = 0.45 * constantTexture + 0.55 * varyingTexture;   % implicit expansion over z
volumeFloat = rescale(volumeFloat);
[xx, yy] = meshgrid(1:volumeW, 1:volumeH);
volumeFloat = 0.60 * volumeFloat + 0.12 * (xx / volumeW) + 0.08 * (yy / volumeH) + 0.10;

% ---- lines and circles that move with z ----------------------------------
% A line is the plane x*cos(theta) + y*sin(theta) = rho0 + lineSlope*z, a circle
% the cone of radius radius0 + circleSlope*z.
numLines = 16;
featureHalfWidth = 1.3;
featureOpacity = 0.45;
lineTheta = rand(1, numLines) * pi;
lineRho   = rand(1, numLines) * hypot(volumeH, volumeW) * 0.9;
lineSlope = (1 + rand(1, numLines)) .* sign(randn(1, numLines));
circleSpec = [130 150 80; 300 290 100; 190 380 60; 350 100 55];   % [cy cx radius at mid-depth]
circleSlope = [1.2 -1.5 1.0 -1.2];
midSlice = (volumeD + 1) / 2;

volume = zeros(volumeH, volumeW, volumeD, 'uint8');
for z = 1:volumeD
    slice = volumeFloat(:, :, z);
    for lineIdx = 1:numLines
        rho = lineRho(lineIdx) + lineSlope(lineIdx) * (z - midSlice);
        lineMask = abs(xx * cos(lineTheta(lineIdx)) + yy * sin(lineTheta(lineIdx)) - rho) < featureHalfWidth;
        if mod(lineIdx, 2) == 0
            slice(lineMask) = slice(lineMask) * (1 - featureOpacity) + featureOpacity;
        else
            slice(lineMask) = slice(lineMask) * (1 - featureOpacity);
        end
    end
    for circleIdx = 1:size(circleSpec, 1)
        radius = circleSpec(circleIdx, 3) + circleSlope(circleIdx) * (z - midSlice);
        circleMask = abs(hypot(xx - circleSpec(circleIdx, 2), yy - circleSpec(circleIdx, 1)) - radius) < featureHalfWidth;
        slice(circleMask) = slice(circleMask) * (1 - featureOpacity) + featureOpacity;
    end
    volume(:, :, z) = uint8(255 * max(min(slice, 1), 0));
end

% ---- cut the folder tiles, every slice through its own backlash window ----
rng(23, 'twister');
numTiles = 4;
trueOrigins = zeros(numTiles, 3);
sliceOffsets = zeros(numTiles, tileD, 2);
tileNames = cell(numTiles, 1);
tileIdx = 0;
for xIdx = 1:2
    for yIdx = 1:2
        tileIdx = tileIdx + 1;
        originY = margin + 1 + (yIdx - 1) * stepY + randi([-xyJitter xyJitter]);
        originX = margin + 1 + (xIdx - 1) * stepX + randi([-xyJitter xyJitter]);
        trueOrigins(tileIdx, :) = [originY, originX, 1];

        approachSign = 2 * randi([0 1], tileD, 2) - 1;   % which side the stage came from
        sliceOffsets(tileIdx, :, :) = reshape(approachSign * (backlashPx / 2) + ...
            randi([-repeatabilityPx repeatabilityPx], tileD, 2), 1, tileD, 2);

        tileNames{tileIdx} = sprintf('stack_Z01-X%02d-Y%02d', xIdx, yIdx);
        tileFolder = fullfile(outputFolder, tileNames{tileIdx});
        if ~isfolder(tileFolder); mkdir(tileFolder); end
        for sliceIdx = 1:tileD
            sliceY = originY + sliceOffsets(tileIdx, sliceIdx, 1);
            sliceX = originX + sliceOffsets(tileIdx, sliceIdx, 2);
            imwrite(volume(sliceY:sliceY + tileH - 1, sliceX:sliceX + tileW - 1, sliceIdx), ...
                fullfile(tileFolder, sprintf('slice_%03d.tif', sliceIdx)));
        end
    end
end

save(fullfile(outputFolder, 'trueOrigins3D.mat'), 'trueOrigins', 'sliceOffsets', 'tileNames');

fprintf('Generated %d pattern-named folder tiles (%dx%dx%d each, ~%d%% XY overlap) in %s\n', ...
    numTiles, tileH, tileW, tileD, round(overlapFraction * 100), outputFolder);
fprintf('Per-slice backlash jitter: %d..%d px per axis (backlash %d px, repeatability +-%d px)\n', ...
    min(abs(sliceOffsets(:))), max(abs(sliceOffsets(:))), backlashPx, repeatabilityPx);
end
