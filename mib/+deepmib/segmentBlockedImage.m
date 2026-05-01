function [outputLabeledImageBlock, scoreBlock] = segmentBlockedImage(block, net, dataDimension, patchwiseWorkflowSwitch, generateScoreFiles, executionEnvironment, padShift)
% SEGMENTBLOCKEDIMAGE - Segment a blocked image using a trained network.
%
% Syntax:
%   .. code-block:: matlab
%
%      [outputLabeledImageBlock, scoreBlock] = segmentBlockedImage( ...
%          block, net, dataDimension, patchwiseWorkflowSwitch, ...
%          generateScoreFiles, executionEnvironment, padShift)
%
% The input block is provided as a batch of blocks from a ``blockedImage``.
%
% Input Arguments:
%   - **block** — struct provided by ``blockedImage/apply``; the first two iterations
%     have ``BatchSize == 1``, subsequent ones use the user-selected batch size:
%
%     - ``.BlockSub`` — block subscript index, e.g. ``[1 1 1]``
%     - ``.Start`` — block start position in the image, e.g. ``[1 1 1]``
%     - ``.End`` — block end position, e.g. ``[224 224 3]``
%     - ``.Level`` — resolution level
%     - ``.ImageNumber`` — index of the source image
%     - ``.BorderSize`` — border padding, e.g. ``[0 0 0]``
%     - ``.BlockSize`` — block dimensions, e.g. ``[224 224 3]``
%     - ``.BatchSize`` — number of blocks in the batch
%     - ``.Data`` — pixel data array, e.g. ``[224×224×3 uint8]``
%
%   - **net** — trained ``DAGNetwork`` or ``dlnetwork``
%   - **dataDimension** — [numeric] dataset dimensionality: ``2``, ``2.5``, or ``3``
%   - **patchwiseWorkflowSwitch** — [logical] ``true`` for patch-wise classification,
%     ``false`` for semantic segmentation
%   - **generateScoreFiles** — [integer] score file format to generate:
%
%     - ``0`` — do not generate score files
%     - ``1`` — AM format
%     - ``2`` — MATLAB non-compressed format
%     - ``3`` — MATLAB compressed format
%     - ``4`` — MATLAB non-compressed format (range 0–1)
%
%   - **executionEnvironment** — [char] execution environment for prediction
%     (e.g. ``'auto'``, ``'gpu'``, ``'cpu'``)
%   - **padShift** — [numeric] ``[y, x]`` or ``[y, x, z]`` padding to crop output
%     during overlap-mode prediction
%

batchSizeDimension = numel(block.BlockSize) + 1;
batchSize = size(block.Data, batchSizeDimension);

% permute dataset for grayscale images when the batch size is
% more than 1, otherwise give error for batch size>1 in the
% patchwise mode
if batchSizeDimension == 3 && batchSize > 1
    block.Data = permute(block.Data, [1 2 4 3]);
end

