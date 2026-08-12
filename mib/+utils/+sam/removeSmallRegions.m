function mask = removeSmallRegions(mask, minArea)
% REMOVESMALLREGIONS - Drop the small islands SAM returns beside the real object.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      mask = utils.sam.removeSmallRegions(mask, minArea)
%
% Both segment-anything predictors binarize a continuous field of mask logits at
% a hard zero, so any structure elsewhere in the view that scores just above it
% is promoted to full membership with the same weight as the object under the
% seed. In practice the object comes back at a logit of several units while
% these islands sit at 0.3-0.8, which makes them small: a handful of pixels of
% the low-resolution mask the model predicts before it is upsampled to the size
% of the shown block. An area threshold separates the two cleanly, whereas
% raising the logit threshold enough to lose the islands also eats into the
% object and eventually breaks it apart.
%
% Components are measured slice by slice, matching the per-2D-mask semantics of
% ``min_mask_region_area`` in the automatic mask generator, which receives the
% same preference. Note that for pyramidal (BigData, Virtual) datasets SAM works
% on the block at the displayed resolution, so the threshold counts pixels of
% the shown image and not of the full-resolution dataset.
%
% Input Arguments:
%   - **mask** - [numeric | logical] segmentation mask as ``[height, width]`` or
%     ``[height, width, depth]``; non-zero pixels are treated as foreground
%   - **minArea** - [numeric] smallest connected component to keep, in pixels.
%     ``0``, negative and empty all disable the filter and return ``mask``
%     unchanged
%
% Output Arguments:
%   - **mask** - the input mask with every 8-connected component smaller than
%     ``minArea`` set to zero; class and pixel values of the surviving
%     components are preserved
%
% Usage:
%
%   **Example 1** - filter the output of an interactive SAM prediction
%
%   .. code-block:: matlab
%
%      minRegionArea = obj.mibModel.preferences.SegmTools.SAM2.min_mask_region_area;
%      imgOut = utils.sam.removeSmallRegions(imgOut, minRegionArea);
%

% Updates
%

if isempty(minArea) || minArea <= 0; return; end

for z = 1:size(mask, 3)
    slice = mask(:, :, z);
    slice(~bwareaopen(slice > 0, minArea, 8)) = 0;
    mask(:, :, z) = slice;
end

end
