function updateBatchOptFromGUI(obj, event)
% UPDATEBATCHOPTFROMGUI - update obj.BatchOpt from widgets of GUI.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.updateBatchOptFromGUI(event)
%
% use an external function (utils\updateBatchOptFromGUI_Shared.m) that is common for all tools
% compatible with the Batch mode
%
% Input Arguments:
%   - **event** - event from the callback
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDeep.updateBatchOptFromGUI(%s): triggered\n', event.Source.Tag);
end

    obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);

    switch event.Source.Tag
        case 'ImageFilenameExtension'
            obj.bioformatsCallback(event);     % relabel Index as Level for ZARR
        case 'P_PredictionMode'
            switch event.Source.Value
                case 'Blocked-image'
                    obj.view.handles.P_DynamicMasking.Enable = 'on';
                case 'Legacy'
                    obj.view.handles.P_DynamicMasking.Enable = 'off';
            end
            % MibDeepGUI.mlapp toggles "Downsample factor for images" with the mode; instance
            % prediction ignores the mode, and only StarDist uses the factor (selectArchitecture)
            if strcmp(obj.BatchOpt.Workflow{1}, '2D Instance')
                if strcmp(obj.BatchOpt.Architecture{1}, 'StarDist')
                    obj.view.handles.P_ImageDownsamplingFactor.Enable = 'on';
                else
                    obj.view.handles.P_ImageDownsamplingFactor.Enable = 'off';
                end
            end
        case 'P_ModelFiles'
            % the settings button has options only for the zarr model output
            if strcmp(event.Source.Value, 'Zarr3 (BigData model)')
                obj.view.handles.P_ModelFilesSettings.Enable = 'on';
            else
                obj.view.handles.P_ModelFilesSettings.Enable = 'off';
            end
        case 'T_ConvolutionPadding'
            if strcmp(event.Source.Value, 'same')
                obj.view.Figure.P_OverlappingTiles.Enable = 'on';
                obj.view.Figure.P_OverlappingTilesPercentage.Enable = 'on';
            else    % valid
                obj.view.Figure.P_OverlappingTiles.Enable = 'off';
                obj.view.Figure.P_OverlappingTiles.Value = false;
                obj.BatchOpt.P_OverlappingTiles = false;
                obj.view.Figure.P_OverlappingTilesPercentage.Enable = 'off';
            end
        case 'T_EncoderNetwork'
            selectedEncoder = obj.BatchOpt.T_EncoderNetwork{1};
            encoderKeyValue = [obj.BatchOpt.Workflow{1} ' ' obj.BatchOpt.Architecture{1}];
            if isKey(obj.availableEncoders, encoderKeyValue)
                if isa(obj.availableEncoders, 'containers.Map')
                    encodersList = obj.availableEncoders(encoderKeyValue);
                    selectedEncoderValue = find(ismember(encodersList(1:end-1), selectedEncoder));
                    obj.availableEncoders(encoderKeyValue) = [encodersList(1:end-1) {selectedEncoderValue}];
                else % dictionary
                    obj.availableEncoders{encoderKeyValue}{end} = find(ismember(obj.availableEncoders{encoderKeyValue}(1:end-1), selectedEncoder));
                end
            end
            % "U-net +Encoder" starts from random weights with the 'Classic' encoder and
            % from pretrained ones with the Resnet encoders, so the starting weights list
            % has to follow the encoder as well as the workflow/architecture
            obj.updateStartingWeightsList();
        case 'T_StartingWeights'
            % only the two-phase schedule has settings to configure, so the button next
            % to the dropdown follows the selection
            obj.updateStartingWeightsList();
    end
end

