function TrainingOptions = preprareTrainingOptions(obj, valDS)
% function TrainingOptions = preprareTrainingOptions(obj, valDS)
% prepare trainig options for the network training
%
% Parameters:
% valDS: datastore with images for validation

global mibDeepTrainingProgressStruct

TrainingOptions = struct();

%% Specify Training Options
% update ResetInputNormalization when obj.InputLayerOpt.Mean,
% .StandardDeviation, .Min, .Max are defined
ResetInputNormalization = true; %#ok<*NASGU>
switch obj.InputLayerOpt.Normalization
    case 'zerocenter'
        if ~isempty(obj.InputLayerOpt.Mean); ResetInputNormalization = false; end
    case 'zscore'
        if ~isempty(obj.InputLayerOpt.Mean) && ~isempty(obj.InputLayerOpt.StandardDeviation); ResetInputNormalization = false; end
    case {'rescale-symmetric', 'rescale-zero-one'}
        if ~isempty(obj.InputLayerOpt.Min) && ~isempty(obj.InputLayerOpt.Max); ResetInputNormalization = false; end
    case 'none'

end

verboseSwitch = false;
if strcmp(obj.TrainingOpt.Plots, 'none')
    verboseSwitch = true;   % drop message into the command window when the plots are disabled
    mibDeepTrainingProgressStruct.useCustomProgressPlot = 0;
else
    mibDeepTrainingProgressStruct.useCustomProgressPlot = obj.BatchOpt.O_CustomTrainingProgressWindow;
end

if isdeployed
    PlotsSwitch = 'none';
else
    if mibDeepTrainingProgressStruct.useCustomProgressPlot
        PlotsSwitch = 'none';
    else
        PlotsSwitch = obj.TrainingOpt.Plots;
    end
end

CheckpointPath = '';
if obj.BatchOpt.T_SaveProgress
    CheckpointPath = fullfile(obj.BatchOpt.ResultingImagesDir, 'ScoreNetwork');
end

