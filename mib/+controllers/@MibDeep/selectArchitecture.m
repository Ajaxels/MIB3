function selectArchitecture(obj, event)
% SELECTARCHITECTURE - select the target architecture.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.selectArchitecture(event)
%
% Input Arguments:
%   - **event** *(optional)* - event of the Architecture dropdown. It is passed only when the
%     user picks an architecture; :func:`loadConfig` and :func:`selectWorkflow` call without it.
%
% When the user picks StarDist in the 2D Instance workflow (``event`` given) and the current
% "Network filename" is not already a StarDist network (no ``StarDistConfig`` in the file),
% a dialog offers to create a network file from the pretrained model with
% :func:`createStarDistFromPretrained`, so it can be used for prediction without training.
% Loading a config or a network never shows it.
%
% "Downsample factor for images" (``P_ImageDownsamplingFactor``) is set per architecture:
% limits ``[1 Inf]`` and enabled with the Blocked-image prediction mode for the semantic
% workflows; disabled for SOLOv2, which ignores it; enabled with limits ``[0.1 Inf]`` and a
% StarDist tooltip for StarDist, which predicts on the image resized by ``1 / factor`` (see
% :func:`startPredictionInstances`). The limits and the tooltip are stored in ``BatchOpt``
% (``{2}`` and ``mibBatchTooltip``) as well, because updateWidgets re-applies them from there;
% a value below the new lower limit is raised to it. :func:`updateBatchOptFromGUI` keeps the
% 2D Instance state when the prediction mode changes.

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDeep.selectArchitecture: triggered\n');
end

pickedByUser = nargin >= 2;
if nargin < 2; event.Source = obj.view.handles.Architecture; end
obj.updateBatchOptFromGUI(event);

obj.view.handles.ModelFilenameExtension.Enable = 'on';
obj.view.handles.SingleModelTrainingFile.Enable = 'on';

obj.view.handles.T_EncoderNetwork.Enable = 'off';
obj.view.handles.T_EncoderDepth.Enable = 'on';
obj.view.handles.T_NumFirstEncoderFilters.Enable = 'on';
obj.view.handles.T_FilterSize.Enable = 'on';
obj.view.handles.T_ConvolutionPadding.Enable = 'on';
obj.view.handles.T_EncoderDepth.Enable = 'on';
obj.view.handles.T_PatchesPerImage.Enable = 'on';
obj.view.handles.T_SegmentationLayer.Enable = 'on';
obj.view.handles.T_ActivationLayer.Enable = 'on';
obj.view.handles.T_NumberOfClasses.Enable = 'on';
obj.view.handles.InputLayerSettings.Enable = 'on';
% the two "settings" buttons only apply to some layer types, so re-derive their state
% from the current selection instead of forcing them on
obj.activationLayerChangeCallback();
obj.setSegmentationLayer();
obj.view.handles.P_OverlappingTiles.Enable = 'on';
obj.view.handles.P_OverlappingTilesPercentage.Enable = 'on';
obj.view.handles.P_PatchWiseUpsample.Enable = 'off';
obj.view.handles.P_OverlapInstancesMode.Enable = 'off';
obj.view.handles.P_OverlapInstancesSettings.Enable = 'off';
obj.view.handles.P_OverlapInstancesSettings.Tooltip = 'Instance stitching settings';   % as in MibDeepGUI.mlapp; StarDist changes it below
obj.view.handles.P_mergeInstancesTo3D.Enable = 'off';
obj.view.handles.O_CalculateAccuracyInstances.Enable = 'off';
obj.view.handles.P_ExtraPaddingPercentage.Enable = 'on';
obj.view.handles.T_EncoderNetwork.Enable = 'off';
obj.view.handles.T_NumAnisotropicBlocks.Enable = 'off';
% "Downsample factor for images": the blocked-image prediction of the semantic workflows
% downsamples by it (enabled per prediction mode, as P_PredictionModeValueChanged of
% MibDeepGUI.mlapp does); 2D Instance sets its own state below
if strcmp(obj.BatchOpt.P_PredictionMode{1}, 'Blocked-image')
    obj.view.handles.P_ImageDownsamplingFactor.Enable = 'on';
else
    obj.view.handles.P_ImageDownsamplingFactor.Enable = 'off';
