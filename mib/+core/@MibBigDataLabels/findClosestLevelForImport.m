function [levelIdx, levelSize] = findClosestLevelForImport(obj, sourceDims)
% FINDCLOSESTLEVELFORIMPORT - Pick the pyramid level whose resolution best matches an imported model.
%
% Syntax:
%   .. code-block:: matlab
%
%      [levelIdx, levelSize] = obj.findClosestLevelForImport(sourceDims)
%
% When a model saved at an arbitrary pyramid resolution is imported into this
% disk-backed pyramid, the source must be written at the level whose
% resolution is closest to the source's own resolution.  The source's
% downsampling relative to full resolution is estimated from the size ratio
% along Y (``modelLevelSizes(1,1) / sourceDims(1)``) and fed to ``pickLevel``,
% which selects the nearest level on ``modelScaleFactors(:,1)``.  This mirrors
% how the image reader (``MibVirtualImage.getDataZarr``) chooses a level by
% ``magFactor``, so the imported model lands on the same level the image would
% display at that resolution.
%
% Input Arguments:
%   - **sourceDims** - [1x2 | 1x3 numeric] size of the source model as
%     ``[Y X]`` or ``[Y X Z]`` (the full-slice extent at the source's own
%     resolution).  Only the Y extent is used for the ratio (X is downsampled
%     by the same factor in MIB pyramids).
%
% Output Arguments:
%   - **levelIdx** - [numeric scalar] 1-based pyramid level index (1 = finest /
%     full-resolution; ``nLevels`` = coarsest).
%   - **levelSize** - [1x3 numeric] ``modelLevelSizes(levelIdx, :)`` = the
%     chosen level's ``[Y X Z]`` size.
%
% See also pickLevel, core.MibBigDataLabels/getData63, core.MibBigDataLabels/setData63.

if isempty(sourceDims)
    levelIdx  = 1;
    levelSize = obj.modelLevelSizes(1, :);
    return;
end

fullY   = double(obj.modelLevelSizes(1, 1));
sourceY = double(sourceDims(1));
if sourceY <= 0; sourceY = 1; end

% Downsampling factor of the source relative to full resolution (>= 1 when the
% source is coarser than full res); the nearest level on this factor is chosen.
magFactor = fullY / sourceY;

levelIdx  = obj.pickLevel(struct('magFactor', magFactor));
levelSize = obj.modelLevelSizes(levelIdx, :);
end
