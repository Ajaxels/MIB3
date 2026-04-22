function selectArchitecture(obj, event)
% function selectArchitecture(obj, event)
% select the target architecture

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
obj.view.handles.P_OverlappingTiles.Enable = 'on';
obj.view.handles.P_OverlappingTilesPercentage.Enable = 'on';
obj.view.handles.P_PatchWiseUpsample.Enable = 'off';
obj.view.handles.P_ExtraPaddingPercentage.Enable = 'on';
obj.view.handles.T_EncoderNetwork.Enable = 'off';
obj.view.handles.T_NumAnisotropicBlocks.Enable = 'off';

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
end

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
end