end
downsamplingLimits = [1 Inf];
obj.BatchOpt.mibBatchTooltip.P_ImageDownsamplingFactor = 'Downsample images by this number of times before prediction, [default=1, no downsampling]; for 2 classes predictions are also smoothed';   % as in the MibDeep constructor

obj.TrainEngine = 'trainNetwork'; % original method

switch obj.BatchOpt.Workflow{1}
    case '2D Semantic'
        obj.view.handles.SingleModelTrainingFile.Enable = 'on';
        switch obj.BatchOpt.Architecture{1}
            case {'DeepLab v3+'}
                obj.view.handles.T_EncoderDepth.Enable = 'off';
                obj.view.handles.T_EncoderDepth.Value = 4;
                obj.BatchOpt.T_EncoderDepth{1} = 4;
                obj.view.handles.T_NumFirstEncoderFilters.Enable = 'off';
                obj.view.handles.T_FilterSize.Enable = 'off';
                obj.view.handles.T_EncoderNetwork.Enable = 'on';
            case 'SegNet'
                if obj.view.handles.SingleModelTrainingFile.Value == false
                    obj.view.handles.ModelFilenameExtension.Enable = 'on';
                end
                obj.view.Figure.T_ConvolutionPadding.Value = 'same';
                obj.view.Figure.T_ConvolutionPadding.Enable = 'off';
                obj.BatchOpt.T_ConvolutionPadding{1} = 'same';
            case 'U-net'
                obj.view.handles.SingleModelTrainingFile.Enable = 'on';
                if obj.view.handles.SingleModelTrainingFile.Value == false
                    obj.view.handles.ModelFilenameExtension.Enable = 'on';
                end
            case 'U-net +Encoder'
                obj.view.handles.T_EncoderNetwork.Enable = 'on';
                obj.view.handles.SingleModelTrainingFile.Enable = 'on';
                if obj.view.handles.SingleModelTrainingFile.Value == false
                    obj.view.handles.ModelFilenameExtension.Enable = 'on';
                end
                obj.TrainEngine = 'trainnet'; % new method for dlnetwork
        end
    case '2.5D Semantic'
        obj.view.handles.SingleModelTrainingFile.Enable = 'on';
        switch obj.BatchOpt.Architecture{1}
            case {'3DC + DLv3 Resnet18'}
                obj.view.handles.T_EncoderDepth.Enable = 'off';
                obj.view.handles.T_EncoderDepth.Value = 4;
                obj.BatchOpt.T_EncoderDepth{1} = 4;
            case {'Z2C + DLv3'}
                obj.view.handles.T_EncoderDepth.Enable = 'off';
                obj.view.handles.T_EncoderDepth.Value = 4;
                obj.BatchOpt.T_EncoderDepth{1} = 4;
                obj.view.handles.T_NumFirstEncoderFilters.Enable = 'off';
                obj.view.handles.T_EncoderNetwork.Enable = 'on';
            case {'Z2C + U-net'}
                obj.view.handles.T_EncoderDepth.Enable = 'on';
                obj.view.handles.T_EncoderDepth.Value = 3;
                obj.BatchOpt.T_EncoderDepth{1} = 3;
            case {'Z2C + U-net +Encoder'}
                obj.view.handles.T_EncoderDepth.Enable = 'on';
                obj.view.handles.T_EncoderDepth.Value = 3;
                obj.BatchOpt.T_EncoderDepth{1} = 3;
                obj.view.handles.T_EncoderNetwork.Enable = 'on';
        end
        obj.view.handles.SingleModelTrainingFile.Enable = 'off';
        obj.view.handles.SingleModelTrainingFile.Value = false;
    case '3D Semantic'
        obj.view.handles.SingleModelTrainingFile.Value = true;
        event2.Source = obj.view.handles.SingleModelTrainingFile;
        obj.singleModelTrainingFileValueChanged(event2);    % callback for press of Single MIB model checkbox
        obj.view.handles.SingleModelTrainingFile.Enable = 'off';
        obj.BatchOpt.SingleModelTrainingFile = false;
        obj.view.handles.T_NumAnisotropicBlocks.Enable = 'on';
    case '2D Patch-wise'
        % preprocessing tab
        obj.view.handles.MaskAway.Enable = 'off';
        obj.view.handles.MaskFilenameExtension.Enable = 'off';
        obj.view.handles.NumberOfClassesPreprocessing.Enable = 'on';

        % Train tab settings
        obj.view.handles.T_ConvolutionPadding.Enable = 'off';
        obj.view.handles.T_ConvolutionPadding.Value = 'same';
        obj.BatchOpt.T_ConvolutionPadding{1} = 'same';
        obj.view.handles.T_EncoderDepth.Enable = 'off';
        obj.view.handles.T_PatchesPerImage.Enable = 'off';
        obj.view.handles.T_SegmentationLayer.Enable = 'off';

        % Prediction tab settings
        obj.view.handles.P_PatchWiseUpsample.Enable = 'on';
        obj.view.handles.P_ExtraPaddingPercentage.Enable = 'off';
    case '2D Instance'
        obj.view.handles.T_EncoderNetwork.Enable = 'on';

        % The network comes ready-made from solov2(detectorName, ...), so none of the
        % layer-level design settings are read by startTrainingInstances - leaving them
        % editable suggests an influence they do not have. The values are left untouched:
        % nothing in the instance path reads them (instance training hardcodes
        % classNames = {'object'}, and processImages routes 2D Instance to
        % processImagesForInstanceSegmentation before the class-count code is reached), so
        % overwriting them would only destroy the settings of the user's semantic projects
        obj.view.handles.T_EncoderDepth.Enable = 'off';
        obj.view.handles.T_NumFirstEncoderFilters.Enable = 'off';
        obj.view.handles.T_FilterSize.Enable = 'off';
        obj.view.handles.T_ActivationLayer.Enable = 'off';
        obj.view.handles.T_ActivationLayerSettings.Enable = 'off';
        obj.view.handles.T_SegmentationLayer.Enable = 'off';
        obj.view.handles.T_SegmentationLayerSettings.Enable = 'off';
        obj.view.handles.T_NumberOfClasses.Enable = 'off';
        % SOLOv2 does its own input preprocessing; obj.InputLayerOpt is never applied
        obj.view.handles.InputLayerSettings.Enable = 'off';

        % Options tab settings
        obj.view.handles.O_CalculateAccuracyInstances.Enable = 'on';
        % Prediction tab settings
        obj.view.handles.P_OverlapInstancesMode.Enable = 'on';
        obj.view.handles.P_OverlapInstancesSettings.Enable = 'on';
        obj.view.handles.P_mergeInstancesTo3D.Enable = 'on';
        % instance prediction does not depend on the prediction mode, and SOLOv2 ignores the
        % downsampling factor; StarDist enables it below
        obj.view.handles.P_ImageDownsamplingFactor.Enable = 'off';

        if strcmp(obj.BatchOpt.Architecture{1}, 'StarDist')
            % StarDist has no exchangeable encoder; its design settings (rays, grid) are
            % behind the settings button of "Starting weights", see setStarDistSettings
            obj.view.handles.T_EncoderNetwork.Enable = 'off';
            % the mAP metric is computed by the SOLOv2 trainer; StarDist reports its
            % accuracy when the thresholds are tuned after training
            obj.view.handles.O_CalculateAccuracyInstances.Enable = 'off';
            % StarDist tiles the probability and distance maps, not the instances, so there
            % is no cross-tile stitching to configure, and the tile overlap follows from the
            % receptive field of the network (deepmib.stardist.predictMaps); the settings
            % button opens the StarDist prediction settings instead
            obj.view.handles.P_OverlapInstancesMode.Enable = 'off';
            obj.view.handles.P_OverlappingTiles.Enable = 'off';
            obj.view.handles.P_OverlappingTilesPercentage.Enable = 'off';
            obj.view.handles.P_OverlapInstancesSettings.Tooltip = 'StarDist prediction settings: detection thresholds and tile size';
            % StarDist predicts on the image resized by 1 / factor (startPredictionInstances),
            % so objects of another size than in the training images can be found; values
            % below 1 enlarge the image, for objects smaller than in the training images
            obj.view.handles.P_ImageDownsamplingFactor.Enable = 'on';
            downsamplingLimits = [0.1 Inf];
            obj.BatchOpt.mibBatchTooltip.P_ImageDownsamplingFactor = ['StarDist: resize images by 1/factor before prediction, ' ...
                'results at the original size; 2D_versatile_fluo expects nuclei of about 20 pixels: ' ...
                'use diameter of your nuclei / 20; own network: 1'];
            obj.TrainEngine = 'trainnet';
        end
