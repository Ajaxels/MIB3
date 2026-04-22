function [lgraph, outputPatchSize] = createNetwork(obj, previewSwitch)
% function lgraph = createNetwork(obj, previewSwitch)
% generate network
% Parameters:
% previewSwitch: logical switch, when 1 - the generated network
% is only for preview, i.e. weights of classes won't be
% calculated
%
% Return values:
% lgraph: network object
% outputPatchSize: output patch size as [height, width, depth, color]

if nargin < 2; previewSwitch = 0; end
lgraph = [];
outputPatchSize = [];
inputPatchSize = str2num(obj.BatchOpt.T_InputPatchSize);    % as [height, width, depth, color]

% debug 2.5D
%obj.BatchOpt.Workflow{1} = '2.5D Semantic';
%obj.BatchOpt.Architecture{1} = '3DC + DLv3 Resnet18';

selectedArchitecture = obj.BatchOpt.Architecture{1};

% default message box settings
mgsOpt.MsgBoxOnly = true;
mgsOpt.headerLines = 1;
mgsOpt.WindowHeight = 180;
mgsOpt.Icon = 'puffin_error';

try
    switch obj.BatchOpt.Workflow{1}
        case '2D Semantic'
            colorDimension = 4; % index of the color dimension in inputPatch

            switch selectedArchitecture
                case 'U-net'
                    [lgraph, outputPatchSize] = unetLayers(...
                        inputPatchSize([1 2 colorDimension]), obj.BatchOpt.T_NumberOfClasses{1}, ...
                        'NumFirstEncoderFilters', obj.BatchOpt.T_NumFirstEncoderFilters{1}, 'FilterSize', obj.BatchOpt.T_FilterSize{1}, ...
                        'ConvolutionPadding', obj.BatchOpt.T_ConvolutionPadding{1}, 'EncoderDepth', obj.BatchOpt.T_EncoderDepth{1}); %#ok<*ST2NM>
                    outputPatchSize = [outputPatchSize(1), outputPatchSize(2), 1, outputPatchSize(3)];  % reformat to [height, width, depth, numClasses]
                case 'U-net +Encoder'
                    [lgraph, outputPatchSize] = obj.generateUnet2DwithEncoder(inputPatchSize([1 2 colorDimension]), obj.BatchOpt.T_EncoderNetwork{1});
                    outputPatchSize = [outputPatchSize(1), outputPatchSize(2), 1, outputPatchSize(3)];  % reformat to [height, width, depth, numClasses]
                case 'SegNet'
                    lgraph = segnetLayers(inputPatchSize([1 2 colorDimension]), obj.BatchOpt.T_NumberOfClasses{1}, obj.BatchOpt.T_EncoderDepth{1}, ...
                        'NumOutputChannels', obj.BatchOpt.T_NumFirstEncoderFilters{1}, ...
                        'FilterSize', obj.BatchOpt.T_FilterSize{1});
                    outputPatchSize = inputPatchSize;  % as [height, width, depth, color]
                case 'DeepLab v3+'
                    if strcmp(obj.BatchOpt.T_ConvolutionPadding{1}, 'valid')
                        msgText = sprintf('"%s" network architecture requires:\n - input patch size of at least [224 224]\n- 1 or 3 color channels\n- "same" padding', obj.BatchOpt.Architecture{1});
                        utils.dlgs.inputUniversalDlg(obj.view.gui, 'Wrong configuration!', {}, {msgText}, 'Wrong configuration!', mgsOpt);
                        return;
                    end

                    targetNetwork = lower(obj.BatchOpt.T_EncoderNetwork{1});
                    if ismember(targetNetwork, {'xception', 'inceptionresnetv2'}) && isdeployed
                        mgsOpt.headerLines = 2;
                        header = sprintf('Currently %s network is only available in MIB for MATLAB', obj.BatchOpt.Architecture{1});
                        utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {'Try to use DLv3-Resnet18/50 instead!'}, 'Ops!', mgsOpt);
                        return;
                    end
                    lgraph = obj.generateDeepLabV3Network(inputPatchSize([1 2 colorDimension]), obj.BatchOpt.T_NumberOfClasses{1}, targetNetwork);
                    if isempty(lgraph); return; end
                    outputPatchSize = inputPatchSize([1 2 4]);
            end
        case '2.5D Semantic'
            if strcmp(obj.BatchOpt.Architecture{1}(1:3), 'Z2C')
                selectedArchitecture = obj.BatchOpt.Architecture{1}(7:end); % skip "Z2C + "
                colorDimension = 3; % index of the color dimension in inputPatch

                switch selectedArchitecture
                    case 'U-net'
                        [lgraph, outputPatchSize] = unetLayers(...
                            inputPatchSize([1 2 colorDimension]), obj.BatchOpt.T_NumberOfClasses{1}, ...
                            'NumFirstEncoderFilters', obj.BatchOpt.T_NumFirstEncoderFilters{1}, 'FilterSize', obj.BatchOpt.T_FilterSize{1}, ...
                            'ConvolutionPadding', obj.BatchOpt.T_ConvolutionPadding{1}, 'EncoderDepth', obj.BatchOpt.T_EncoderDepth{1}); %#ok<*ST2NM>
                    case 'U-net +Encoder'
                        [lgraph, outputPatchSize] = obj.generateUnet2DwithEncoder(inputPatchSize([1 2 colorDimension]), obj.BatchOpt.T_EncoderNetwork{1});
                        outputPatchSize = [outputPatchSize(1) outputPatchSize(2) 1]; % [height, width, depth]
                        % remove the skip connection from the first layer
                        lgraph = layerGraph(lgraph);
                        
                        % find index of the layer (encoderDecoderSkipConnectionCrop1) that needs to be removed
                        skipConnectionLayer = zeros([numel(lgraph.Layers), 1]);
                        % find indices of ReLU layers
                        for layerId = 1:numel(lgraph.Layers)
                            %if isa(lgraph.Layers(layerId), 'nnet.cnn.layer.Convolution2DLayer')
                            %    convIndices(layerId) = 1;
                            %end
                            if strcmp(lgraph.Layers(layerId).Name, 'encoderDecoderSkipConnectionCrop1')
                                skipConnectionLayer(layerId) = 1;
                            end
                        end
                        skipConnectionLayer = find(skipConnectionLayer);
                        % find the name of the previous layer to reconnect the new network
                        prevLayerName = lgraph.Layers(skipConnectionLayer-1).Name;
                        % find the name of the previous layer to reconnect the new network
                        % skip convolutions that were designed to use the
                        % channels from the input layer
                        nextLayerName = lgraph.Layers(skipConnectionLayer+4).Name;

                        removeLayerName0 = lgraph.Layers(skipConnectionLayer).Name;
                        removeLayerName1 = lgraph.Layers(skipConnectionLayer+1).Name;
                        removeLayerName2 = lgraph.Layers(skipConnectionLayer+2).Name;
                        removeLayerName3 = lgraph.Layers(skipConnectionLayer+3).Name;

                        lgraph = removeLayers(lgraph, removeLayerName0);
                        lgraph = removeLayers(lgraph, removeLayerName1);
                        lgraph = removeLayers(lgraph, removeLayerName2);
                        lgraph = removeLayers(lgraph, removeLayerName3);

                        lgraph = connectLayers(lgraph, prevLayerName, nextLayerName);
                        % Convert to dlnetwork
                        lgraph = dlnetwork(lgraph);

                    case 'DLv3'
                        if strcmp(obj.BatchOpt.T_ConvolutionPadding{1}, 'valid')
                            msgText = sprintf('%s" network architecture requires:\n - input patch size of at least [224 224]\n- 1 or 3 color channels\n- "same" padding', obj.BatchOpt.Architecture{1});
                            utils.dlgs.inputUniversalDlg(obj.view.gui, 'Wrong configuration!', {}, {msgText}, 'Wrong configuration!', mgsOpt);
                            return;
                        end
                        targetNetwork = lower(obj.BatchOpt.T_EncoderNetwork{1});
                        
                        lgraph = obj.generateDeepLabV3Network(inputPatchSize([1 2 colorDimension]), obj.BatchOpt.T_NumberOfClasses{1}, targetNetwork);
                        if isempty(lgraph); return; end
                        outputPatchSize = inputPatchSize([1 2 4]);
                end
            else  % 3D convolutional filters
                switch selectedArchitecture
                    case {'3DC + DLv3 Resnet18'}
                        if strcmp(obj.BatchOpt.T_ConvolutionPadding{1}, 'valid')
                            msgText = sprintf('"%s" network architecture requires:\n - input patch size of at least [224 224]\n- 1 or 3 color channels\n- "same" padding', obj.BatchOpt.Architecture{1});
                            utils.dlgs.inputUniversalDlg(obj.view.gui, 'Wrong configuration!', {}, {msgText}, 'Wrong configuration!', mgsOpt);
                            return;
                        end
                        switch selectedArchitecture
                            case '3DC + DLv3 Resnet18'
                                targetNetwork = 'resnet18';
                            case '3DC + DLv3 Resnet50'
                                targetNetwork = 'resnet50';
                        end
                        lgraph = obj.generate3DDeepLabV3Network(inputPatchSize, obj.BatchOpt.T_NumberOfClasses{1}, targetNetwork);

                        if isempty(lgraph); return; end
                        outputPatchSize = inputPatchSize([1 2 3 4]);
                end
            end
        case '3D Semantic'
            switch selectedArchitecture
                case 'U-net'
                    %lgraph = obj.generate3DDeepLabV3Network(inputPatchSize([1 2 4]), obj.BatchOpt.T_NumberOfClasses{1}, 8, 'resnet50');

                    if ~isMATLABReleaseOlderThan('R2026a')  % unet3dLayers removed in R2026a
                        [lgraph, outputPatchSize] = unet3d(...
                            inputPatchSize, obj.BatchOpt.T_NumberOfClasses{1}, ...
                            'NumFirstEncoderFilters', obj.BatchOpt.T_NumFirstEncoderFilters{1}, 'FilterSize', obj.BatchOpt.T_FilterSize{1}, ...
                            'ConvolutionPadding', obj.BatchOpt.T_ConvolutionPadding{1}, 'EncoderDepth', obj.BatchOpt.T_EncoderDepth{1}); %#ok<*ST2NM>
                    else
                        [lgraph, outputPatchSize] = unet3dLayers(...
                            inputPatchSize, obj.BatchOpt.T_NumberOfClasses{1}, ...
                            'NumFirstEncoderFilters', obj.BatchOpt.T_NumFirstEncoderFilters{1}, 'FilterSize', obj.BatchOpt.T_FilterSize{1}, ...
                            'ConvolutionPadding', obj.BatchOpt.T_ConvolutionPadding{1}, 'EncoderDepth', obj.BatchOpt.T_EncoderDepth{1}); %#ok<UNRCH>
                    end
                case 'U-net Anisotropic'
                    %obj.BatchOpt.T_NumAnisotropicBlocks{1} = 1; % define number of 2D convolutional blocks
                    [lgraph, outputPatchSize] = utils.deepmib.createAnisotropic3dUnet(...
                        inputPatchSize, obj.BatchOpt.T_NumberOfClasses{1}, ...
                        obj.BatchOpt.T_FilterSize{1}, obj.BatchOpt.T_NumFirstEncoderFilters{1}, ...
                        obj.BatchOpt.T_ConvolutionPadding{1}, obj.BatchOpt.T_EncoderDepth{1}, ...
                        obj.BatchOpt.T_NumAnisotropicBlocks{1});
            end
        case '2D Patch-wise'
            if obj.BatchOpt.T_UseImageNetWeights
                if isdeployed
                    mgsOpt.headerLines = 2;
                    header = sprintf('Initialization of the network with imagenet weights is only available in MIB for MATLAB!');
                    msgText = 'Please uncheck the "use ImageNet weights" checkbox to initialize the network using empty weights and try again.';
                    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {msgText}, 'Ops!', mgsOpt);
                    return;
                end
                if inputPatchSize(4) ~= 3
                    mgsOpt.headerLines = 2;
                    header = sprintf('Initialization of the network with imagenet weights is only available for images with 3 color channels!');
                    msgText = sprintf('Change "Input patch size" to [%d %d %d 3] and try again', inputPatchSize(1), inputPatchSize(2), inputPatchSize(3));
                    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {msgText}, 'Ops!', mgsOpt);
                    return;
                end
                weightsValue = 'imagenet';
            else
                weightsValue = 'none';
            end
            try
                switch selectedArchitecture
                    case 'Resnet18'
                        lgraph = resnet18('Weights', weightsValue);
                        outputPatchSize = [1 1 inputPatchSize(4)];
                    case 'Resnet50'
                        lgraph = resnet50('Weights', weightsValue);
                        outputPatchSize = [1 1 inputPatchSize(4)];
                    case 'Resnet101'
                        lgraph = resnet101('Weights', weightsValue);
                        outputPatchSize = [1 1 inputPatchSize(4)];
                    case 'Xception'
                        lgraph = xception('Weights', weightsValue);
                        outputPatchSize = [1 1 inputPatchSize(4)];
                end
                % convert from 'DAGNetwork' to 'LayerGraph'
                % when init with imagenet weights
                if isa(lgraph, 'DAGNetwork')
                    lgraph = layerGraph(lgraph);
                end
            catch err
                utils.dlgs.showErrorDialog(obj.view.gui, err, 'Missing packages', 'Most likely required package is missing!');
                return;
            end
    end     % end of "switch obj.BatchOpt.Workflow"