try
    % select gpu or cpu for training
    % and define executionEnvironment
    selectedIndex = find(ismember(obj.view.Figure.GPUDropDown.Items, obj.view.Figure.GPUDropDown.Value));
    switch obj.view.Figure.GPUDropDown.Value
        case 'CPU only'
            if numel(obj.view.Figure.GPUDropDown.Items) > 2 % i.e. GPU is present
                gpuDevice([]);  % CPU only mode
            end
            executionEnvironment = 'cpu';
        case 'Multi-GPU'
            executionEnvironment = 'multi-gpu';
        case 'Parallel'
            executionEnvironment = 'parallel';
        otherwise
            gpuDevice(selectedIndex);   % choose selected GPU device
            executionEnvironment = 'gpu';
    end

    % recalculate validation frequency from epochs to
    % interations
    ValidationFrequencyInIterations = ceil(mibDeepTrainingProgressStruct.iterPerEpoch / obj.TrainingOpt.ValidationFrequency);

    evalTrainingOptions = join([
        "TrainingOptions = trainingOptions(obj.TrainingOpt.solverName,"
        "'MaxEpochs', obj.TrainingOpt.MaxEpochs,"
        "'Shuffle', obj.TrainingOpt.Shuffle,"
        "'InitialLearnRate', obj.TrainingOpt.InitialLearnRate,"
        "'LearnRateSchedule', obj.TrainingOpt.LearnRateSchedule,"
        "'LearnRateDropPeriod', obj.TrainingOpt.LearnRateDropPeriod,"
        "'LearnRateDropFactor', obj.TrainingOpt.LearnRateDropFactor,"
        "'L2Regularization', obj.TrainingOpt.L2Regularization,"
        "'Plots', PlotsSwitch,"
        "'Verbose', verboseSwitch,"
        "'ResetInputNormalization', ResetInputNormalization,"
        "'MiniBatchSize', obj.BatchOpt.T_MiniBatchSize{1},"
        "'CheckpointPath', CheckpointPath,"
        "'ExecutionEnvironment', executionEnvironment,"
        ], ' ');

    % Accuracy metric is only used in the classification tasks
    % for semantic segmentation tasks TrainAccuracy is empty
    if strcmp(obj.TrainEngine, 'trainnet')
        evalTrainingOptions = join([evalTrainingOptions, ...
            "'Metrics', 'accuracy',"
            ], ' ');
    end

    % if strcmp(obj.TrainEngine, 'trainnet')
    %     evalTrainingOptions = join([evalTrainingOptions, ...
    %         "'Metrics', 'rmse',"
    %         ], ' ');
    % end

    if mibDeepTrainingProgressStruct.useCustomProgressPlot
        % add output function and dispatch in background option
        switch obj.view.Figure.GPUDropDown.Value
            case {'Multi-GPU', 'Parallel'}
                trainingProgressOptions = struct();
                trainingProgressOptions.O_NumberOfPoints = obj.BatchOpt.O_NumberOfPoints{1};
                trainingProgressOptions.NetworkFilename = obj.BatchOpt.NetworkFilename;
                trainingProgressOptions.noColorChannels = str2num(obj.BatchOpt.T_InputPatchSize);
                trainingProgressOptions.noColorChannels = trainingProgressOptions.noColorChannels(4);
                trainingProgressOptions.Workflow = obj.BatchOpt.Workflow{1};
                trainingProgressOptions.Architecture = obj.BatchOpt.Architecture{1};
                trainingProgressOptions.refreshRateIter = obj.BatchOpt.O_RefreshRateIter{1};
                trainingProgressOptions.matlabVersion = obj.mibController.matlabVersion;
                trainingProgressOptions.gpuDevice = obj.view.Figure.GPUDropDown.Value;
                trainingProgressOptions.iterPerEpoch = mibDeepTrainingProgressStruct.iterPerEpoch;
                trainingProgressOptions.TrainingOpt = obj.TrainingOpt;
                trainingProgressOptions.sendNextReportAtEpoch = -1;   % next epoch value to send training report
                if obj.SendReports.T_SendReports && obj.SendReports.sendDuringRun
                    trainingProgressOptions.sendNextReportAtEpoch = obj.TrainingOpt.CheckpointFrequency+1; % the value is taken from the checkpoint frequency
                    trainingProgressOptions.sendReportToEmail = obj.SendReports.TO_email;
                end

                switch obj.TrainEngine
                    case 'trainNetwork'
                        evalTrainingOptions = join([evalTrainingOptions
                            "'OutputFcn', @(info)mibDeepCustomTrainingProgressDisplay(info, trainingProgressOptions),"
                            ], ' ');
                    case 'trainnet'
                        evalTrainingOptions = join([evalTrainingOptions
                            "'OutputFcn', @(info)mibDeepCustomTrainingProgressDisplayTrainNet(info, trainingProgressOptions),"
                            ], ' ');
                end
            otherwise
                trainingProgressOptions = struct();
                trainingProgressOptions.O_NumberOfPoints = obj.BatchOpt.O_NumberOfPoints{1};
                trainingProgressOptions.NetworkFilename = obj.BatchOpt.NetworkFilename;
                trainingProgressOptions.noColorChannels = str2num(obj.BatchOpt.T_InputPatchSize);
                trainingProgressOptions.noColorChannels = trainingProgressOptions.noColorChannels(4);
                trainingProgressOptions.Workflow = obj.BatchOpt.Workflow{1};
                trainingProgressOptions.Architecture = obj.BatchOpt.Architecture{1};
                trainingProgressOptions.refreshRateIter = obj.BatchOpt.O_RefreshRateIter{1};
                trainingProgressOptions.matlabVersion = obj.mibController.matlabVersion;
                trainingProgressOptions.gpuDevice = obj.view.Figure.GPUDropDown.Value;
                trainingProgressOptions.iterPerEpoch = mibDeepTrainingProgressStruct.iterPerEpoch;
                trainingProgressOptions.TrainingOpt = obj.TrainingOpt;
                trainingProgressOptions.sendNextReportAtEpoch = -1;   % next epoch value to send training report
                if obj.SendReports.T_SendReports && obj.SendReports.sendDuringRun
                    trainingProgressOptions.sendNextReportAtEpoch = obj.TrainingOpt.CheckpointFrequency+1; % the value is taken from the checkpoint frequency
                    trainingProgressOptions.sendReportToEmail = obj.SendReports.TO_email;
                end

                switch obj.TrainEngine
                    case 'trainNetwork'
                        evalTrainingOptions = join([evalTrainingOptions
                            "'OutputFcn', @(info)mibDeepCustomTrainingProgressDisplay(info, trainingProgressOptions),"
                            ], ' ');
                    case 'trainnet'
                        evalTrainingOptions = join([evalTrainingOptions
                            "'OutputFcn', @(info)mibDeepCustomTrainingProgressDisplayTrainNet(info, trainingProgressOptions),"
                            ], ' ');
                end

                % testing DispatchInBackground
                % compatible only with matlab progress plot and
                % with the console only
                % par dispatch was about the same time as
                % normal training

                % evalTrainingOptions = join([evalTrainingOptions
                %    "'DispatchInBackground', false,"
                %    ], ' ');

        end
    else
        evalTrainingOptions = join([evalTrainingOptions
            "'OutputFcn', @mibDeepStopTrainingWithoutPlots,"
            ], ' ');
    end

    % define solver specific settings
    switch obj.TrainingOpt.solverName
        case 'adam'
            evalTrainingOptions = join([evalTrainingOptions
                "'GradientDecayFactor', obj.TrainingOpt.GradientDecayFactor,"
                "'SquaredGradientDecayFactor', obj.TrainingOpt.SquaredGradientDecayFactor,"
                ], ' ');
        case 'rmsprop'
            evalTrainingOptions = join([evalTrainingOptions
                "'SquaredGradientDecayFactor', obj.TrainingOpt.SquaredGradientDecayFactor,"
                ], ' ');
        case 'sgdm'
            evalTrainingOptions = join([evalTrainingOptions
                "'Momentum', obj.TrainingOpt.Momentum,"
                ], ' ');
    end

    % add validation store
    if ~isempty(valDS)
        evalTrainingOptions = join([evalTrainingOptions
            "'ValidationData', valDS,"
            "'ValidationFrequency', ValidationFrequencyInIterations,"
            "'ValidationPatience', obj.TrainingOpt.ValidationPatience," ...
            ], ' ');
    end

    % add output network selection method
    if obj.mibController.matlabVersion >= 9.11 % R2021b
        if strcmp(obj.TrainingOpt.OutputNetwork, 'best-validation-loss') && isempty(valDS)
            selection = uiconfirm(obj.view.gui, ...
                sprintf('The current training options have OutputNetwork parameter set to "best-validation-loss" to return the network corresponding to the training iteration with the lowest validation loss.\n\nPlease hit Cancel and provide images for validation (Directories and preprocessing->Fraction of images for validation) and start training again.\n\nAlternatively press "Continue using last-iteration output" to return the network corresponding to the last training iteration.'), ...
                'Missing validation images',...
                'Options',{'Continue using last-iteration output', 'Cancel'}, ...
                'DefaultOption', 'Cancel', ...
                'Icon','warning');
            if strcmp(selection, 'Cancel'); delete(obj.wb); return; end
            obj.TrainingOpt.OutputNetwork = 'last-iteration';
        end

        evalTrainingOptions = join([evalTrainingOptions
            "'OutputNetwork', obj.TrainingOpt.OutputNetwork,"
            ], ' ');
    end

    % add frequency of checkpoint generations
    if obj.mibController.matlabVersion >= 9.12 % R2022a
        if obj.BatchOpt.T_SaveProgress
            evalTrainingOptions = join([evalTrainingOptions
                "'CheckpointFrequency', obj.TrainingOpt.CheckpointFrequency,"
                ], ' ');
        end
    end
    evalTrainingOptions = char(evalTrainingOptions);
    evalTrainingOptions = [evalTrainingOptions(1:end-1), ');'];
    % generate TrainingOptions structure
    eval(evalTrainingOptions);
catch err
    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Wrong training options');
    if obj.BatchOpt.showWaitbar; delete(obj.wb); return; end
end
end