end
% the limits are kept in BatchOpt too, because updateWidgets re-applies them from there
if obj.BatchOpt.P_ImageDownsamplingFactor{1} < downsamplingLimits(1)
    obj.BatchOpt.P_ImageDownsamplingFactor{1} = downsamplingLimits(1);
end
obj.BatchOpt.P_ImageDownsamplingFactor{2} = downsamplingLimits;
obj.view.handles.P_ImageDownsamplingFactor.Limits = downsamplingLimits;
obj.view.handles.P_ImageDownsamplingFactor.Value = obj.BatchOpt.P_ImageDownsamplingFactor{1};
obj.view.handles.P_ImageDownsamplingFactor.Tooltip = obj.BatchOpt.mibBatchTooltip.P_ImageDownsamplingFactor;

if strcmp(obj.BatchOpt.T_ConvolutionPadding{1}, 'valid')
    obj.view.Figure.P_OverlappingTiles.Enable = 'off';
    obj.view.Figure.P_OverlappingTilesPercentage.Enable = 'off';
end

% update encoders list
encoderKeyValue = [obj.BatchOpt.Workflow{1} ' ' obj.BatchOpt.Architecture{1}];
if isKey(obj.availableEncoders, encoderKeyValue)
    if isa(obj.availableEncoders, 'containers.Map')
        encodersList = obj.availableEncoders(encoderKeyValue);
        obj.BatchOpt.T_EncoderNetwork{2} = encodersList(1:end-1); % as the last value is the selected encoder
        obj.BatchOpt.T_EncoderNetwork{1} = encodersList{encodersList{end}}; % as the last value is the selected encoder
        obj.view.handles.T_EncoderNetwork.Items = obj.BatchOpt.T_EncoderNetwork{2};
        obj.view.handles.T_EncoderNetwork.Value = obj.BatchOpt.T_EncoderNetwork{1};
    else % dictionary
        obj.BatchOpt.T_EncoderNetwork{2} = obj.availableEncoders{encoderKeyValue}(1:end-1); % as the last value is the selected encoder
        obj.BatchOpt.T_EncoderNetwork{1} = obj.availableEncoders{encoderKeyValue}{obj.availableEncoders{encoderKeyValue}{end}}; % as the last value is the selected encoder
        obj.view.handles.T_EncoderNetwork.Items = obj.BatchOpt.T_EncoderNetwork{2};
        obj.view.handles.T_EncoderNetwork.Value = obj.BatchOpt.T_EncoderNetwork{1};
    end
