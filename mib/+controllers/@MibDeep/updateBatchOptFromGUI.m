function updateBatchOptFromGUI(obj, event)
    % function updateBatchOptFromGUI(obj, event)
    %
    % update obj.BatchOpt from widgets of GUI
    % use an external function (utils\updateBatchOptFromGUI_Shared.m) that is common for all tools
    % compatible with the Batch mode
    %
    % Parameters:
    % event: event from the callback

    obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);

    switch event.Source.Tag
        case 'P_PredictionMode'
            switch event.Source.Value
                case 'Blocked-image'
                    obj.view.handles.P_DynamicMasking.Enable = 'on';
                case 'Legacy'
                    obj.view.handles.P_DynamicMasking.Enable = 'off';
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
    end
end

