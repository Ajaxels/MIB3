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
% **What has to be decided.** The two pyramids do not line up level for level,
% and which one has to give up levels depends on what the label group is:
%
%   * A **ground-truth crop** is annotated FINER than the volume it came from -
%     the OpenOrganelle crops are 2 nm against 4 nm EM - so the image opens at
%     its finest level and the labels supply the matching coarser one. For the
%     COSEM crops that is label ``s1`` against image ``s0``.
%   * A **whole-volume inference segmentation** is the other way round: it is
%     often published only from a coarse level down. ``jrc_ctl-id8-1``'s ``nuc``
%     starts at 64 nm, which is the EM's ``s4`` exactly, so there the IMAGE is
%     the pyramid that gives up levels and the dataset opens at 64 nm.
%
% Image levels are therefore searched from the finest, which keeps the first
% case picking ``s0`` and lets the second fall through to the level that matches.
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
%     - ``.imageLevelName`` - [char] the image level's own name (``'s4'``), for
%       reporting which resolution the dataset will actually open at
%     - ``.shapeYXZ`` - [1x3] agreed voxel counts
%     - ``.voxelSizeUm`` - [1x3] ``[x y z]`` voxel size of the chosen pair
%     - ``.requiredBytes`` - [numeric] what opening it costs in RAM, 0 until the
%       shapes are known
%     - ``.candidatePairs`` - [1xN struct] every level pair that lines up, finest
%       image level first, each with ``imageLevel``, ``labelLevel``,
%       ``imageLevelName``, ``shapeYXZ``, ``voxelSizeUm``, ``requiredBytes`` and
%       ``fits``. The chosen pair above is the first one whose ``fits`` is true;
%       the rest are what the level dialog offers

if nargin < 4 || isempty(memoryLimitBytes); memoryLimitBytes = defaultMemoryLimit(); end

cropPlan = struct('ok', false, 'reason', '', 'cropOuterBoxUm', [], ...
    'labelLevel', 1, 'imageLevel', 1, 'imageLevelName', '', ...
    'shapeYXZ', [0 0 0], 'voxelSizeUm', [0 0 0], 'requiredBytes', 0, ...
    'candidatePairs', emptyCandidate());

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

% ---- EVERY level pair that shares a resolution --------------------------
% All of them, not just the first: which one the user wants is a question worth
% asking (see SelectFromUrl.chooseCropLevel), and a coarser pair may be the only
% one that fits in memory. Collected finest-image-level first, so the default
% pick keeps a ground-truth crop on image s0 exactly as before.
labelVoxelSizes = labelPyramid.levelVoxelSizesXYZ * labelToUm;
imageVoxelSizes = imagePyramid.levelVoxelSizesXYZ * imageToUm;

% One part in a thousand: enough slack for the rounded decimals a store writes
% (5.24 against 2.62 x 2), nowhere near enough to accept a 2x level as a match.
scaleTolerance = 1e-3;

% + 1 byte per voxel for the composed model; MIB then needs headroom again for
% undo and the displayed slice, which is what the 60% default leaves room for.
imageBytesPerVoxel = bytesPerVoxel(imagePyramid.dataType) + 1;

candidatePairs      = emptyCandidate();
closestPair         = [1 1];   % kept only to name real numbers in the refusal
closestMismatch     = Inf;
shapeMismatchReason = '';
outsideImage        = false;

for candidateImageLevel = 1:size(imageVoxelSizes, 1)
    mismatchPerLabelLevel = max(abs( ...
        labelVoxelSizes ./ imageVoxelSizes(candidateImageLevel, :) - 1), [], 2);
    [levelMismatch, candidateLabelLevel] = min(mismatchPerLabelLevel);
    if levelMismatch < closestMismatch
        closestMismatch = levelMismatch;
        closestPair     = [candidateLabelLevel, candidateImageLevel];
    end
    if levelMismatch > scaleTolerance; continue; end

    % ---- the image region the crop covers, on THIS level's own grid ----
    voxelRange = io.loaders.OmeZarrMetadataUtils.regionToVoxelRange( ...
        cropOuterBoxUm / imageToUm, ...
        imagePyramid.levelWorldBoxes(candidateImageLevel, :), ...
        imagePyramid.levelVoxelSizesXYZ(candidateImageLevel, :), ...
        imagePyramid.levelShapesYXZ(candidateImageLevel, [2 1 3]));
    imageCountXYZ = max(voxelRange(:, 2) - voxelRange(:, 1) + 1, 0)';
    if any(imageCountXYZ == 0); outsideImage = true; continue; end

    labelShapeYXZ     = labelPyramid.levelShapesYXZ(candidateLabelLevel, :);
    imageShapeCropYXZ = imageCountXYZ([2 1 3]);
    if ~isequal(labelShapeYXZ, imageShapeCropYXZ)
        if isempty(shapeMismatchReason)
            shapeMismatchReason = sprintf(['The crop and the matching image region disagree ' ...
                'on size: labels %s are %d x %d x %d but the image region is %d x %d x %d ' ...
                '(Y x X x Z). The store''s grids do not line up; MIB will not resample to ' ...
                'force a fit.'], ...
                labelPyramid.levelNames{candidateLabelLevel}, ...
                labelShapeYXZ(1), labelShapeYXZ(2), labelShapeYXZ(3), ...
                imageShapeCropYXZ(1), imageShapeCropYXZ(2), imageShapeCropYXZ(3));
        end
        continue;
    end

    requiredBytes = prod(double(labelShapeYXZ)) * imageBytesPerVoxel;
    levelName = '';
    if candidateImageLevel <= numel(imagePyramid.levelNames)
        levelName = char(imagePyramid.levelNames{candidateImageLevel});
    end
    candidatePairs(end+1) = struct( ...
        'imageLevel', candidateImageLevel, 'labelLevel', candidateLabelLevel, ...
        'imageLevelName', levelName, 'shapeYXZ', labelShapeYXZ, ...
        'voxelSizeUm', labelVoxelSizes(candidateLabelLevel, :), ...
        'requiredBytes', requiredBytes, ...
        'fits', requiredBytes <= memoryLimitBytes); %#ok<AGROW>