end

% the possible starting weights depend on the encoder too, so refresh after the
% encoder list above has been settled
obj.updateStartingWeightsList();

if pickedByUser && strcmp(obj.BatchOpt.Workflow{1}, '2D Instance') && strcmp(obj.BatchOpt.Architecture{1}, 'StarDist')
    % a StarDist network is already selected: nothing to offer
    networkIsStarDist = false;
    if isfile(obj.BatchOpt.NetworkFilename)
        try
            networkIsStarDist = ~isempty(whos('-file', obj.BatchOpt.NetworkFilename, 'StarDistConfig'));
        catch
            % not a MAT-file: treated as no StarDist network
        end
    end
    if networkIsStarDist; return; end
    selection = uiconfirm(obj.view.gui, sprintf(['The pretrained StarDist model 2D_versatile_fluo segments nuclei ' ...
        'in fluorescence images and can be used for prediction directly, without training.\n\n' ...
        'It was trained on nuclei of about 20 pixels in diameter (most between 10 and 50). For larger or ' ...
        'smaller nuclei set "Downsample factor for images" on the Predict tab to about diameter of your ' ...
        'nuclei / 20, for example 2 for nuclei of 40 pixels or 0.5 for nuclei of 10 pixels.\n\n' ...
        'Create a network file from it now? This is also available later in the StarDist settings ' ...
        '(the button next to "Starting weights").']), 'StarDist', ...
        'Options', {'Create network from pretrained', 'Train my own'}, 'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'info');
    if strcmp(selection, 'Create network from pretrained')
        obj.createStarDistFromPretrained();
    end
end
end

