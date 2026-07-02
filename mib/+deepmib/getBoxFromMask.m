function boxes = getBoxFromMask(masks)
% GETBOXFROMMASK - Compute axis-aligned bounding boxes from a stack of instance masks.
%
% Syntax:
%   .. code-block:: matlab
%
%      boxes = deepmib.getBoxFromMask(masks)
%
% Input Arguments:
%   - **masks** — ``[H×W×N logical]`` binary mask stack, one slice per object instance
%
% Output Arguments:
%   - **boxes** — ``[N×4 double]`` bounding boxes in ``[x y width height]`` format
%     (one row per mask slice). Empty mask slices produce a row of ``NaN``, so the
%     caller can filter them together with the corresponding masks and labels.
%
% Used when augmenting instance-segmentation data: after a geometric transform is
% applied to the mask stack the bounding boxes must be recomputed from the warped masks
% to keep boxes and masks in sync (see deepmib.augmentInstanceData2D).

numObjects = size(masks, 3);
boxes = nan(numObjects, 4);
for idx = 1:numObjects
    [ptsR, ptsC] = find(masks(:, :, idx));
    if isempty(ptsR); continue; end     % empty mask -> leave a NaN row
    minR = min(ptsR);   maxR = max(ptsR);
    minC = min(ptsC);   maxC = max(ptsC);
    boxes(idx, :) = [minC, minR, maxC-minC+1, maxR-minR+1];
end
end
