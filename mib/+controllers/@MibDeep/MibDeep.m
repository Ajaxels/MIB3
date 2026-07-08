classdef MibDeep < handle
% MIBDEEP - @type MibDeep class is a template class for using with.
%
% GUI developed using appdesigner of Matlab
%
%
% .. code-block:: matlab
%
%   obj.mibController.startController('controllers.MibDeep', obj.mibController);; // as GUI tool
%
% or
%
% .. code-block:: matlab
%
%   // a code below was used for mibImageArithmeticController
%   BatchOpt.Parameter = 'test'mib;  // fill edit boxes as strings
%   BatchOpt.Checkbox = true;     // fill checkboxes with logicals: true/false
%   BatchOpt.Popup = {'value'};        // value for the popups as a cell
%   BatchOpt.Radio = {'Radio1'};          // selection of radio buttons, as cell with the handle of the target radio button
%   BatchOpt.showWaitbar = true;  // show or not the waitbar
%   obj.startController('MibDeep', [], BatchOpt); // start MibDeep in the batch mode
%
% or
%
% .. code-block:: matlab
%
%   // trigger return of the possible Options using returnBatchOpt function
%   // using notify syncBatch event
%   obj.startController('MibDeep', [], NaN);

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
        OverlapInstancesOpt
        % options for stitching of instances across tiles during 2D Instance prediction
        % (the stitching mode itself is in BatchOpt.P_OverlapInstancesMode)
        % .DetectionThreshold = 0.5;  % confidence threshold of segmentObjects [both overlap modes]
        % .MergeIoU = 0.5;   % in-band intersection-over-union to merge detections ['IoU merge' mode]
        % .MergeIoA = 0.8;   % in-band intersection-over-smaller-area to merge detections ['IoU merge' mode]
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
            % TIF3DFILEREAD - data = tif3DFileRead(filename).
            %
            % Syntax:
            %   function data = tif3DFileRead(filename)
            %
            % custom reading function to load tif files with stack of images
            % used in evaluate segmentation function
            meta = imfinfo(filename);
            data = zeros([meta(1).Height, meta(1).Width, numel(meta)], 'uint8');
            for sliceId = 1:numel(meta)
                data(:, :, sliceId) = imread(filename, 'Index', sliceId);
            end
        end

        %         function img = loadAndTransposeImages(filename)
        %             img = mibLoadImages(filename);
        %             img = permute(img, [1 2 4 3]);  % transpose from [h,w,c,z] to [h,w,z,c]
        %         end
    end

    methods
        % declaration of functions in the external files, keep empty line in between for the doc generator
        activationLayerChangeCallback(obj)        % callback for modification of the Activation Layer dropdown
        balanceClasses(obj)        % balance classes before training
        bioformatsCallback(obj, event) % update available filename extensions upon press of the BioFormats checkbox
        imgOut = channelWisePreProcess(obj, imgIn)        % function imgOut = channelWisePreProcess(obj, imgIn)
        checkNetwork(obj, fn)        % generate and check network using settings in the Train tab
        closeWindow(obj)        % callback on closing of DeepMIB window
        res = correctBatchOpt(obj, res)        % correct loaded BatchOpt structure if it is not compatible with the current version of DeepMIB
        countLabels(obj)        % count occurrences of labels in model files callback for press of the "Count labels" in the Options panel
        [lgraph, outputPatchSize] = createNetwork(obj, previewSwitch) % generate network
        customTrainingProgressWindow_Callback(obj, event)        % callback for click on obj.view.handles.O_CustomTrainingProgressWindow checkbox
        duplicateConfigAndNetwork(obj)        % copy the network file and its config to a new filename
        evaluateSegmentation(obj)        % evaluate segmentation results by comparing predicted models with the ground truth models
        evaluateSegmentationPatches(obj)        % evaluate segmentation results for the patches in the patch-wise mode
        exploreActivations(obj)        % [MOVE TO THE BUTTON CALLBACK] explore activations within the trained network
        exportNetwork(obj)        % convert and export network to ONNX or TensorFlow formats
        net = generateDeepLabV3Network(obj, imageSize, numClasses, targetNetwork)% generate DeepLab v3+ convolutional neural network for semantic image segmentation of 2D RGB images
        net = generate3DDeepLabV3Network(obj, imageSize, numClasses, downsamplingFactor, targetNetwork) % generate DeepLab v3+ convolutional neural network for semantic image segmentation of 2D RGB images
        [net, outputSize] = generateUnet2DwithEncoder(obj, imageSize, encoderNetwork) % enerate Unet convolutional neural network for semantic image segmentation of 2D RGB images using a specified encoder
        bls = generateDynamicMaskingBlocks(obj, vol, blockSize, noColors)        % generate blocks using dynamic masking parameters acquired in obj.DynamicMaskOpt
        gpuInfo(obj)        % display information about the selected GPU
        helpButton_callback(obj)        % show Help sections
        importNetwork(obj)        % import an externally trained or designed network to be used with DeepMIB
        loadConfig(obj, configName)        % load config file with Deep MIB settings
        TrainingOptions = preprareTrainingOptions(obj, valDS)        % prepare trainig options for the network training
        TrainingOptions = preprareTrainingOptionsInstances(obj, valDS);     % prepare options for training of instance segmentation network
        previewDynamicMask(obj)        % preview results for the dynamic mode
        previewImagePatches_Callback(obj, event)        % callback for value change of obj.view.handles.O_PreviewImagePatches
        previewModels(obj, loadImagesSwitch)        % load images for predictions and the resulting models into MIB
        previewPredictions(obj)        % load images of prediction scores into MIB
        [cancelled, outputLabels, scoreImg] = processBlocksBlockedImage(obj, vol, zValue, net, inputPatchSize, outputPatchSize, blockSize, padShift, dataDimension, patchwiseWorkflowSwitch, patchwisePatchesPredictSwitch, classNames, generateScoreFiles, executionEnvironment, fn, progressDlg) % process image as patches using the blockmode    
        processImages(obj, preprocessFor)        % Preprocess images for training and prediction
        processImagesForInstanceSegmentation(obj, preprocessFor)        % Preprocess labels for 2D instance segmentation for training and prediction
        returnBatchOpt(obj, BatchOptOut)        % return structure with Batch Options and possible configurations via the notify 'SyncBatch' event
        saveCheckpointNetworkCheck(obj)        % callback for press of Save checkpoint networks (obj.view.handles.T_SaveProgress)
        saveConfig(obj, filename)        % save Deep MIB configuration to a file
        selectArchitecture(obj, event)        % select the target architecture
        selectDirerctories(obj, event)        % select directories containing images for training and prediction
        selectGPUDevice(obj)        % select environment for computations
        net = selectNetwork(obj, networkName)        % select a filename for a new network in the Train mode, or select a network to use for the Predict mode
        selectWorkflow(obj, event)        % select deep learning workflow to perform
        sendReportsCallback(obj)        % define parameters for sending progress report to the user's email address
        setActivationLayerOptions(obj)        % update options for the activation layers
        [status, augNumber] = setAugFuncHandles(obj, mode, augOptions)        % define list of 2D/3D augmentation functions
        setAugmentationSettings(obj, mode)        % update settings for augmentation fo 2D images
        setInputLayerSettings(obj)        % update init settings for the input layer of networks
        setSegmentationLayer(obj)        % callback for modification of the Segmentation Layer dropdown
        setSegmentationLayerOptions(obj)        % update options for the activation layers
        setTrainingSettings(obj)        % update settings for training of networks
        singleModelTrainingFileValueChanged(obj, event)        % callback for press of SingleModelTrainingFile
        start(obj, event)        % start calcualtions, depending on the selected tab preprocessing, training, or prediction is initialized
        startPrediction2D(obj)        % predict datasets for 2D taken to a separate function for better performance
        startPredictionInstances(obj)        % predict 2D instance segmentation (SOLOv2) datasets
        startPrediction3D(obj)        % predict datasets for 3D networks taken to a separate to improve performance
        startPredictionBlockedImage(obj)        % predict 2D/3D datasets using the blockedImage class requires R2021a or newer
        startPreprocessing(obj)        % preprocess imaging for training and prediction
        startTraining(obj)        % perform training of the network
        startTrainingInstances(obj)        % perform training of instance segmentation network
        toggleAugmentations(obj)        % callback for press of the T_augmentation checkbox
        transferLearning(obj)        % perform fine-tuning of the loaded network to a different number of classes
        lgraph = updateActivationLayers(obj, lgraph)        % update the activation layers depending on settings in obj.BatchOpt.T_ActivationLayer and obj.ActivationLayerOpt
        updateBatchOptFromGUI(obj, event)       % update obj.BatchOpt from widgets of GUI
        lgraph = updateConvolutionLayers(obj, lgraph)        % update the convolution layers by providing new set of weight initializers
        updateDynamicMaskSettings(obj)        % update settings for calculation of dynamic masks during prediction using blockedimage mode the settings are stored in obj.DynamicMaskOpt
        updateOverlapInstancesSettings(obj)        % update settings for stitching of instances across tiles during 2D Instance prediction, the settings are stored in obj.OverlapInstancesOpt
        updateImageDirectoryPath(obj, event)        % update directories with images for training, prediction and results
        lgraph = updateMaxPoolAndTransConvLayers(obj, lgraph, poolSize)        % update maxPool and TransposedConvolution layers depending on network downsampling factor only for U-net and SegNet
        lgraph = updateNetworkInputLayer(obj, lgraph, inputPatchSize)        % update the input layer settings for lgraph parameters are taken from obj.InputLayerOpt
        updatePreprocessingMode(obj)        % callback for change of selection in the Preprocess for dropdown
        updateScoreExportSettings(obj)        % update export settings for score files
        lgraph = updateSegmentationLayer(obj, lgraph, classNames)        % redefine the segmentation layer of lgraph based on obj.BatchOpt settings
        updateWidgets(obj)        % update widgets of this window
       
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
            architectureList{1} = {'DeepLab v3+', 'SegNet', 'U-net +Encoder'};
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
            obj.BatchOpt.T_NumAnisotropicBlocks{1} = 1;
            obj.BatchOpt.T_NumAnisotropicBlocks{2} = [1 Inf];
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
            obj.BatchOpt.P_OverlapInstancesMode = {'Centroid in core'};   % cross-tile stitching mode for 2D Instance prediction
            obj.BatchOpt.P_OverlapInstancesMode{2} = {'Centroid in core', 'IoU merge'};

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
            obj.BatchOpt.O_CalculateAccuracyInstances = true;

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
            obj.BatchOpt.mibBatchTooltip.T_NumAnisotropicBlocks = 'Number of initial 2D-only downsampling blocks before full 3D convolutions; for anisotropic datasets where Z spacing is coarser than XY (U-net Anisotropic only)';
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
            obj.BatchOpt.mibBatchTooltip.P_OverlapInstancesMode = 'stitching of instances across tiles during 2D Instance prediction: "Centroid in core" - each object is emitted by the tile owning its centroid (overlap must exceed the largest object); "IoU merge" - detections of neighboring tiles are merged when their masks agree in the overlap band (works for objects larger than the overlap)';
            obj.BatchOpt.mibBatchTooltip.O_CustomTrainingProgressWindow = 'When checked the custom progress plot is displayed during training, instead of Matlab default plot';
            obj.BatchOpt.mibBatchTooltip.O_RefreshRateIter = 'Refresh rate of the training progress window in iterations. Decrease for more frequent refresh, increase to speed up training performance';
            obj.BatchOpt.mibBatchTooltip.O_NumberOfPoints = 'Number of points in the training plot. Decrease to improve training performance, increase to see more detailed plot';
            obj.BatchOpt.mibBatchTooltip.O_PreviewImagePatches = 'Preview image patches that network is seeing with the cost of decreased training performance';
            obj.BatchOpt.mibBatchTooltip.O_FractionOfPreviewPatches = 'Fraction of image patches that has to be visualized. Decrease to improve performance, increase to see patches more frequently';
            obj.BatchOpt.mibBatchTooltip.O_CalculateAccuracyInstances = '[2D Instance only] Calculate the validation accuracy (mAP) metric during training; disable to speed up training by skipping the extra inference over the validation set (validation loss is still computed)';

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
            if ~isfield(obj.TrainingOpt, 'GradientThreshold')      % add new fields in MIB 2.85
                obj.TrainingOpt.GradientThreshold = Inf;            % Inf = no clipping (default)
                obj.TrainingOpt.GradientThresholdMethod = 'l2norm'; % recommended for Dice loss
            end
            % dynamic masking and score export properties
            obj.DynamicMaskOpt = obj.mibModel.preferences.Deep.DynamicMaskOpt;
            obj.ScoreExportOpt = obj.mibModel.preferences.Deep.ScoreExportOpt;

            % instance stitching properties
            if isfield(obj.mibModel.preferences.Deep, 'OverlapInstancesOpt')
                obj.OverlapInstancesOpt = obj.mibModel.preferences.Deep.OverlapInstancesOpt;
            else
                obj.OverlapInstancesOpt.DetectionThreshold = 0.5;
                obj.OverlapInstancesOpt.MergeIoU = 0.5;
                obj.OverlapInstancesOpt.MergeIoA = 0.8;
            end

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
            obj.view.handles.PreprocessingParForWorkers.Value = obj.mibModel.preferences.System.cpuParallelLimit;

            % generate colormaps
            obj.colormap6 = [166 67 33; 71 178 126; 79 107 171; 150 169 213; 26 51 111; 255 204 102 ]/255;
            obj.colormap20 = [230 25 75; 255 225 25; 0 130 200; 245 130 48; 145 30 180; 70 240 240; 240 50 230; 210 245 60; 250 190 190; 0 128 128; 230 190 255; 170 110 40; 255 250 200; 128 0 0; 170 255 195; 128 128 0; 255 215 180; 0 0 128; 128 128 128; 60 180 75]/255;
            obj.colormap255 = rand([255,3]);

            % add handle tags to the tooltips
            if obj.mibModel.preferences.System.DeveloperMode
                utils.overrideDescriptions(obj.view.handles, true, 'obj.view.handles');
            end
            % show the gui
            obj.view.Figure.Figure.Visible = 'on';

            % add listner to obj.mibModel and call controller function as a callback
            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) obj.viewListner_Callback(obj, src, evnt));    % listen changes in number of ROIs

            if gpuDeviceCount == 0
                obj.view.Figure.GPUDropDown.Items = {'CPU only', 'Parallel'};
                mgsOpt.MsgBoxOnly = true;
                header     = sprintf('You do not have compatible CUDA card or driver,\nwithout those the training will be extrelemy slow!');
                utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Warning', mgsOpt);
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
