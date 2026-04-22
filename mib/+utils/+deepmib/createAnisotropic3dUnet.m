function [lgraph, outputPatchSize] = createAnisotropic3dUnet(inputPatchSize, numClasses, ...
        filterSize, numFirstFilters, convPadding, encoderDepth, numAnisotropicBlocks)
% function [lgraph, outputPatchSize] = createAnisotropic3dUnet(inputPatchSize, numClasses, ...
%        filterSize, numFirstFilters, convPadding, encoderDepth, numAnisotropicBlocks)
% Create a 3D U-Net with N initial anisotropic (2D) downsampling blocks.
%
% For anisotropic datasets where Z voxel spacing is coarser than XY, the
% first numAnisotropicBlocks encoder stages use 2D convolution kernels
% ([filterSize filterSize 1]) and 2D max-pooling ([2 2 1]), downsampling
% only in the XY plane.  The corresponding decoder stages are also made
% 2D.  After those stages, the remaining encoder/decoder stages use the
% standard 3D kernels.
%
% Parameters:
% inputPatchSize: [@em required] 4-element vector [height width depth channels]
% numClasses: [@em required] number of segmentation classes
% filterSize: [@em required] convolution kernel size for the 3D U-Net template
% numFirstFilters: [@em required] number of output channels for the first encoder stage
% convPadding: [@em required] 'same' or 'valid'
% encoderDepth: [@em required] total number of encoder stages
% numAnisotropicBlocks: [@em optional] number of initial 2D stages; default 1
%
% Return values:
% lgraph: layerGraph (MATLAB < R2026a) or dlnetwork (MATLAB >= R2026a) with
%         the requested anisotropic modifications applied
% outputPatchSize: 4-element vector [height width depth classes], or []
%                  when convPadding is 'valid'
%
% @b Examples:
% @code
% [lgraph, outputPatchSize] = utils.deepmib.createAnisotropic3dUnet( ...
%     [64 64 32 1], 3, 3, 32, 'same', 3, 2);
% @endcode

if nargin < 7; numAnisotropicBlocks = 1; end

if numAnisotropicBlocks >= encoderDepth
    error('MibDeep:createAnisotropic3dUnet', ...
        'numAnisotropicBlocks (%d) must be less than encoderDepth (%d)', ...
        numAnisotropicBlocks, encoderDepth);
end

% Create the base isotropic 3D U-Net
if ~isMATLABReleaseOlderThan('R2026a')
    [lgraph, outputPatchSize] = unet3d(inputPatchSize, numClasses, ...
        'NumFirstEncoderFilters', numFirstFilters, 'FilterSize', filterSize, ...
        'ConvolutionPadding', convPadding, 'EncoderDepth', encoderDepth);
else
    [lgraph, outputPatchSize] = unet3dLayers(inputPatchSize, numClasses, ...
        'NumFirstEncoderFilters', numFirstFilters, 'FilterSize', filterSize, ...
        'ConvolutionPadding', convPadding, 'EncoderDepth', encoderDepth); %#ok<UNRCH>
end

switch convPadding
    case 'same';  paddingValue = 'same';
    case 'valid'; paddingValue = 0;
end

% Replace encoder stages 1..numAnisotropicBlocks with 2D-kernel layers
for stageIndex = 1:numAnisotropicBlocks
    for convSuffix = {'Conv-1', 'Conv-2'}
        layerName = sprintf('Encoder-Stage-%d-%s', stageIndex, convSuffix{1});
        layerId = find(ismember({lgraph.Layers.Name}, layerName));
        numFilters = lgraph.Layers(layerId).NumFilters;
        layer = convolution3dLayer([filterSize filterSize 1], numFilters, ...
            'Padding', paddingValue, 'Name', layerName);
        lgraph = replaceLayer(lgraph, layerName, layer);
    end

    poolLayerName = sprintf('Encoder-Stage-%d-MaxPool', stageIndex);
    layer = maxPooling3dLayer([2 2 1], 'Padding', paddingValue, ...
        'Stride', [2 2 1], 'Name', poolLayerName);
    lgraph = replaceLayer(lgraph, poolLayerName, layer);
end

% Replace the corresponding decoder stages with 2D-kernel layers.
% Decoder-Stage-encoderDepth mirrors Encoder-Stage-1 (both closest to the
% input/output boundary); Decoder-Stage-(encoderDepth-k+1) mirrors
% Encoder-Stage-k.
for stageIndex = 1:numAnisotropicBlocks
    decoderStageId = encoderDepth - stageIndex + 1;

    upconvLayerName = sprintf('Decoder-Stage-%d-UpConv', decoderStageId);
    layerId = find(ismember({lgraph.Layers.Name}, upconvLayerName));
    numFilters = lgraph.Layers(layerId).NumFilters;
    layer = transposedConv3dLayer([2 2 1], numFilters, ...
        'Stride', [2 2 1], 'Name', upconvLayerName);
    lgraph = replaceLayer(lgraph, upconvLayerName, layer);

    for convSuffix = {'Conv-1', 'Conv-2'}
        layerName = sprintf('Decoder-Stage-%d-%s', decoderStageId, convSuffix{1});
        layerId = find(ismember({lgraph.Layers.Name}, layerName));
        numFilters = lgraph.Layers(layerId).NumFilters;
        layer = convolution3dLayer([filterSize filterSize 1], numFilters, ...
            'Padding', paddingValue, 'Name', layerName);
        lgraph = replaceLayer(lgraph, layerName, layer);
    end
end

if strcmp(convPadding, 'valid')
    outputPatchSize = [];
end
end