switch dataDimension
    case 2  % 2D case
        if ~patchwiseWorkflowSwitch
            if batchSizeDimension == 3 && ndims(block.Data) == 3 % second and other calls for grayscale images
                % requres to permute the dataset to add a color channel
                [outputLabeledImageBlock, ~, scoreBlock] = semanticseg(permute(block.Data, [1,2,4,3]), net, ...
                    'OutputType', 'uint8',...
                    'ExecutionEnvironment', executionEnvironment);
            else
                [outputLabeledImageBlock, ~, scoreBlock] = semanticseg(block.Data, net, ...
                    'OutputType', 'uint8',...
                    'ExecutionEnvironment', executionEnvironment);

                %scores = predict(net, single(block.Data));
                %[label,score] = scores2label(scores, {'bg', 'mito'});
            end

            % crop the output
            if sum(padShift) ~= 0
                y1 = padShift(1)+1;
                y2 = padShift(1)+1+block.BlockSize(1)-1;
                x1 = padShift(2)+1;
                x2 = padShift(2)+1+block.BlockSize(2)-1;
                outputLabeledImageBlock = outputLabeledImageBlock(y1:y2, x1:x2, :, :);
                if generateScoreFiles > 0
                    scoreBlock = scoreBlock(y1:y2, x1:x2, :, :);
                end
            end

            % Add singleton channel dimension to permit blocked image apply to
            % reconstruct the full image from the processed blocks.
            sz = size(outputLabeledImageBlock);
            %outputLabeledImageBlock = reshape(outputLabeledImageBlock, [sz(1:2) 1 sz(3:end)]);
            outputLabeledImageBlock = reshape(outputLabeledImageBlock, [sz(1:2) 1 batchSize]);
            if generateScoreFiles > 0
                sz = size(scoreBlock);
                if generateScoreFiles < 4 %  convert to uint8
                    scoreBlock = uint8(scoreBlock*255);     % scale and convert to uint8
                end
                scoreBlock = reshape(scoreBlock, [sz(1:3) batchSize]);
            else
                scoreBlock = zeros([sz(1:2) 1 batchSize]);
            end
        else
            [outputLabeledImageBlock, scoreBlock] = classify(net, block.Data, ...
                'ExecutionEnvironment', executionEnvironment);

            outputLabeledImageBlock = reshape(outputLabeledImageBlock, [1 batchSize]);
            scoreBlock = reshape(scoreBlock', [1 1 size(scoreBlock,2) batchSize]);
        end
    case 2.5  % 2D case
        if batchSizeDimension == 4 && ndims(block.Data) == 4 % second and other calls for grayscale images
            % requres to permute the dataset to add a color channel
            [outputLabeledImageBlock, ~, scoreBlock] = semanticseg(permute(block.Data, [1,2,3,5,4]), net, ...
                'OutputType', 'uint8',...
                'ExecutionEnvironment', executionEnvironment);
        else
            [outputLabeledImageBlock, ~, scoreBlock] = semanticseg(block.Data, net, ...
                'OutputType', 'uint8',...
                'ExecutionEnvironment', executionEnvironment);
        end

        %[scores, pixelLabels] = max(scoreBlock(:,:,3,:,1,:), [], 4);

        % crop the output
        z = ceil(block.BlockSize(3)/2);
        if sum(padShift) ~= 0
            y1 = padShift(1)+1;
            y2 = padShift(1)+1 + block.BlockSize(1)-1;
            x1 = padShift(2)+1;
            x2 = padShift(2)+1 + block.BlockSize(2)-1;
            %z1 = padShift(3)+1;
            %z2 = padShift(3)+1 + block.BlockSize(3)-1;
            %outputLabeledImageBlock = outputLabeledImageBlock(y1:y2, x1:x2, z1:z2, :, :);
            outputLabeledImageBlock = outputLabeledImageBlock(y1:y2, x1:x2, z, :, :);   % get a single slice
            if generateScoreFiles > 0
                %scoreBlock = scoreBlock(y1:y2, x1:x2, z1:z2, :, :);
                scoreBlock = scoreBlock(y1:y2, x1:x2, z, :, :);
            end
        else
            outputLabeledImageBlock = outputLabeledImageBlock(:, :, z, :, :);   % get a single slice
            if generateScoreFiles > 0
                scoreBlock = scoreBlock(:, :, z, :, :);
            end
        end

        % Add singleton channel dimension to permit blocked image apply to
        % reconstruct the full image from the processed blocks.
        sz = size(outputLabeledImageBlock);
        %outputLabeledImageBlock = reshape(outputLabeledImageBlock, [sz(1:3) 1 batchSize]);
        outputLabeledImageBlock = reshape(outputLabeledImageBlock, [sz(1:2) 1 batchSize]);
        if generateScoreFiles > 0
            sz = size(scoreBlock);
            if generateScoreFiles < 4 %  convert to uint8
                scoreBlock = uint8(scoreBlock*255);     % scale and convert to uint8
            end
            % scoreBlock = reshape(scoreBlock, [sz(1:4) batchSize]);
            scoreBlock = reshape(scoreBlock, [sz(1:2) sz(4) batchSize]);
        else
            %scoreBlock = zeros([sz(1:3) 1 batchSize]);
            scoreBlock = zeros([sz(1:2) 1 batchSize]);
        end
    case 3  % 3D case
        if ~patchwiseWorkflowSwitch
            if batchSizeDimension == 4 && ndims(block.Data) == 4 % second and other calls for grayscale images
                % requres to permute the dataset to add a color channel
                [outputLabeledImageBlock, ~, scoreBlock] = semanticseg(permute(block.Data, [1,2,3,5,4]), net, ...
                    'OutputType', 'uint8',...
                    'ExecutionEnvironment', executionEnvironment);
            else
                [outputLabeledImageBlock, ~, scoreBlock] = semanticseg(block.Data, net, ...
                    'OutputType', 'uint8',...
                    'ExecutionEnvironment', executionEnvironment);
            end

            % crop the output
            if sum(padShift) ~= 0
                y1 = padShift(1)+1;
                y2 = padShift(1)+1 + block.BlockSize(1)-1;
                x1 = padShift(2)+1;
                x2 = padShift(2)+1 + block.BlockSize(2)-1;
                z1 = padShift(3)+1;
                z2 = padShift(3)+1 + block.BlockSize(3)-1;
                outputLabeledImageBlock = outputLabeledImageBlock(y1:y2, x1:x2, z1:z2, :, :);
                if generateScoreFiles > 0
                    scoreBlock = scoreBlock(y1:y2, x1:x2, z1:z2, :, :);
                end
            end

            % Add singleton channel dimension to permit blocked image apply to
            % reconstruct the full image from the processed blocks.
            sz = size(outputLabeledImageBlock);
            %outputLabeledImageBlock = reshape(outputLabeledImageBlock, [sz(1:2) 1 sz(3:end)]);
            outputLabeledImageBlock = reshape(outputLabeledImageBlock, [sz(1:3) 1 batchSize]);
            if generateScoreFiles > 0
                sz = size(scoreBlock);
                if generateScoreFiles < 4 %  convert to uint8
                    scoreBlock = uint8(scoreBlock*255);     % scale and convert to uint8
                end
                scoreBlock = reshape(scoreBlock, [sz(1:4) batchSize]);
            else
                scoreBlock = zeros([sz(1:3) 1 batchSize]);
            end
        else
            error('not implemented');
        end
end
end
