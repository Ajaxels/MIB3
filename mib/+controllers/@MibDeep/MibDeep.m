classdef MibDeep < handle
    % @type MibDeep class is a template class for using with
    % GUI developed using appdesigner of Matlab
    %
    % @code
    % obj.mibController.startController('controllers.MibDeep', obj.mibController);; // as GUI tool
    % @endcode
    % or
    % @code
    % // a code below was used for mibImageArithmeticController
    % BatchOpt.Parameter = 'test'mib;  // fill edit boxes as strings
    % BatchOpt.Checkbox = true;     // fill checkboxes with logicals: true/false
    % BatchOpt.Popup = {'value'};        // value for the popups as a cell
    % BatchOpt.Radio = {'Radio1'};          // selection of radio buttons, as cell with the handle of the target radio button
    % BatchOpt.showWaitbar = true;  // show or not the waitbar
    % obj.startController('MibDeep', [], BatchOpt); // start MibDeep in the batch mode
    % @endcode
    % or
    % @code
    % // trigger return of the possible Options using returnBatchOpt function
    % // using notify syncBatch event
    % obj.startController('MibDeep', [], NaN);
    % @endcode

    % Updates
    %

    properties
        mibModel
        % handles to mibModel
        mibController
        % handle to mib controller
        view
        % handle to the view / mibDeepGUI
        listener
        % a cell array with handles to listeners
        childControllers
        % list of opened subcontrollers
        childControllersIds
        % a cell array with names of initialized child controllers
        availableArchitectures
        % containers.Map with available architectures
        % keySet = {'2D Semantic', '2.5D Semantic', '3D Semantic', '2D Patch-wise', '2D Instance'};
        % valueSet{1} = {'DeepLab v3+', 'SegNet', 'U-net', 'U-net +Encoder'}; old: {'U-net', 'SegNet', 'DLv3 Resnet18', 'DLv3 Resnet50', 'DLv3 Xception', 'DLv3 Inception-ResNet-v2'}
        % valueSet{2} = {'Z2C + DLv3', 'Z2C + DLv3', 'Z2C + U-net', 'Z2C + U-net +Encoder'}; % 3DC + DLv3 Resnet18'
        % valueSet{3} = {'U-net', 'U-net Anisotropic'}
        % valueSet{4} = {'Resnet18', 'Resnet50', 'Resnet101', 'Xception'}
        % valueSet{5} = {'SOLOv2'} old: {'SOLOv2 Resnet18', 'SOLOv2 Resnet50'};
        availableEncoders
        % containers.Map with available encoders
        % keySet - is a mixture of workflow -space- architecture {'2D Semantic DeepLab v3+', '2D Semantic U-net +Encoder'}
        % encoders for each "workflow -space- architecture" combination, the last value shows the selected encoder
        % encodersList{1} = {'Resnet18', 'Resnet50', 'Xception', 'InceptionResnetv2', 1}; % for '2D Semantic DeepLab v3+'
        % encodersList{2} = {'Classic', 'Resnet18', 'Resnet50', 2}; % for '2D Semantic U-net +Encoder'
        % encodersList{3} = {'Resnet18', 'Resnet50', 1}; % for '2D Instance SOLOv2''
        BatchOpt
        % a structure compatible with batch operation
        % name of each field should be displayed in a tooltip of GUI
        % it is recommended that the Tags of widgets match the name of the
        % fields in this structure
        % .Parameter - [editbox], char/string
        % .Checkbox - [checkbox], logical value true or false
        % .Dropdown{1} - [dropdown],  cell string for the dropdown
        % .Dropdown{2} - [optional], an array with possible options
        % .Radio - [radiobuttons], cell string 'Radio1' or 'Radio2'...
        % .ParameterNumeric{1} - [numeric editbox], cell with a number
        % .ParameterNumeric{2} - [optional], vector with limits [min, max]
        % .ParameterNumeric{3} - [optional], string 'on' - to round the value, 'off' to do not round the value
        AugOpt2D
        % a structure with augumentation options for 2D unets, default
        % obtained from obj.mibModel.preferences.Deep.AugOpt2D, see getDefaultParameters.m
        % .FillValue = 0;
        % .RandXReflection = true;
        % .RandYReflection = true;
        % .RandRotation = [-10, 10];
        % .RandScale = [.95 1.05];
        % .RandXScale = [.95 1.05];
        % .RandYScale = [.95 1.05];
        % .RandXShear = [-5 5];
        % .RandYShear = [-5 5];
        Aug2DFuncNames
        % cell array with names of 2D augmenter functions
        Aug2DFuncProbability
        % probabilities of each 2D augmentation action to be triggered
        Aug3DFuncNames
        % cell array with names of 2D augmenter functions
        Aug3DFuncProbability
        % probabilities of each 3D augmentation action to be triggered
        gpuInfoFig
        % a handle for GPU info window
        AugOpt3D
        % .Fraction = .6;   % augment 60% of patches
        % .FillValue = 0;
        % .RandXReflection = true;
        % .RandYReflection = true;
        % .RandZReflection = true;
        % .Rotation90 = true;
        % .ReflectedRotation90 = true;
        ActivationLayerOpt
        % options for the activation layer
        DynamicMaskOpt
        % options for calculation of dynamic masks for prediction using blocked image mode
        % .Method = 'Keep above threshold';  % 'Keep above threshold' or 'Keep below threshold'
        % .ThresholdValue = 60;
        % .InclusionThreshold = 0.1;     % Inclusion threshold for mask blocks
        SegmentationLayerOpt
        % options for the segmentation layer
        InputLayerOpt
        % a structure with settings for the input layer
        % .Normalization = 'zerocenter';
        % .Mean = [];
        % .StandardDeviation = [];
        % .Min = [];
        % .Max = [];
        modelMaterialColors
        % colors of materials
        PatchPreviewOpt
        % structure with preview patch options
        % .noImages = 9, number of images in montage
        % .imageSize = 160, patch size for preview
        % .labelShow = true, display overlay labels with details
        % .labelSize = 9, font size for the label
        % .labelColor = 'black', color of the label
        % .labelBgColor = 'yellow', color of the label background
        % .labelBgOpacity = 0.6;   % opacity of the background
        ScoreExportOpt
        % structure with settings to export score files
        % .Precision = 8;   % define precision for the output scores, '8' or '16' bit
        % .IncludeExterior = false;  % when false the scores will also have probability for the background material
        SendReports
        % send email reports with progress of the training process
        % .T_SendReports = false;
        % .FROM_email = 'user@gmail.com';
        % .SMTP_server = 'smtp-relay.brevo.com';
        % .SMTP_port = '587';
        % .SMTP_auth = true;
        % .SMTP_starttls = true;
        % .SMTP_sername = 'user@gmail.com';
        % .SMTP_password = '';
        % .sendWhenFinished = false;
        % .sendDuringRun = false;
        TrainingOpt
        % a structure with training options, the default ones are obtained
        % from obj.mibModel.preferences.Deep.TrainingOpt, see getDefaultParameters.m
        % .solverName = 'adam';
        % .MaxEpochs = 50;
        % .Shuffle = 'once';
        % .InitialLearnRate = 0.0005;
        % .LearnRateSchedule = 'piecewise';
        % .LearnRateDropPeriod = 10;
        % .LearnRateDropFactor = 0.1;
        % .L2Regularization = 0.0001;
        % .Momentum = 0.9;
        % .ValidationFrequency = 400;
        % .Plots = 'training-progress';
        TrainingProgress
        % a structure to be used for the training progress plot for the
        % compiled version of MIB
        % .maxNoIter = max number of iteractions for during training
        % .iterPerEpoch - iterations per epoch
        % .stopTraining - logical switch that forces to stop training and
        % save all progress
        wb
        % handle to waitbar
        colormap6
        % colormap for 6 colors
        colormap20
        % colormap for 20 colors
        colormap255
        % colormap for 255 colors
        sessionSettings
        % structure for the session settings
        % .countLabelsDir - directory with labels to count, used in count labels function
        TrainEngine
        % temp property to test trainnet function for training: can be
        % 'trainnet' or 'trainNetwork'
    end

    events
        %> Description of events
        CloseEvent
        % event firing when window is closed
    end

    methods (Static)
        function viewListner_Callback(obj, src, evnt)
            switch evnt.EventName
                case {'updateGuiWidgets'}
                    obj.updateWidgets();
            end
        end

        function data = tif3DFileRead(filename)
            % data = tif3DFileRead(filename)
            % custom reading function to load tif files with stack of images
            % used in evaluate segmentation function
            meta = imfinfo(filename);
            data = zeros([meta(1).Height, meta(1).Width, numel(meta)], 'uint8');
            for sliceId = 1:numel(meta)
                data(:, :, sliceId) = imread(filename, 'Index', sliceId);
            end
        end

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

        %         function img = loadAndTransposeImages(filename)
        %             img = mibLoadImages(filename);
        %             img = permute(img, [1 2 4 3]);  % transpose from [h,w,c,z] to [h,w,z,c]
        %         end
    end

    methods
        % declaration of functions in the external files, keep empty line in between for the doc generator

        bioformatsCallback(obj, event) % update available filename extensions upon press of the BioFormats checkbox
        
        closeWindow(obj)        % callback on closing of DeepMIB window
        
        [lgraph, outputPatchSize] = createNetwork(obj, previewSwitch) % generate network

        net = generateDeepLabV3Network(obj, imageSize, numClasses, targetNetwork) % generate DeepLab v3+ convolutional neural network for semantic image segmentation of 2D RGB images

        net = generate3DDeepLabV3Network(obj, imageSize, numClasses, downsamplingFactor, targetNetwork) % generate DeepLab v3+ convolutional neural network for semantic image segmentation of 2D RGB images

        [net, outputSize] = generateUnet2DwithEncoder(obj, imageSize, encoderNetwork) % enerate Unet convolutional neural network for semantic image segmentation of 2D RGB images using a specified encoder

        [patchOut, info, augList, augPars] = mibDeepAugmentAndCrop3dPatchMultiGPU(patchIn, info, inputPatchSize, outputPatchSize, mode, options) % augment patches for 3D in multi-gpu mode

        [patchOut, info, augList, augPars] = mibDeepAugmentAndCrop2dPatchMultiGPU(patchIn, info, inputPatchSize, outputPatchSize, mode, options) %  augment patches for 2D in multi-gpu mode

        TrainingOptions = preprareTrainingOptionsInstances(obj, valDS);     % prepare options for training of instance segmentation network

        function obj = MibDeep(mibModel, varargin)
            obj.mibModel = mibModel;    % assign model
            obj.mibController = varargin{1};

            %% fill the BatchOpt structure with default values
            % fields of the structure should correspond to the starting
            % text in the each widget tooltip.
            % For example, this demo template has an edit box, where the
            % tooltip starts with "Parameter:...". Text Parameter
            % indicates field of the BatchOpt structure that defines value
            % for this widget

            obj.TrainEngine = 'trainNetwork'; % original training engine

            % define available architectures
            workflowsList = {'2D Semantic', '2.5D Semantic', '3D Semantic', '2D Patch-wise', '2D Instance'};
            architectureList{1} = {'DeepLab v3+', 'SegNet', 'U-net', 'U-net +Encoder'};
            %architectureList{2} = {'3DC + DLv3 Resnet18', 'Z2C + DLv3 Resnet18', 'Z2C + DLv3 Resnet50', 'Z2C + U-net', 'Z2C + U-net +Encoder'};
            architectureList{2} = {'Z2C + DLv3', 'Z2C + U-net', 'Z2C + U-net +Encoder'}; % 3DC + DLv3 Resnet18'
            architectureList{3} = {'U-net', 'U-net Anisotropic'};
            architectureList{4} = {'Resnet18', 'Resnet50', 'Resnet101', 'Xception'};
            architectureList{5} = {'SOLOv2'};
            obj.availableArchitectures = containers.Map(workflowsList, architectureList);
            % define list of encoders for different architectures
            %workflowsArchList = {'2D Semantic DeepLab v3+', '2D Semantic U-net +Encoder', '2D Instance SOLOv2', '2.5D Semantic Z2C + U-net +Encoder', '2.5D Semantic Z2C + DLv3'};
            encodersList{1} = {'Resnet18', 'Resnet50', 'Xception', 'InceptionResnetv2', 1}; % for '2D Semantic DeepLab v3+'
            encodersList{2} = {'Classic', 'Resnet18', 'Resnet50', 2}; % for '2D Semantic U-net +Encoder'
            encodersList{3} = {'Resnet18', 'Resnet50', 1}; % for '2D Instance SOLOv2''
            encodersList{4} = {'Classic', 'Resnet18', 'Resnet50', 2}; % for '2D Semantic U-net +Encoder'
            encodersList{5} = {'Resnet18', 'Resnet50', 1}; % for '2.5D Semantic Z2C + DLv3'
            workflowsArchList = ["2D Semantic DeepLab v3+", "2D Semantic U-net +Encoder", "2D Instance SOLOv2", ...
                "2.5D Semantic Z2C + U-net +Encoder", "2.5D Semantic Z2C + DLv3"];
            %obj.availableEncoders = dictionary(workflowsArchList, encodersList); % dictionary available only from R2022b
            obj.availableEncoders = containers.Map(workflowsArchList, encodersList);

            obj.BatchOpt.NetworkFilename = fullfile(obj.mibModel.currentDirectory, 'myLovelyNetwork.mibDeep');
            obj.BatchOpt.Workflow = {'2D Semantic'};
            obj.BatchOpt.Workflow{2} = workflowsList;
            obj.BatchOpt.Architecture = {'DeepLab v3+'};
            obj.BatchOpt.Architecture{2} = obj.availableArchitectures('2D Semantic');
            % 2D Semantic: {'U-net', 'SegNet', 'DLv3 Resnet18'}
            % 2.5D Semantic: {'3DC + DLv3 Resnet18', 'Z2C + U-net', 'Z2C + DLv3 Resnet18', 'Z2C + DLv3 Resnet50'}
            % 3D Semantic: {'U-net', '3D U-net Anisotropic'}
            % 2D Patch-wise: {'Resnet18', 'Resnet50', 'Resnet101', 'Xception'}
            obj.BatchOpt.Mode = {'Train'};
            obj.BatchOpt.Mode{2} = {'Train', 'Predict'};
            obj.BatchOpt.T_EncoderNetwork = {'Resnet18'};
            obj.BatchOpt.T_EncoderNetwork{2} = {'Classic', 'Resnet18', 'Resnet50'};
            obj.BatchOpt.T_ConvolutionPadding = {'same'};
            obj.BatchOpt.T_ConvolutionPadding{2} = {'same', 'valid'};
            obj.BatchOpt.T_InputPatchSize = '256 256 1 1';
            obj.BatchOpt.T_NumberOfClasses{1} = 2;
            obj.BatchOpt.T_NumberOfClasses{2} = [1 Inf];
            obj.BatchOpt.T_SegmentationLayer = {'dicePixelCustomClassificationLayer'};
            if verLessThan('matlab','9.8')  % 'focalLossLayer' - is available from R2020a
                obj.BatchOpt.T_SegmentationLayer{2} = {'pixelClassificationLayer', 'dicePixelClassificationLayer', 'dicePixelCustomClassificationLayer'};
            else
                obj.BatchOpt.T_SegmentationLayer{2} = {'pixelClassificationLayer', 'focalLossLayer', 'dicePixelClassificationLayer', 'dicePixelCustomClassificationLayer'};
            end
            obj.BatchOpt.T_ActivationLayer = {'reluLayer'};
            obj.BatchOpt.T_ActivationLayer{2} = {'clippedReluLayer', 'eluLayer', 'leakyReluLayer', 'reluLayer', 'swishLayer', 'tanhLayer'};
            obj.BatchOpt.T_EncoderDepth{1} = 3;
            obj.BatchOpt.T_EncoderDepth{2} = [1 Inf];
            obj.BatchOpt.T_NumFirstEncoderFilters{1} = 32;
            obj.BatchOpt.T_NumFirstEncoderFilters{2} = [1 Inf];
            obj.BatchOpt.T_FilterSize{1} = 3;
            obj.BatchOpt.T_FilterSize{2} = [3 Inf];
            obj.BatchOpt.T_UseImageNetWeights = false;
            obj.BatchOpt.T_PatchesPerImage{1} = 1;
            obj.BatchOpt.T_PatchesPerImage{2} = [1 Inf];
            obj.BatchOpt.T_MiniBatchSize{1} = obj.mibModel.preferences.Deep.MiniBatchSize;
            obj.BatchOpt.T_MiniBatchSize{2} = [1 Inf];
            obj.BatchOpt.T_augmentation = true;
            obj.BatchOpt.T_ExportTrainingPlots = true;
            obj.BatchOpt.T_SaveProgress = false;
            obj.BatchOpt.UseParallelComputing = false;
            obj.BatchOpt.T_RandomGeneratorSeed{1} = obj.mibModel.preferences.Deep.RandomGeneratorSeed;  % random seed generator for training
            obj.BatchOpt.T_RandomGeneratorSeed{2} = [0 Inf];
            obj.BatchOpt.T_RandomGeneratorSeed{3} = true;

            obj.BatchOpt.Bioformats = false;    % use bioformats file reader for prediction images
            obj.BatchOpt.BioformatsTraining = false;    % use bioformats file reader for training images
            obj.BatchOpt.BioformatsTrainingIndex{1} = 1;    % index of a serie to be used with bio-formats reader for training
            obj.BatchOpt.BioformatsTrainingIndex{2} = [1 Inf];
            obj.BatchOpt.BioformatsTrainingIndex{3} = true;
            obj.BatchOpt.BioformatsIndex{1} = 1; % index of a serie to be used with bio-formats reader for prediction
            obj.BatchOpt.BioformatsIndex{2} = [1 Inf];
            obj.BatchOpt.BioformatsIndex{3} = true;

            obj.BatchOpt.SingleModelTrainingFile = false;    % use single model file with the model
            obj.BatchOpt.ModelFilenameExtension = {'MODEL'};    % extension for model files
            obj.BatchOpt.ModelFilenameExtension{2} = {'MODEL', 'PNG', 'TIF', 'TIFF'};
            obj.BatchOpt.MaskFilenameExtension = {'MASK'};      % extension for mask files
            obj.BatchOpt.MaskFilenameExtension{2} = {'USE 0-s IN LABELS', 'MASK', 'PNG', 'TIF', 'TIFF'};

            if strcmp(obj.mibModel.preferences.Deep.OriginalTrainingImagesDir, '\')
                obj.BatchOpt.OriginalTrainingImagesDir = obj.mibModel.currentDirectory;
                obj.BatchOpt.OriginalPredictionImagesDir = obj.mibModel.currentDirectory;
                obj.BatchOpt.ResultingImagesDir = obj.mibModel.currentDirectory;
            else
                obj.BatchOpt.OriginalTrainingImagesDir = obj.mibModel.preferences.Deep.OriginalTrainingImagesDir;
                obj.BatchOpt.OriginalPredictionImagesDir = obj.mibModel.preferences.Deep.OriginalPredictionImagesDir;
                obj.BatchOpt.ResultingImagesDir = obj.mibModel.preferences.Deep.ResultingImagesDir;
            end
            obj.BatchOpt.ImageFilenameExtension = obj.mibModel.preferences.Deep.ImageFilenameExtension;
            obj.BatchOpt.ImageFilenameExtension{2} = upper(obj.mibModel.extensionRegistryLoad.getAllowedExtensions('Standard', 'Default', false)); % {'AM', 'PNG', 'TIF'};
            obj.BatchOpt.ImageFilenameExtensionTraining = obj.mibModel.preferences.Deep.ImageFilenameExtension;
            obj.BatchOpt.ImageFilenameExtensionTraining{2} = upper(obj.mibModel.extensionRegistryLoad.getAllowedExtensions('Standard', 'Default', false)); % {'AM', 'PNG', 'TIF'};

            obj.BatchOpt.PreprocessingMode = {'Preprocessing is not required'};
            obj.BatchOpt.PreprocessingMode{2} = {'Training', 'Prediction', 'Training and Prediction', 'Preprocessing is not required', 'Split files for training/validation'};
            obj.BatchOpt.CompressProcessedImages = obj.mibModel.preferences.Deep.CompressProcessedImages;
            obj.BatchOpt.CompressProcessedModels = obj.mibModel.preferences.Deep.CompressProcessedModels;

            obj.BatchOpt.NormalizeImages = false;
            obj.BatchOpt.ValidationFraction{1} = obj.mibModel.preferences.Deep.ValidationFraction;
            obj.BatchOpt.ValidationFraction{2} = [0 1];
            obj.BatchOpt.ValidationFraction{3} = false;
            obj.BatchOpt.RandomGeneratorSeed{1} = obj.mibModel.preferences.Deep.RandomGeneratorSeed;
            obj.BatchOpt.RandomGeneratorSeed{2} = [0 Inf];
            obj.BatchOpt.RandomGeneratorSeed{3} = true;
            obj.BatchOpt.MaskAway = false;

            obj.BatchOpt.P_OverlappingTiles = true;
            obj.BatchOpt.P_OverlappingTilesPercentage{1} = 5;
            obj.BatchOpt.P_OverlappingTilesPercentage{2} = [1 100];
            obj.BatchOpt.P_OverlappingTilesPercentage{3} = true;
            obj.BatchOpt.P_PredictionMode = {'Blocked-image'};
            obj.BatchOpt.P_PredictionMode{2} = {'Blocked-image', 'Legacy'};
            obj.BatchOpt.P_ModelFiles = {'MIB Model format'};
            obj.BatchOpt.P_ModelFiles{2} = {'MIB Model format', 'TIF compressed format', 'TIF uncompressed format'};
            obj.BatchOpt.P_ScoreFiles = {'Use AM format'};
            obj.BatchOpt.P_ScoreFiles{2} = {'Do not generate', 'Use AM format', 'Use Matlab non-compressed format', 'Use Matlab compressed format', 'Use Matlab non-compressed format (range 0-1)'};
            obj.BatchOpt.P_ExtraPaddingPercentage{1} = 0;
            obj.BatchOpt.P_ExtraPaddingPercentage{2} = [0 100];
            obj.BatchOpt.P_ExtraPaddingPercentage{3} = false;
            obj.BatchOpt.P_ImageDownsamplingFactor{1} = 1;
            obj.BatchOpt.P_ImageDownsamplingFactor{2} = [1 Inf];
            obj.BatchOpt.P_ImageDownsamplingFactor{3} = false;
            obj.BatchOpt.P_MiniBatchSize{1} = 1;
            obj.BatchOpt.P_MiniBatchSize{2} = [1 Inf];
            obj.BatchOpt.P_MiniBatchSize{3} = true;
            obj.BatchOpt.P_PatchWiseUpsample = false;
            obj.BatchOpt.P_DynamicMasking = false;

            obj.BatchOpt.O_CustomTrainingProgressWindow = true;
            obj.BatchOpt.O_RefreshRateIter{1} = 5;
            obj.BatchOpt.O_RefreshRateIter{2} = [1 Inf];
            obj.BatchOpt.O_RefreshRateIter{3} = true;
            obj.BatchOpt.O_NumberOfPoints{1} = 1000;
            obj.BatchOpt.O_NumberOfPoints{2} = [50 Inf];
            obj.BatchOpt.O_NumberOfPoints{3} = true;
            obj.BatchOpt.O_PreviewImagePatches = true;
            obj.BatchOpt.O_FractionOfPreviewPatches{1} = .02;
            obj.BatchOpt.O_FractionOfPreviewPatches{2} = [0 1];

            obj.BatchOpt.showWaitbar = true;

            %% part below is only valid for use of the plugin from MIB batch controller
            % comment it if intended use not from the batch mode
            obj.BatchOpt.mibBatchSectionName = 'Menu -> Ribbon';    % section name for the Batch
            obj.BatchOpt.mibBatchActionName = 'DeepMIB';           % name of the plugin
            % tooltips that will accompany the BatchOpt
            obj.BatchOpt.mibBatchTooltip.NetworkFilename = 'Network filename, a new filename for training or existing filename for prediction';
            obj.BatchOpt.mibBatchTooltip.Workflow = 'Targeted workflow to perform';
            obj.BatchOpt.mibBatchTooltip.Architecture = 'Architecture of the network';
            obj.BatchOpt.mibBatchTooltip.T_EncoderNetwork = 'Select backbone to modify the encoder part of the network';
            obj.BatchOpt.mibBatchTooltip.T_ConvolutionPadding = '"same": zero padding is applied to the inputs to convolution layers such that the output and input feature maps are the same size; "valid" - zero padding is not applied; the output feature map is smaller than the input feature map';
            obj.BatchOpt.mibBatchTooltip.Mode = 'Use tool in the training or prediction mode';
            obj.BatchOpt.mibBatchTooltip.T_InputPatchSize = 'Network input image size as [height width depth colors]';
            obj.BatchOpt.mibBatchTooltip.T_NumberOfClasses = 'Number of classes in the model including Exterior';
            obj.BatchOpt.mibBatchTooltip.T_ActivationLayer = 'Replace default activation layer with any one from this list';
            obj.BatchOpt.mibBatchTooltip.T_SegmentationLayer = 'Define the type of the last (segmentation) layer of the network';
            obj.BatchOpt.mibBatchTooltip.T_EncoderDepth = 'The depth of the network determines the number of times the input volumetric image is downsampled or upsampled during processing';
            obj.BatchOpt.mibBatchTooltip.T_NumFirstEncoderFilters = 'Number of output channels for the first encoder stage';
            obj.BatchOpt.mibBatchTooltip.T_FilterSize = 'Convolutional layer filter size, specified as a positive odd integer';
            obj.BatchOpt.mibBatchTooltip.T_UseImageNetWeights = 'Init the network with imagenet weights [MATLAB version of MIB only]';
            obj.BatchOpt.mibBatchTooltip.T_PatchesPerImage = 'Number of patches to extract from each image';
            obj.BatchOpt.mibBatchTooltip.T_MiniBatchSize = 'Number of observations that are returned in each batch';
            obj.BatchOpt.mibBatchTooltip.T_augmentation = 'Augment images during training';
            obj.BatchOpt.mibBatchTooltip.T_ExportTrainingPlots = 'When ticked, export training scores to files, which are placed to Results\ScoreNetwork folder';
            obj.BatchOpt.mibBatchTooltip.T_SaveProgress = 'When ticked the network progress is saved to Results\ScoreNetwork folder';
            obj.BatchOpt.mibBatchTooltip.OriginalTrainingImagesDir = 'Specify directory with original images and models. The images and models should be placed under "Images" and "Labels" subfolders correspondingly';
            obj.BatchOpt.mibBatchTooltip.OriginalPredictionImagesDir = 'Specify directory with original images for prediction';
            obj.BatchOpt.mibBatchTooltip.ImageFilenameExtension = 'Filename extension of original images used for prediction';
            obj.BatchOpt.mibBatchTooltip.ImageFilenameExtensionTraining = 'Filename extension of original images used for traininig';
            obj.BatchOpt.mibBatchTooltip.BioformatsTraining = 'Use Bioformats file reader for training images';
            obj.BatchOpt.mibBatchTooltip.BioformatsTrainingIndex = 'Index of a serie to be used with bio-formats reader or with TIFs for training';
            obj.BatchOpt.mibBatchTooltip.Bioformats = 'Use Bioformats file reader for prediction images';
            obj.BatchOpt.mibBatchTooltip.BioformatsIndex = 'Index of a serie to be used with bio-formats reader or with TIFs for prediction';
            obj.BatchOpt.mibBatchTooltip.ResultingImagesDir = 'Specify directory for resulting images for preprocessing and prediction, the following subfolders are used: TrainImages, TrainLabels, ValidationImages, ValidationLabels, PredictionImages';
            obj.BatchOpt.mibBatchTooltip.NormalizeImages = 'Normalize images during preprocessing, or use original images';
            obj.BatchOpt.mibBatchTooltip.CompressProcessedImages = 'Compression of images slows down performance but saves space';
            obj.BatchOpt.mibBatchTooltip.CompressProcessedModels = 'Compression of models slows down performance but saves space';
            obj.BatchOpt.mibBatchTooltip.PreprocessingMode = 'Preprocess images for prediction or training by splitting the datasets for training and validation';
            obj.BatchOpt.mibBatchTooltip.ValidationFraction = 'Fraction of images used for validation during training';
            obj.BatchOpt.mibBatchTooltip.RandomGeneratorSeed = 'Seed for random number generator used during splitting of test and validation datasets';
            obj.BatchOpt.mibBatchTooltip.T_RandomGeneratorSeed = 'Seed for random number generator used during initialization of training. Use 0 for random initialization each time or any other number for reproducibility';
            obj.BatchOpt.mibBatchTooltip.MaskAway = 'Mask away areas that should not be used for training, requires MIB *.mask files under Mask subfolder for preprocessing or use of 0s (Exterior) to specify mask out areas in models';
            obj.BatchOpt.mibBatchTooltip.SingleModelTrainingFile = 'When checked a single Model file with labels is used, when unchecked each image should have a corresponding model file with labels';
            obj.BatchOpt.mibBatchTooltip.ModelFilenameExtension = 'Extension for model filenames with labels, the files should be placed under "Labels" subfolder';
            obj.BatchOpt.mibBatchTooltip.MaskFilenameExtension = 'Extension for mask filenames, the files should be placed under "Masks" subfolder; when "Use 0-s IN LABELS" is selected mask is encoded with 0-indices, no preprocessing is required';
            obj.BatchOpt.mibBatchTooltip.P_MiniBatchSize = 'Number of patches processed simultaneously during prediction, increasing the MiniBatchSize value increases the efficiency, but it also takes up more GPU memory';
            obj.BatchOpt.mibBatchTooltip.P_OverlappingTiles = 'The ooverlapping tiles mode can be used with "same" padding. It is slower but in general expected to give better predictions';
            obj.BatchOpt.mibBatchTooltip.P_OverlappingTilesPercentage = 'Overlap percentage between tiles when predicting with the Overlapping tiles mode';
            obj.BatchOpt.mibBatchTooltip.P_ExtraPaddingPercentage = 'Add symmetric padding to images for prediction; it helps to minimize edge artefacts';
            obj.BatchOpt.mibBatchTooltip.P_ImageDownsamplingFactor = 'Downsample images by this number of times before prediction, [default=1, no downsampling]; for 2 classes predictions are also smoothed';
            obj.BatchOpt.mibBatchTooltip.P_DynamicMasking = 'When enabled, the images for predictions are thresholded to detect masked areas where segmentation occurs';
            obj.BatchOpt.mibBatchTooltip.P_PredictionMode = 'Main processing mode for prediction, the blocked image mode is recommended';
            obj.BatchOpt.mibBatchTooltip.P_ScoreFiles = 'tweak generation of score files showing probability of each class';
            obj.BatchOpt.mibBatchTooltip.P_ModelFiles = 'define output type for generated model files during prediction';
            obj.BatchOpt.mibBatchTooltip.P_PatchWiseUpsample = 'upsample generated patch predictions to match resolution of underlying images for direct comparison';
            obj.BatchOpt.mibBatchTooltip.O_CustomTrainingProgressWindow = 'When checked the custom progress plot is displayed during training, instead of Matlab default plot';
            obj.BatchOpt.mibBatchTooltip.O_RefreshRateIter = 'Refresh rate of the training progress window in iterations. Decrease for more frequent refresh, increase to speed up training performance';
            obj.BatchOpt.mibBatchTooltip.O_NumberOfPoints = 'Number of points in the training plot. Decrease to improve training performance, increase to see more detailed plot';
            obj.BatchOpt.mibBatchTooltip.O_PreviewImagePatches = 'Preview image patches that network is seeing with the cost of decreased training performance';
            obj.BatchOpt.mibBatchTooltip.O_FractionOfPreviewPatches = 'Fraction of image patches that has to be visualized. Decrease to improve performance, increase to see patches more frequently';

            obj.BatchOpt.mibBatchTooltip.showWaitbar = sprintf('Show or not waitbar');

            obj.AugOpt2D = obj.mibModel.preferences.Deep.AugOpt2D;
            obj.AugOpt3D = obj.mibModel.preferences.Deep.AugOpt3D;
            if isfield(obj.mibModel.preferences.Deep, 'PatchPreviewOpt')
                obj.PatchPreviewOpt = obj.mibModel.preferences.Deep.PatchPreviewOpt;
            else
                obj.PatchPreviewOpt.noImages = 9;         % number of images in montage
                obj.PatchPreviewOpt.imageSize = 160;         % patch image size for preview
                obj.PatchPreviewOpt.labelShow = true;   % display overlay labels with details
                obj.PatchPreviewOpt.labelSize = 9;      % font size for the label
                obj.PatchPreviewOpt.labelColor = 'black'; % color of the label
                obj.PatchPreviewOpt.labelBgColor = 'yellow'; % color of the label background
                obj.PatchPreviewOpt.labelBgOpacity = 0.6;   % opacity of the background
            end

            obj.InputLayerOpt = obj.mibModel.preferences.Deep.InputLayerOpt;
            obj.TrainingOpt = obj.mibModel.preferences.Deep.TrainingOpt;
            if ~isfield(obj.TrainingOpt, 'GradientDecayFactor')     % add new fields in MIB 2.71
                obj.TrainingOpt.GradientDecayFactor = 0.9;
                obj.TrainingOpt.SquaredGradientDecayFactor = 0.9;
                obj.TrainingOpt.ValidationPatience = Inf;
            end
            % dynamic masking and score export properties
            obj.DynamicMaskOpt = obj.mibModel.preferences.Deep.DynamicMaskOpt;
            obj.ScoreExportOpt = obj.mibModel.preferences.Deep.ScoreExportOpt;

            if isfield(obj.mibModel.preferences.Deep, 'ActivationLayerOpt')
                obj.ActivationLayerOpt = obj.mibModel.preferences.Deep.ActivationLayerOpt;
            else
                obj.ActivationLayerOpt.clippedReluLayer.Ceiling = 10;
                obj.ActivationLayerOpt.leakyReluLayer.Scale = 0.01;
                obj.ActivationLayerOpt.eluLayer.Alpha = 1;
            end

            if isfield(obj.mibModel.preferences.Deep, 'SegmentationLayerOpt')
                obj.SegmentationLayerOpt = obj.mibModel.preferences.Deep.SegmentationLayerOpt;
            else
                obj.SegmentationLayerOpt.focalLossLayer.Alpha = 0.25;
                obj.SegmentationLayerOpt.focalLossLayer.Gamma = 2;
                obj.mibModel.preferences.Deep.SegmentationLayerOpt.dicePixelCustom.ExcludeExerior = false;
            end

            % sending reports settings
            obj.SendReports = obj.mibModel.preferences.Deep.SendReports;

            obj.TrainingProgress = struct;
            obj.Aug2DFuncNames = [];    % names of augmentation functions for 2D
            obj.Aug3DFuncNames = [];    % names of augmentation functions for 3D
            obj.childControllers = {};    % initialize child controllers
            obj.childControllersIds = {};
            obj.gpuInfoFig = [];    % gpu info window
            obj.sessionSettings = struct();

            % set of default material colors for models
            obj.modelMaterialColors = [166 67 33; 71 178 126; 79 107 171; 150 169 213; 26 51 111; 255 204 102; 230 25 75; 255 225 25; 0 130 200; 245 130 48; 145 30 180; 70 240 240; 240 50 230; 210 245 60; 250 190 190; 0 128 128; 230 190 255; 170 110 40; 255 250 200; 128 0 0; 170 255 195; 128 128 0; 255 215 180; 0 0 128; 128 128 128; 60 180 75]/255;

            %% add here a code for the batch mode, for example
            % when the BatchOpt stucture is provided the controller will
            % use it as the parameters, and performs the function in the
            % headless mode without GUI
            if nargin == 3
                BatchOptIn = varargin{2};
                if isstruct(BatchOptIn) == 0
                    if isnan(BatchOptIn)     % when varargin{2} == NaN return possible settings
                        obj.returnBatchOpt();   % obtain Batch parameters
                    else
                        errorOpts.mibPath = obj.mibModel.mibPath;
                        errorOpts.WindowHeight = 150;
                        utils.dlgs.showErrorDialog([], sprintf('A structure as the 3rd parameter is required!'), 'Error', 'Error in controllers.MibDeep', '', errorOpts);
                    end
                    notify(obj, 'CloseEvent');
                    return
                end
                % add/update BatchOpt with the provided fields in BatchOptIn
                % combine fields from input and default structures
                obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptIn);

                obj.start();
                notify(obj, 'CloseEvent');
                return;
            end

            guiName = 'views.MibDeepGUI';
            obj.view = core.ChildView(obj, guiName); % initialize the view

            % update font and size
            % you may need to replace "obj.view.handles.text1" with tag of any text field of your own GUI
            % update font and size
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.Workflow.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.Workflow.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            % move the window to the left hand side of the main window
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');

            obj.updateWidgets();

            % update widgets from the BatchOpt structure
            obj.view = utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);

            obj.view.handles.PreprocessingParForWorkers.Limits = [0 obj.mibModel.cpuParallelLimitMax];
            obj.view.handles.PreprocessingParForWorkers.Value = obj.mibModel.cpuParallelLimitMax;

            % generate colormaps
            obj.colormap6 = [166 67 33; 71 178 126; 79 107 171; 150 169 213; 26 51 111; 255 204 102 ]/255;
            obj.colormap20 = [230 25 75; 255 225 25; 0 130 200; 245 130 48; 145 30 180; 70 240 240; 240 50 230; 210 245 60; 250 190 190; 0 128 128; 230 190 255; 170 110 40; 255 250 200; 128 0 0; 170 255 195; 128 128 0; 255 215 180; 0 0 128; 128 128 128; 60 180 75]/255;
            obj.colormap255 = rand([255,3]);

            obj.view.Figure.Figure.Visible = 'on';
            
            % add listner to obj.mibModel and call controller function as a callback
            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) obj.viewListner_Callback(obj, src, evnt));    % listen changes in number of ROIs
           
            if gpuDeviceCount == 0
                obj.view.Figure.GPUDropDown.Items = {'CPU only', 'Parallel'};
                mgsOpt.MsgBoxOnly = true;
                mgsOpt.Header     = sprintf('You do not have compatible CUDA card or driver,\nwithout those the training will be extrelemy slow!');
                utils.dlgs.inputUniversalDlg(obj.view.gui, {}, {}, 'Warning', mgsOpt);
            else
                clear gpuList;
                for deviceId = 1:gpuDeviceCount
                    gpuInfo = gpuDevice(deviceId);
                    gpuList{deviceId} = sprintf('%d. %s', deviceId, gpuInfo.Name); %#ok<AGROW>
                end
                if gpuDeviceCount > 1
                    gpuList{end+1} = 'Multi-GPU';
                end
                gpuList = [gpuList, {'CPU only'}, {'Parallel'}];
                obj.view.Figure.GPUDropDown.Items = gpuList;
                obj.view.Figure.GPUDropDown.Value = gpuList{1};
                gpuDevice(1);   % select 1st device
            end
        end

    end
end
