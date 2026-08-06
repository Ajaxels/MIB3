function bls = generateDynamicMaskingBlocks(obj, vol, blockSize, noColors)
% GENERATEDYNAMICMASKINGBLOCKS - generate blocks using dynamic masking parameters acquired in obj.DynamicMaskOpt.
%
% Syntax:
%   .. code-block:: matlab
%
%       bls = obj.generateDynamicMaskingBlocks(vol, blockSize, noColors)
%
% Input Arguments:
%   - **vol** - blocked image to process
%   - **blockSize** - block size
%   - **noColors** - number of color channels in the blocked image
%
% Output Arguments:
%   - **bls** - calculated  blockLocationSet
%     .ImageNumber
%     .BlockOrigin
%     .BlockSize
%     .Levels
%

    % generate the mask
    switch obj.DynamicMaskOpt.Method
        case 'Keep above threshold'
            if noColors == 1
                bmask = apply(vol, @(bs) bs.Data > obj.DynamicMaskOpt.ThresholdValue, "Level", 1);
            elseif noColors == 3
                bmask = apply(vol, @(bs)rgb2gray(bs.Data) > obj.DynamicMaskOpt.ThresholdValue, "Level", 1);
            else
                bmask = apply(vol, @(bs)max(bs.Data, [], 3) > obj.DynamicMaskOpt.ThresholdValue, "Level", 1);
            end
        case 'Keep below threshold'
            if noColors == 1
                bmask = apply(vol, @(bs) bs.Data < obj.DynamicMaskOpt.ThresholdValue, "Level", 1);
            elseif noColors == 3
                bmask = apply(vol, @(bs)rgb2gray(bs.Data) < obj.DynamicMaskOpt.ThresholdValue, "Level", 1);
            else
                bmask = apply(vol, @(bs)max(bs.Data, [], 3) < obj.DynamicMaskOpt.ThresholdValue, "Level", 1);
            end
    end

    % calculate block locations
    bls = selectBlockLocations(vol, 'Mask', bmask, "InclusionThreshold", obj.DynamicMaskOpt.InclusionThreshold, ...
        'Levels', 1, 'BlockSize', blockSize);
    %                             % % preview
    %                             figure(1); bigimageshow(bmask);
    %                             blockedWH = fliplr(bls.BlockSize(1,1:2));
    %                             for ind = 1:size(bls.BlockOrigin,1)
    %                                 % BlockOrigin is already in x,y order.
    %                                 drawrectangle('Position', [bls.BlockOrigin(ind,1:2),blockedWH]);
    %                             end
end

