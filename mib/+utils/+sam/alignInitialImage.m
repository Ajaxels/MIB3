function alignedImage = alignInitialImage(cachedImage, cachedBox, currentImage, currentBox)
% ALIGNINITIALIMAGE - Re-map an image cached over one shown block onto another block.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      alignedImage = utils.sam.alignInitialImage(cachedImage, cachedBox, currentImage, currentBox)
%
% The interactive SAM tools cache the state of the destination layer as it was
% before the segmentation of the current object started, so that every
% refinement click can be merged with that initial state instead of with the
% result of the previous click. The cache is taken in the block mode and
% becomes invalid as soon as the user zooms, pans or seeds a new slice.
%
% This function rebuilds the initial state for the new block: it starts from
% **currentImage** (the layer as it is right now, which outside of
% **cachedBox** was never touched by SAM and therefore still holds the initial
% state) and pastes **cachedImage** over the overlapping part. When the two
% blocks cannot be related to each other (different orientation or different
% pyramid level) **currentImage** is returned unchanged.
%
% Input Arguments:
%   - **cachedImage** - [numeric] image cached over **cachedBox**, ``[height, width, depth]``
%   - **cachedBox** - struct returned by :func:`utils.sam.blockBox` at the moment
%     **cachedImage** was taken; can be empty
%   - **currentImage** - [numeric] the destination layer fetched over **currentBox**
%   - **currentBox** - struct returned by :func:`utils.sam.blockBox` for the current view
%
% Output Arguments:
%   - **alignedImage** - [numeric] **currentImage** with **cachedImage** pasted
%     into the overlapping area; same size and class as **currentImage**
%
% Usage:
%
%   **Example 1** - restore the pre-SAM state after the view was zoomed out
%
%   .. code-block:: matlab
%
%      currentBox = utils.sam.blockBox(dataset, [z1 z2]);
%      initialImage = utils.sam.alignInitialImage(cachedImage, cachedBox, currentImage, currentBox);
%

% Updates
%

alignedImage = currentImage;

if isempty(cachedImage) || isempty(cachedBox) || ~isstruct(cachedBox); return; end
if ~isstruct(currentBox); return; end
if cachedBox.orientation ~= currentBox.orientation; return; end
% a different pyramid level would require resizing of the cache, in this case
% the current state of the layer is the best available approximation
if abs(cachedBox.magFactor - currentBox.magFactor) > 1e-6; return; end

magFactor = currentBox.magFactor;
[rowsCurrent, rowsCached] = matchRange(cachedBox.y, currentBox.y, magFactor, size(currentImage, 1), size(cachedImage, 1));
[colsCurrent, colsCached] = matchRange(cachedBox.x, currentBox.x, magFactor, size(currentImage, 2), size(cachedImage, 2));
[slicesCurrent, slicesCached] = matchRange(cachedBox.z, currentBox.z, 1, size(currentImage, 3), size(cachedImage, 3));
if isempty(rowsCurrent) || isempty(colsCurrent) || isempty(slicesCurrent); return; end

alignedImage(rowsCurrent, colsCurrent, slicesCurrent) = ...
    cast(cachedImage(rowsCached, colsCached, slicesCached), 'like', alignedImage);

end

function [indicesCurrent, indicesCached] = matchRange(cachedRange, currentRange, magFactor, currentCount, cachedCount)
% MATCHRANGE - indices of the overlapping part of two ranges in both images.
%
% Input Arguments:
%   - **cachedRange** - ``[minValue, maxValue]`` of the cached block in the dataset coordinates
%   - **currentRange** - ``[minValue, maxValue]`` of the current block in the dataset coordinates
%   - **magFactor** - number of dataset units per pixel of the fetched blocks
%   - **currentCount** - number of pixels of the current image in this dimension
%   - **cachedCount** - number of pixels of the cached image in this dimension
%
% Output Arguments:
%   - **indicesCurrent** - indices of the overlap in the current image
%   - **indicesCached** - indices of the overlap in the cached image
%

indicesCurrent = [];
indicesCached = [];

overlap = [max([cachedRange(1) currentRange(1)]), min([cachedRange(2) currentRange(2)])];
if overlap(2) < overlap(1); return; end

startCurrent = floor((overlap(1) - currentRange(1))/magFactor) + 1;
startCached = floor((overlap(1) - cachedRange(1))/magFactor) + 1;
if startCurrent < 1 || startCached < 1; return; end

% rounding of the pyramidal fetches may shift the sizes by a pixel, so keep
% the number of elements that both images can provide
overlapCount = min([round((overlap(2)-overlap(1)+1)/magFactor), ...
    currentCount-startCurrent+1, cachedCount-startCached+1]);
if overlapCount < 1; return; end

indicesCurrent = startCurrent:startCurrent+overlapCount-1;
indicesCached = startCached:startCached+overlapCount-1;

end
