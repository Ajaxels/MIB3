function tf = imageBoxContains(~, candidatePyramid, cropBoxUm, cropVoxelSizeUm)
% IMAGEBOXCONTAINS - Does this candidate image pyramid enclose the crop?
%
% Syntax:
%   .. code-block:: matlab
%
%      tf = obj.imageBoxContains(candidatePyramid, cropBoxUm, cropVoxelSizeUm)
%
% The containment test behind :meth:`resolveSiblingImageGroup`, kept separate so
% it can be asserted offline. A candidate that carries a ``cellmap`` annotation
% is rejected outright: that block is what marks a group as an annotation, so a
% label group that happens to enclose a smaller one must never be offered as the
% image to load it onto.
%
% **Two different roundings have to be tolerated**, which is why the crop's own
% voxel size is an argument rather than something derived from the box:
%
%   * *the candidate's* - half of its own voxel, so a crop reaching exactly to
%     the volume's edge is not rejected by a rounding decimal in the store's
%     declared translation.
%   * *the crop's* - one whole label voxel. A label pyramid published as a
%     downsample of the image rounds its shape UP, so its declared extent
%     overshoots the image's. In ``jrc_ctl-id8-1`` the ``nuc`` segmentation is
%     the EM downsampled 16x and ``18500/16`` rounds up to 1157, so it claims
%     ``1157 * 64 = 74048 nm`` against the EM's ``18500 * 4 = 74000 nm`` - a
%     48 nm overshoot that half an image voxel (2 nm) rejects outright. The
%     excess can never exceed one label voxel, which is therefore the bound.
%
% Input Arguments:
%   - **candidatePyramid** - [struct] a readGroupPyramid result
%   - **cropBoxUm** - [1x6] the crop's outer extent in micrometres
%   - **cropVoxelSizeUm** - [1x3] ``[x y z]`` voxel size of the crop's finest
%     level, in micrometres. Pass zeros to compare on the candidate's rounding
%     alone
%
% Output Arguments:
%   - **tf** - [logical] true when the candidate is an image enclosing the crop

tf = false;
if isempty(candidatePyramid) || ~candidatePyramid.ok; return; end
if ~isempty(candidatePyramid.annotation); return; end

toUm = io.loaders.OmeZarrMetadataUtils.unitToMicrometreFactor(candidatePyramid.unit);
candidateOuterUm = io.loaders.OmeZarrMetadataUtils.outerBoundingBox( ...
    candidatePyramid.levelWorldBoxes(1, :), candidatePyramid.levelVoxelSizesXYZ(1, :)) * toUm;

tolerance = max(candidatePyramid.levelVoxelSizesXYZ(1, :) * toUm / 2, ...
    reshape(cropVoxelSizeUm, 1, 3));

lowerFits = cropBoxUm([1 3 5]) >= candidateOuterUm([1 3 5]) - tolerance;
upperFits = cropBoxUm([2 4 6]) <= candidateOuterUm([2 4 6]) + tolerance;
tf = all(lowerFits) && all(upperFits);
end
