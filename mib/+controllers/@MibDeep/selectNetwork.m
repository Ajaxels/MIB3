function net = selectNetwork(obj, networkName)
    % function net = selectNetwork(obj, networkName)
    % select a filename for a new network in the Train mode, or
    % select a network to use for the Predict mode
    %
    % Parameters:
    % networkName: optional parameter with the network full filename
    %
    % Return values:
    % net: trained network

    if nargin < 2; networkName = '';  end
    net = [];

    switch obj.BatchOpt.Mode{1}
        case 'Predict'
            if isempty(networkName)
                [file, path] = mib_uigetfile({'*.mibDeep;', 'Deep MIB network files (*.mibDeep)';
                    '*.mat', 'Mat files (*.mat)'}, 'Open network file', ...
                    obj.BatchOpt.NetworkFilename);
                if isequal(file , 0); return; end
                networkName = fullfile(path, file{1});
            end
            if exist(networkName, 'file') ~= 2
                mgsOpt.MsgBoxOnly = true;
                header = sprintf('The provided file does not exist!\n\n%s', networkName);
                utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Wrong network name', mgsOpt);
                
                obj.view.Figure.NetworkFilename.Value = obj.BatchOpt.NetworkFilename;
                % the two following commands are fix of sending the DeepMIB
                % window behind main MIB window
                drawnow;
                figure(obj.view.gui);
                return;
            end

            obj.wb = uiprogressdlg(obj.view.gui, 'Message', sprintf('Loading the network\nPlease wait...'), ...
                'Title', 'Load network');

            res = load(networkName, '-mat');     % loading 'net', 'TrainingOptions', 'classNames' variables
            net = res.net;   % generate output network

            % update waitbar
            obj.wb.Value = 0.5;

            % add/update BatchOpt with the provided fields in BatchOptIn
            % combine fields from input and default structures
            res.BatchOpt = rmfield(res.BatchOpt, ...
                {'NetworkFilename', 'Mode', 'OriginalTrainingImagesDir', 'OriginalPredictionImagesDir', ...
                'ResultingImagesDir', 'PreprocessingMode', 'CompressProcessedImages', 'showWaitbar', ...
                'mibBatchSectionName', 'mibBatchActionName', 'mibBatchTooltip'});

            % update res.BatchOpt to be compatible with DeepMIB v2.83
            res = obj.correctBatchOpt(res);
            obj.BatchOpt = updateBatchOptCombineFields_Shared(obj.BatchOpt, res.BatchOpt);

            try
                if isfield(res.AugOpt2DStruct, 'ImageBlur') == 0
                    importFields = fieldnames(res.AugOpt2DStruct);
                    for fieldId = 1:length(importFields)
                        obj.AugOpt2D.(importFields{fieldId}) = res.AugOpt2DStruct.(importFields{fieldId});
                    end
                    mgsOpt.MsgBoxOnly = true;
                    header = sprintf('You are loading an old config file with a smaller number of augmentation options.\nThe loaded settings were merged with the current ones!');
                    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Merge augmentation settings', mgsOpt);
                else
                    obj.AugOpt2D = mibConcatenateStructures(obj.AugOpt2D, res.AugOpt2DStruct);
                end
                obj.TrainingOpt = mibConcatenateStructures(obj.TrainingOpt, res.TrainingOptStruct);
                if strcmp(obj.TrainingOpt.Plots, 'training-progress-Matlab'); obj.TrainingOpt.Plots = 'training-progress'; end
                obj.InputLayerOpt = mibConcatenateStructures(obj.InputLayerOpt, res.InputLayerOpt);
                obj.AugOpt3D = mibConcatenateStructures(obj.AugOpt3D, res.AugOpt3DStruct);

                if ~isfield(obj.TrainingOpt, 'GradientDecayFactor')     % add new fields in MIB 2.71
                    obj.TrainingOpt.GradientDecayFactor = 0.9;
                    obj.TrainingOpt.SquaredGradientDecayFactor = 0.9;
                    obj.TrainingOpt.ValidationPatience = Inf;
                end
            catch err
                % when the training was stopped before finish,
                % those structures are not stored
            end

            obj.updateWidgets();

            obj.wb.Value = 1;
            delete(obj.wb);
        case {'Train', 'Preprocess'}
            if isempty(networkName)
                [file, path] = uiputfile({'*.mibDeep', 'mibDeep files (*.mibDeep)';
                    '*.mat', 'Mat files (*.mat)'}, 'Select network file', ...
                    obj.BatchOpt.NetworkFilename);
                if file == 0; return; end
                networkName = fullfile(path, file);
            else
                if exist(networkName, 'file') == 2
                    choice = questdlg(sprintf('!!! Warning !!!\n\nThe provided file already exist!\n\n%s\n\nWould you like to overwrite it for new training?', networkName), 'File exists!', 'Overwrite', 'Cancel', 'Cancel');
                    if strcmp(choice, 'Cancel')
                        obj.view.Figure.NetworkFilename.Value = obj.BatchOpt.NetworkFilename;
                        return;
                    end
                end
            end
    end
    obj.BatchOpt.NetworkFilename = networkName;
    obj.view.Figure.NetworkFilename.Value = obj.BatchOpt.NetworkFilename;
    % the two following commands are fix of sending the DeepMIB
    % window behind main MIB window
    drawnow;
    figure(obj.view.gui);
end