catch err
    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Network configuration error');
    return;
end

% update the input layer
lgraph = obj.updateNetworkInputLayer(lgraph, inputPatchSize);
if isempty(lgraph); return; end

% update the activation layers
lgraph = obj.updateActivationLayers(lgraph);

% update the initialization weight for convolutional layers
% lgraph = updateConvolutionLayers(obj, lgraph);

% update maxPool and TransposedConvolution layers depending on network downsampling factor
if obj.view.handles.T_DownsamplingFactor.Value ~=2 && ismember(selectedArchitecture, {'U-net', 'SegNet'})
    lgraph = obj.updateMaxPoolAndTransConvLayers(lgraph);
end

if strcmp(obj.BatchOpt.Workflow{1}, '2D Patch-wise') % 2D Patch-wise Resnet18 or 2D Patch-wise Resnet50
    % update last 3 layers to adapt them to the new number of output classes
    fullConnLayer = fullyConnectedLayer(obj.BatchOpt.T_NumberOfClasses{1}-1, 'Name', 'FullyConnectedLayer');
    switch obj.BatchOpt.Architecture{1}
        case {'Resnet18', 'Resnet50', 'Resnet101'}
            lgraph = replaceLayer(lgraph, 'fc1000', fullConnLayer);
        case 'Xception'
            lgraph = replaceLayer(lgraph, 'predictions', fullConnLayer);
    end
    if obj.BatchOpt.T_UseImageNetWeights % replace classification output layer
        classificationOutputLayer = classificationLayer('Name', 'ClassificationLayer_predictions');
        lgraph = replaceLayer(lgraph, lgraph.Layers(end).Name, classificationOutputLayer); % 'ClassificationLayer_predictions'
    end
else    % semantic segmentation
    if ~isa(lgraph, 'dlnetwork')
        lgraph = obj.updateSegmentationLayer(lgraph);
    end
end
end