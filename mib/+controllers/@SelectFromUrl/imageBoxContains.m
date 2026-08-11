function tf = imageBoxContains(~, candidatePyramid, cropBoxUm)
% IMAGEBOXCONTAINS - Does this candidate image pyramid enclose the crop?
%
% Syntax:
%   .. code-block:: matlab
%
%      tf = obj.imageBoxContains(candidatePyramid, cropBoxUm)
%
% The containment test behind :meth:`resolveSiblingImageGroup`, kept separate so
% it can be asserted offline. A candidate that carries a ``cellmap`` annotation
% is rejected outright: that block is what marks a group as an annotation, so a
% label group that happens to enclose a smaller one must never be offered as the
% image to load it onto.
%
% The comparison is padded by half of the candidate's own voxel, so a crop that
% reaches exactly to the volume's edge is not rejected by a rounding decimal in
% the store's declared translation.
%
% Input Arguments:
%   - **candidatePyramid** - [struct] a readGroupPyramid result
%   - **cropBoxUm** - [1x6] the crop's outer extent in micrometres
%
% Output Arguments:
%   - **tf** - [logical] true when the candidate is an image enclosing the crop

tf = false;
if isempty(candidatePyramid) || ~candidatePyramid.ok; return; end
if ~isempty(candidatePyramid.annotation); return; end

toUm = io.loaders.OmeZarrMetadataUtils.unitToMicrometreFactor(candidatePyramid.unit);
candidateOuterUm = io.loaders.OmeZarrMetadataUtils.outerBoundingBox( ...
    candidatePyramid.levelWorldBoxes(1, :), candidatePyramid.levelVoxelSizesXYZ(1, :)) * toUm;

tolerance = candidatePyramid.levelVoxelSizesXYZ(1, :) * toUm / 2;

lowerFits = cropBoxUm([1 3 5]) >= candidateOuterUm([1 3 5]) - tolerance;
upperFits = cropBoxUm([2 4 6]) <= candidateOuterUm([2 4 6]) + tolerance;
tf = all(lowerFits) && all(upperFits);
end
