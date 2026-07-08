function TrainingOptions = preprareTrainingOptionsInstances(obj, valDS)
% PREPRARETRAININGOPTIONSINSTANCES - prepare trainig options for training of the instance segmentation network.
%
% Syntax:
%   .. code-block:: matlab
%
%       TrainingOptions = obj.preprareTrainingOptionsInstances(valDS)
%
% Input Arguments:
%   - **valDS** — datastore with images for validation
%

global mibDeepTrainingProgressStruct

TrainingOptions = struct();

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
            executionEnvironment = 'cpu'; %#ok<*NASGU>
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
        "'ResetInputNormalization', false,"
        "'MiniBatchSize', obj.BatchOpt.T_MiniBatchSize{1},"
        "'CheckpointPath', CheckpointPath,"
        "'ExecutionEnvironment', executionEnvironment,"
        ], ' ');

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
                trainingProgressOptions.calculateAccuracy = obj.BatchOpt.O_CalculateAccuracyInstances;   % whether the validation mAP metric is computed
                trainingProgressOptions.sendNextReportAtEpoch = -1;   % next epoch value to send training report
                if obj.SendReports.T_SendReports && obj.SendReports.sendDuringRun
                    trainingProgressOptions.sendNextReportAtEpoch = obj.TrainingOpt.CheckpointFrequency+1; % the value is taken from the checkpoint frequency
                    trainingProgressOptions.sendReportToEmail = obj.SendReports.TO_email;
                end

                evalTrainingOptions = join([evalTrainingOptions
                    "'OutputFcn', @(info)deepmib.customTrainingProgressDisplay(info, trainingProgressOptions),"
                    ], ' ');
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
                trainingProgressOptions.calculateAccuracy = obj.BatchOpt.O_CalculateAccuracyInstances;   % whether the validation mAP metric is computed
                trainingProgressOptions.sendNextReportAtEpoch = -1;   % next epoch value to send training report
                if obj.SendReports.T_SendReports && obj.SendReports.sendDuringRun
                    trainingProgressOptions.sendNextReportAtEpoch = obj.TrainingOpt.CheckpointFrequency+1; % the value is taken from the checkpoint frequency
                    trainingProgressOptions.sendReportToEmail = obj.SendReports.TO_email;
                end

                evalTrainingOptions = join([evalTrainingOptions
                    "'OutputFcn', @(info)deepmib.customTrainingProgressDisplay(info, trainingProgressOptions),"
                    ], ' ');

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
            "'OutputFcn', @deepmib.stopTrainingWithoutPlots,"
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

        % trainSOLOV2 never computes a training-time accuracy metric (only Loss/ClsLoss/
        % MaskLoss), but it accepts mAPInstanceSegmentationMetric as a ValidationOnly metric
        % (see trainSOLOV2.m); this feeds the "ValidationmAP" field into the custom progress
        % display (deepmib.customTrainingProgressDisplay), which maps it onto the Validation
        % accuracy gauge as a percentage. Only add it when validation data is present -
        % ValidationOnly metrics error out otherwise.
        % Computing mAP additionally runs the detector in inference mode over the whole
        % validation set every validation interval (plus IoU matching / mAP integration) - a
        % notable extra cost. Skip the metric entirely when the user disables accuracy
        % calculation via the "Calculate accuracy" checkbox (BatchOpt.O_CalculateAccuracyInstances);
        % validation loss is still computed and plotted.
        if obj.BatchOpt.O_CalculateAccuracyInstances
            evalTrainingOptions = join([evalTrainingOptions
                "'Metrics', {mAPInstanceSegmentationMetric()},"
                ], ' ');
        end
    end

    % add output network selection method
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

    % add frequency of checkpoint generations
    if obj.BatchOpt.T_SaveProgress
        evalTrainingOptions = join([evalTrainingOptions
            "'CheckpointFrequency', obj.TrainingOpt.CheckpointFrequency,"
            ], ' ');
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
