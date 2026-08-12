function cropPlan = planLabelCrop(~, labelPyramid, imagePyramid, memoryLimitBytes)
% PLANLABELCROP - Work out how a label crop pairs with its parent image pyramid.
%
% Syntax:
%   .. code-block:: matlab
%
%      cropPlan = obj.planLabelCrop(labelPyramid, imagePyramid)
%      cropPlan = obj.planLabelCrop(labelPyramid, imagePyramid, memoryLimitBytes)
%
% Pure - takes two :meth:`readGroupPyramid` results and touches nothing else, so
% the pairing arithmetic can be asserted offline against embedded metadata. The
% one environment-dependent input, how much memory may be used, is an argument
% with a machine-derived default rather than a lookup inside.
%
% **What has to be decided.** A ground-truth crop is annotated at a finer scale
% than the volume it came from - the OpenOrganelle crops are 2 nm against 4 nm EM
% - so the two pyramids do not line up level for level. The image is opened at
% its finest level, and the label level that matches *that* scale is the one to
% read. For the COSEM crops that is label ``s1`` against image ``s0``.
%
% **The shapes are asserted, never forced.** A pyramid pair that shares no
% common scale is reported and refused; resampling one to fit the other would
% turn a metadata problem into silently wrong labels.
%
% Input Arguments:
%   - **labelPyramid** - [struct] from readGroupPyramid, the label group
%   - **imagePyramid** - [struct] from readGroupPyramid, the candidate image group
%   - **memoryLimitBytes** - *(optional)* [numeric] ceiling for the image region
%     plus its model. Default: 60% of what MATLAB reports it could still
%     allocate, or 8 GiB where the platform cannot say (``memory`` is
%     Windows-only). Pass a value to make the decision deterministic in a test
%
% Output Arguments:
%   - **cropPlan** - [struct] with fields:
%
%     - ``.ok`` - [logical] true when the pair can be opened
%     - ``.reason`` - [char] why not, when ``ok`` is false
%     - ``.cropOuterBoxUm`` - [1x6] the crop's outer extent in micrometres,
%       ready for ``BatchOpt.Region``
%     - ``.labelLevel`` / ``.imageLevel`` - [numeric] 1-based level indices
%     - ``.shapeYXZ`` - [1x3] agreed voxel counts
%     - ``.voxelSizeUm`` - [1x3] ``[x y z]`` voxel size of the chosen pair
%     - ``.requiredBytes`` - [numeric] what opening it costs in RAM, 0 until the
%       shapes are known

if nargin < 4 || isempty(memoryLimitBytes); memoryLimitBytes = defaultMemoryLimit(); end

cropPlan = struct('ok', false, 'reason', '', 'cropOuterBoxUm', [], ...
    'labelLevel', 1, 'imageLevel', 1, 'shapeYXZ', [0 0 0], 'voxelSizeUm', [0 0 0], ...
    'requiredBytes', 0);

if ~labelPyramid.ok
    cropPlan.reason = 'The selected group has no image pyramid to place.';
    return;
end
if isempty(imagePyramid) || ~imagePyramid.ok
    cropPlan.reason = ['No sibling image pyramid could be found for this crop, so there ' ...
        'is nothing to load it onto. Enter the image group path by hand to override.'];
    return;
end

labelToUm = io.loaders.OmeZarrMetadataUtils.unitToMicrometreFactor(labelPyramid.unit);
imageToUm = io.loaders.OmeZarrMetadataUtils.unitToMicrometreFactor(imagePyramid.unit);

% ---- the crop's true physical extent, in micrometres --------------------
% Edge-based, because that is the space in which two grids either line up or do
% not; see io.loaders.OmeZarrMetadataUtils.outerBoundingBox.
cropOuterBoxUm = io.loaders.OmeZarrMetadataUtils.outerBoundingBox( ...
    labelPyramid.levelWorldBoxes(1, :), labelPyramid.levelVoxelSizesXYZ(1, :)) * labelToUm;
cropPlan.cropOuterBoxUm = cropOuterBoxUm;

% ---- the image is opened at its finest level ---------------------------
imageLevel      = 1;
imageVoxelUm    = imagePyramid.levelVoxelSizesXYZ(imageLevel, :) * imageToUm;
labelVoxelSizes = labelPyramid.levelVoxelSizesXYZ * labelToUm;

% ---- the label level that matches that scale ---------------------------
scaleMismatch  = max(abs(labelVoxelSizes ./ imageVoxelUm - 1), [], 2);
[bestMismatch, labelLevel] = min(scaleMismatch);

% One part in a thousand: enough slack for the rounded decimals a store writes
% (5.24 against 2.62 x 2), nowhere near enough to accept a 2x level as a match.
if bestMismatch > 1e-3
    cropPlan.reason = sprintf(['The label and image pyramids share no common resolution ' ...
        '(closest is %g x %g x %g um against the image''s %g x %g x %g um). MIB will not ' ...
        'resample one to fit the other.'], ...
        labelVoxelSizes(labelLevel, 1), labelVoxelSizes(labelLevel, 2), labelVoxelSizes(labelLevel, 3), ...
        imageVoxelUm(1), imageVoxelUm(2), imageVoxelUm(3));
    return;
end

