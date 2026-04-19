function [outputLabeledImageBlock, scoreBlock] = segmentBlockedImage(block, net, dataDimension, patchwiseWorkflowSwitch, generateScoreFiles, executionEnvironment, padShift)
% test function for utilization of blockedImage for prediction
% The input block will be a batch of blocks from the a blockedImage.
%
% Parameters:
% block: a structure with a block that is provided by
% blockedImage/apply. The first and second iterations have
% batch size==1, while the following have the batch size equal
% to the selected. Below fields of the structure,
%      .BlockSub: [1 1 1]
%      .Start: [1 1 1]
%      .End: [224 224 3]
%      .Level: 1
%      .ImageNumber: 1
%      .BorderSize: [0 0 0]
%      .BlockSize: [224 224 3]
%      .BatchSize: 1
%      .Data: [224×224×3 uint8]
% net: a trained DAGNetwork
% dataDimension: numeric switch that identify dataset dimension, can be 2, 2.5, 3
% patchwiseWorkflowSwitch: logical switch indicating the patch-wise mode, when true->use patch mode, when false->use semantic segmentation
% generateScoreFiles: variable to generate score files with probabilities of classes
% 0-> do not generate
% 1-> 'Use AM format'
% 2-> 'Use Matlab non-compressed format'
% 3-> 'Use Matlab compressed format'
% 4-> 'Use Matlab non-compressed format (range 0-1)'
% executionEnvironment: string with the environment to execute prediction
% padShift: numeric, (y,x,z or y,x) value for the padding, used during the overlap mode to crop the output patch for export

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
