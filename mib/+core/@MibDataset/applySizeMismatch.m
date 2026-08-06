function outArray = applySizeMismatch(rawArray, imgH, imgW, action, offsetY, offsetX)
% APPLYSIZEMISMATCH - Crop/place or resize a Model/Mask array to [imgH, imgW].
%
% Syntax:
%   .. code-block:: matlab
%
%       outArray = core.MibDataset.applySizeMismatch(rawArray, imgH, imgW, action, offsetY, offsetX)
%
% Pure data transform (no dialogs, no obj state) used by
% core.MibDataset.loadModel and core.MibDataset.loadMask after the user (or
% the unattended/batch fallback) has decided how to resolve a Model/Mask
% size mismatch against the currently open image.
%
% Input Arguments:
%   - **rawArray** - [numeric|logical] Model/Mask array; the first two
%     dimensions are height/width. Any number of trailing dimensions
%     (depth, time, ...) are carried through unchanged.
%   - **imgH**, **imgW** - [numeric] target height/width (the open image's).
%   - **action** - [char] ``'Crop'`` or ``'Resize'``.
%   - **offsetY**, **offsetX** - [numeric] non-negative pixel offsets, only
%     used when ``action == 'Crop'``. Meaning depends on which side is
%     bigger on that axis: when the source is bigger, the offset selects
%     where the crop window starts within the source; when the source is
%     smaller, it selects where the data is placed within the destination.
%     Callers are expected to keep these within ``[0, abs(imgSize - itemSize)]``
%     so the item stays fully inside the larger of the two - this function
%     does not clamp or validate them.
%
% Output Arguments:
%   - **outArray** - array of size ``[imgH, imgW, <trailing dims>]``, same
%     class as ``rawArray``.
%
% Usage:
%   **Example 1** - crop/place with an offset
%
%   .. code-block:: matlab
%
%      outArray = core.MibDataset.applySizeMismatch(rawModel, imgH, imgW, 'Crop', offsetY, offsetX);
%
%   **Example 2** - resize (nearest-neighbor, preserves label/mask values)
%
%   .. code-block:: matlab
%
%      outArray = core.MibDataset.applySizeMismatch(rawModel, imgH, imgW, 'Resize', 0, 0);
%

% Updates

sz = size(rawArray);
curH = sz(1);
curW = sz(2);
trailingDims = sz(3:end);

switch action
    case 'Resize'
        % 'nearest' is required (not the default bilinear): Model/Mask data is
        % categorical/binary, and interpolating would invent new material
        % indices or non-binary mask values.
        reshaped = reshape(rawArray, curH, curW, []);
        numSlices = size(reshaped, 3);
        resized = zeros(imgH, imgW, numSlices, class(rawArray));
        for sliceIndex = 1:numSlices
            resized(:, :, sliceIndex) = imresize(reshaped(:, :, sliceIndex), [imgH, imgW], 'nearest');
        end
        outArray = reshape(resized, [imgH, imgW, trailingDims]);

    case 'Crop'
        if curH >= imgH
            copyH = imgH;
            srcRow = offsetY + (1:copyH);
            dstRow = 1:copyH;
        else
            copyH = curH;
            srcRow = 1:copyH;
            dstRow = offsetY + (1:copyH);
        end

        if curW >= imgW
            copyW = imgW;
            srcCol = offsetX + (1:copyW);
            dstCol = 1:copyW;
        else
            copyW = curW;
            srcCol = 1:copyW;
            dstCol = offsetX + (1:copyW);
        end

        outArray = zeros([imgH, imgW, trailingDims], class(rawArray));
        outArray(dstRow, dstCol, :, :, :) = rawArray(srcRow, srcCol, :, :, :);

    otherwise
        error('MibDataset:applySizeMismatch', 'Unknown action "%s", expected "Crop" or "Resize"', action);
end
end