% ---- the image region the crop covers, on the image's own grid ---------
imageBoxInImageUnits   = imagePyramid.levelWorldBoxes(imageLevel, :);
imageVoxelInImageUnits = imagePyramid.levelVoxelSizesXYZ(imageLevel, :);
imageShapeYXZ          = imagePyramid.levelShapesYXZ(imageLevel, :);

voxelRange = io.loaders.OmeZarrMetadataUtils.regionToVoxelRange( ...
    cropOuterBoxUm / imageToUm, imageBoxInImageUnits, imageVoxelInImageUnits, ...
    imageShapeYXZ([2 1 3]));
imageCountXYZ = max(voxelRange(:, 2) - voxelRange(:, 1) + 1, 0)';

if any(imageCountXYZ == 0)
    cropPlan.reason = ['This crop lies outside the image pyramid found for it. Enter the ' ...
        'correct image group path by hand.'];
    return;
end

labelShapeYXZ = labelPyramid.levelShapesYXZ(labelLevel, :);
imageShapeCropYXZ = imageCountXYZ([2 1 3]);

if ~isequal(labelShapeYXZ, imageShapeCropYXZ)
    cropPlan.reason = sprintf(['The crop and the matching image region disagree on size: ' ...
        'labels %s are %d x %d x %d but the image region is %d x %d x %d (Y x X x Z). ' ...
        'The store''s grids do not line up; MIB will not resample to force a fit.'], ...
        labelPyramid.levelNames{labelLevel}, ...
        labelShapeYXZ(1), labelShapeYXZ(2), labelShapeYXZ(3), ...
        imageShapeCropYXZ(1), imageShapeCropYXZ(2), imageShapeCropYXZ(3));
    return;
end

% ---- will it fit in memory? --------------------------------------------
% This route is Standard-mode by construction: the image region is read whole
% and the label groups are blended into a model array beside it. That suits the
% thing it was built for - a ground-truth crop is tens of megabytes - but the
% same metadata shape describes a whole-volume inference segmentation, whose
% "crop region" is the entire volume. jrc_mus-liver-6's er segmentation is
% 8500 x 8050 x 8000, i.e. 510 GiB, and without this the first sign of trouble
% was a Python MemoryError from inside the zarr read, four layers down.
imageBytesPerVoxel = bytesPerVoxel(imagePyramid.dataType);
% + 1 byte per voxel for the composed model; MIB then needs headroom again for
% undo and the displayed slice, which is what the 60% default leaves room for.
cropPlan.requiredBytes = prod(double(labelShapeYXZ)) * (imageBytesPerVoxel + 1);

if cropPlan.requiredBytes > memoryLimitBytes
    cropPlan.reason = sprintf(['This group covers %d x %d x %d voxels (Y x X x Z), so opening ' ...
        'it with its image region needs about %s of memory against %s usable here.\n' ...
        'Labels are loaded onto their own image region in memory, which suits a ground-truth ' ...
        'crop but not a segmentation of a whole volume. Open it with Load as = Image instead, ' ...
        'where a pyramid level can be chosen.'], ...
        labelShapeYXZ(1), labelShapeYXZ(2), labelShapeYXZ(3), ...
        formatBytes(cropPlan.requiredBytes), formatBytes(memoryLimitBytes));
    return;
end

cropPlan.ok          = true;
cropPlan.labelLevel  = labelLevel;
cropPlan.imageLevel  = imageLevel;
cropPlan.shapeYXZ    = labelShapeYXZ;
cropPlan.voxelSizeUm = labelVoxelSizes(labelLevel, :);
end

% =========================================================================
function limitBytes = defaultMemoryLimit()
% DEFAULTMEMORYLIMIT - What this machine can spare for a crop, in bytes.
%
% Same approach as utils.stitch.tileCacheBudget: ask MATLAB, and fall back to a
% fixed figure where it cannot answer. The fallback is deliberately generous
% enough for every published COSEM crop (the largest is 64 MB) and far below the
% whole-volume case this guards against, so a wrong guess on Linux or macOS
% cannot turn into a refusal of work that would have succeeded.
limitBytes = 8 * 1024^3;
try
    memoryInfo = memory;
    limitBytes = 0.6 * memoryInfo.MemAvailableAllArrays;
catch
    % not Windows - keep the fixed fallback
end
end

% =========================================================================
function nBytes = bytesPerVoxel(className)
switch className
    case {'uint8', 'int8', 'logical'};   nBytes = 1;
    case {'uint16', 'int16'};            nBytes = 2;
    case {'uint32', 'int32', 'single'};  nBytes = 4;
    case {'uint64', 'int64', 'double'};  nBytes = 8;
    otherwise;                           nBytes = 2;   % unknown: assume 16-bit
end
end

% =========================================================================
function text = formatBytes(nBytes)
units = {'bytes', 'KiB', 'MiB', 'GiB', 'TiB'};
unitIdx = 1;
while nBytes >= 1024 && unitIdx < numel(units)
    nBytes  = nBytes / 1024;
    unitIdx = unitIdx + 1;
end
if unitIdx == 1
    text = sprintf('%d bytes', round(nBytes));
else
    text = sprintf('%.1f %s', nBytes, units{unitIdx});
end
end
