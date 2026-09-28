function stack = tileDrawOrder(numTiles, correction, tileStack)
% TILEDRAWORDER - The order ``'Overwrite'`` draws the tiles in, bottom to top.
%
% Syntax:
%   .. code-block:: matlab
%
%      stack = utils.stitch.tileDrawOrder(numTiles)
%      stack = utils.stitch.tileDrawOrder(numTiles, correction)
%      stack = utils.stitch.tileDrawOrder(numTiles, correction, tileStack)
%
% Where tiles overlap, ``'Overwrite'`` keeps the pixels of the tile drawn LAST.
% This is the one place that decides that order, so the fusers
% (:func:`utils.stitch.fuseSliceComposite`) and the seam inspector - which colours
% the tile on top magenta - can never disagree about which tile wins. Three
% sources, first match wins:
%
% 1. **An explicit stack** set by the user in the seam inspector
%    (``controllers.Stitching.tileStack``). Ignored unless it is a permutation of
%    ``1:numTiles``, so a stack saved for a different layout cannot reorder this
%    one.
% 2. **Re-exposure damage** (``correction.damage`` with footprints): tiles in
%    DESCENDING acquisition rank, so the tile imaged FIRST is on top and every
%    overlap shows the undamaged copy. Tiles the damage model could not place
%    (``NaN`` rank) go to the bottom, in index order.
% 3. **Index order** - the historical behaviour: the highest index wins.
%
% Input Arguments:
%   - **numTiles** - [double] number of tiles in the layout.
%   - **correction** *(optional)* - [struct] intensity correction from
%     :func:`utils.stitch.estimateIntensityCorrection`, or ``[]``.
%   - **tileStack** *(optional)* - [1 x N double] explicit order, bottom first,
%     or ``[]``.
%
% Output Arguments:
%   - **stack** - [1 x N double] tile indices, bottom first: ``stack(end)`` is
%     drawn last and wins every overlap it takes part in.
%
% **Example** - which of tiles 2 and 5 is on top:
%
%   .. code-block:: matlab
%
%      stack = utils.stitch.tileDrawOrder(numel(layout), correction, tileStack);
%      fiveIsAbove = find(stack == 5) > find(stack == 2);
%
% See also utils.stitch.fuseSliceComposite, utils.stitch.estimateIntensityCorrection

arguments
    numTiles   (1,1) double
    correction = []
    tileStack  = []
end

if ~isempty(tileStack) && numel(tileStack) == numTiles && ...
        isequal(sort(double(tileStack(:)))', 1:numTiles)
    stack = double(tileStack(:))';
    return;
end

stack = 1:numTiles;
if isstruct(correction) && isfield(correction, 'damage') && isstruct(correction.damage) && ...
        ~isempty(correction.damage.footprints) && numel(correction.damage.order) == numTiles
    acquisitionRank = correction.damage.order(:);
    acquisitionRank(~isfinite(acquisitionRank)) = Inf;   % unplaced: bottom
    [~, stack] = sort(-acquisitionRank);                  % stable: ties keep index order
    stack = stack(:)';
end
end