end

cropPlan.candidatePairs = candidatePairs;

if isempty(candidatePairs)
    if ~isempty(shapeMismatchReason)
        cropPlan.reason = shapeMismatchReason;
    elseif outsideImage
        cropPlan.reason = ['This crop lies outside the image pyramid found for it. Enter the ' ...
            'correct image group path by hand.'];
    else
        cropPlan.reason = sprintf(['The label and image pyramids share no common resolution ' ...
            '(closest is %g x %g x %g um against the image''s %g x %g x %g um). MIB will not ' ...
            'resample one to fit the other.'], ...
            labelVoxelSizes(closestPair(1), 1), labelVoxelSizes(closestPair(1), 2), ...
            labelVoxelSizes(closestPair(1), 3), ...
            imageVoxelSizes(closestPair(2), 1), imageVoxelSizes(closestPair(2), 2), ...
            imageVoxelSizes(closestPair(2), 3));
    end
    return;
end

% ---- will any of them fit in memory? -----------------------------------
% This route is Standard-mode by construction: the image region is read whole
% and the label groups are blended into a model array beside it. That suits the
% thing it was built for - a ground-truth crop is tens of megabytes - but the
% same metadata shape describes a whole-volume inference segmentation, whose
% "crop region" is the entire volume. jrc_mus-liver-6's er segmentation is
% 8500 x 8050 x 8000, i.e. 510 GiB, and without this the first sign of trouble
% was a Python MemoryError from inside the zarr read, four layers down.
firstFitting = find([candidatePairs.fits], 1);
if isempty(firstFitting)
    finest = candidatePairs(1);
    cropPlan.shapeYXZ      = finest.shapeYXZ;
    cropPlan.requiredBytes = finest.requiredBytes;
    cropPlan.reason = sprintf(['This group covers %d x %d x %d voxels (Y x X x Z), so opening ' ...
        'it with its image region needs about %s of memory against %s usable here.\n' ...
        'Labels are loaded onto their own image region in memory, which suits a ground-truth ' ...
        'crop but not a segmentation of a whole volume. Open it with Load as = Image instead, ' ...
        'where a pyramid level can be chosen.'], ...
        finest.shapeYXZ(1), finest.shapeYXZ(2), finest.shapeYXZ(3), ...
        formatBytes(finest.requiredBytes), formatBytes(memoryLimitBytes));
    return;
end

% The finest pair that fits is the default, so the preselected row of the level
% dialog is always one that can actually be opened.
cropPlan = applyCandidate(cropPlan, candidatePairs(firstFitting));
cropPlan.ok = true;
end

% =========================================================================
function cropPlan = applyCandidate(cropPlan, candidate)
% APPLYCANDIDATE - Promote one candidate pair to the plan's chosen pair.
% Shared with SelectFromUrl.chooseCropLevel, which re-applies the user's pick.
cropPlan.labelLevel     = candidate.labelLevel;
cropPlan.imageLevel     = candidate.imageLevel;
cropPlan.imageLevelName = candidate.imageLevelName;
cropPlan.shapeYXZ       = candidate.shapeYXZ;
cropPlan.voxelSizeUm    = candidate.voxelSizeUm;
cropPlan.requiredBytes  = candidate.requiredBytes;
end

% =========================================================================
function candidate = emptyCandidate()
% EMPTYCANDIDATE - 0x0 struct array with the candidate fields, so growing it
% in the loop does not depend on the first assignment to define the shape.
candidate = struct('imageLevel', {}, 'labelLevel', {}, 'imageLevelName', {}, ...
    'shapeYXZ', {}, 'voxelSizeUm', {}, 'requiredBytes', {}, 'fits', {});
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
