function TrainingOptions = preprareTrainingOptionsInstances(obj, valDS, trainingOptOverrides)
% PREPRARETRAININGOPTIONSINSTANCES - prepare trainig options for training of the instance segmentation network.
%
% Syntax:
%   .. code-block:: matlab
%
%       TrainingOptions = obj.preprareTrainingOptionsInstances(valDS)
%       TrainingOptions = obj.preprareTrainingOptionsInstances(valDS, trainingOptOverrides)
%
% Input Arguments:
%   - **valDS** - datastore with images for validation
%   - **trainingOptOverrides** - *optional* struct whose fields replace the matching fields
%     of ``obj.TrainingOpt`` for this call only. Used by the two-phase "frozen then
%     trainable" schedule, where each phase needs its own ``MaxEpochs`` and
%     ``InitialLearnRate`` without disturbing what the user configured
%     (see :func:`startTrainingInstances`). ``obj.TrainingOpt`` is never modified.
%
% Output Arguments:
%   - **TrainingOptions** - options object accepted by ``trainSOLOV2``
%

global mibDeepTrainingProgressStruct

if nargin < 3; trainingOptOverrides = struct(); end

% work on a copy so a phase-specific learning rate or epoch count never leaks back into
% the user's settings, and so the progress window is told about the phase it is showing
trainingOpt = obj.TrainingOpt;
% 'plateauDetection' is not a trainingOptions parameter, it is forwarded to the progress
% display further down, so it must not join the copy
overrideFields = setdiff(fieldnames(trainingOptOverrides), {'plateauDetection'}, 'stable');
for overrideId = 1:numel(overrideFields)
    trainingOpt.(overrideFields{overrideId}) = trainingOptOverrides.(overrideFields{overrideId});
end

TrainingOptions = struct();

verboseSwitch = false;
if strcmp(trainingOpt.Plots, 'none')
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
        PlotsSwitch = trainingOpt.Plots;
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
            % gpuDevice(index) RESETS the device and invalidates every gpuArray that
            % already exists - and it does so even when the requested index is the one
            % already selected (verified: parallel:gpu:array:InvalidData). This function
            % runs once per training phase, and the "frozen then trainable" schedule
            % carries a trained network from one phase into the next, so an unconditional
            % call here destroys those weights and phase 2 dies on its first forward pass.
            % Only select when the device is not already the current one.
            try
                currentDevice = gpuDevice();    % query only, this form does not reset
            catch
                currentDevice = [];
            end
            if isempty(currentDevice) || currentDevice.Index ~= selectedIndex
                gpuDevice(selectedIndex);   % choose selected GPU device
            end
            executionEnvironment = 'gpu';
    end

    % recalculate validation frequency from epochs to
    % interations
    ValidationFrequencyInIterations = ceil(mibDeepTrainingProgressStruct.iterPerEpoch / trainingOpt.ValidationFrequency);

    evalTrainingOptions = join([
        "TrainingOptions = trainingOptions(trainingOpt.solverName,"
        "'MaxEpochs', trainingOpt.MaxEpochs,"
        "'Shuffle', trainingOpt.Shuffle,"
        "'InitialLearnRate', trainingOpt.InitialLearnRate,"
        "'LearnRateSchedule', trainingOpt.LearnRateSchedule,"
        "'LearnRateDropPeriod', trainingOpt.LearnRateDropPeriod,"
        "'LearnRateDropFactor', trainingOpt.LearnRateDropFactor,"
        "'L2Regularization', trainingOpt.L2Regularization,"
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
                trainingProgressOptions.TrainingOpt = trainingOpt;
                trainingProgressOptions.calculateAccuracy = obj.BatchOpt.O_CalculateAccuracyInstances;   % whether the validation mAP metric is computed
                % only the frozen phase of the two-phase schedule sets this; see
                % deepmib.customTrainingProgressDisplay
                if isfield(trainingOptOverrides, 'plateauDetection')
                    trainingProgressOptions.plateauDetection = trainingOptOverrides.plateauDetection;
                end
                trainingProgressOptions.sendNextReportAtEpoch = -1;   % next epoch value to send training report
                if obj.SendReports.T_SendReports && obj.SendReports.sendDuringRun
                    trainingProgressOptions.sendNextReportAtEpoch = trainingOpt.CheckpointFrequency+1; % the value is taken from the checkpoint frequency
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
                trainingProgressOptions.TrainingOpt = trainingOpt;
                trainingProgressOptions.calculateAccuracy = obj.BatchOpt.O_CalculateAccuracyInstances;   % whether the validation mAP metric is computed
                % only the frozen phase of the two-phase schedule sets this; see
                % deepmib.customTrainingProgressDisplay
                if isfield(trainingOptOverrides, 'plateauDetection')
                    trainingProgressOptions.plateauDetection = trainingOptOverrides.plateauDetection;
                end
                trainingProgressOptions.sendNextReportAtEpoch = -1;   % next epoch value to send training report
                if obj.SendReports.T_SendReports && obj.SendReports.sendDuringRun
                    trainingProgressOptions.sendNextReportAtEpoch = trainingOpt.CheckpointFrequency+1; % the value is taken from the checkpoint frequency
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
    switch trainingOpt.solverName
        case 'adam'
            evalTrainingOptions = join([evalTrainingOptions
                "'GradientDecayFactor', trainingOpt.GradientDecayFactor,"
                "'SquaredGradientDecayFactor', trainingOpt.SquaredGradientDecayFactor,"
                ], ' ');
        case 'rmsprop'
            evalTrainingOptions = join([evalTrainingOptions
                "'SquaredGradientDecayFactor', trainingOpt.SquaredGradientDecayFactor,"
                ], ' ');
        case 'sgdm'
            evalTrainingOptions = join([evalTrainingOptions
                "'Momentum', trainingOpt.Momentum,"
                ], ' ');
    end

    % add validation store
    if ~isempty(valDS)
        evalTrainingOptions = join([evalTrainingOptions
            "'ValidationData', valDS,"
            "'ValidationFrequency', ValidationFrequencyInIterations,"
            "'ValidationPatience', trainingOpt.ValidationPatience," ...
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
    if strcmp(trainingOpt.OutputNetwork, 'best-validation-loss') && isempty(valDS)
        selection = uiconfirm(obj.view.gui, ...
            sprintf('The current training options have OutputNetwork parameter set to "best-validation-loss" to return the network corresponding to the training iteration with the lowest validation loss.\n\nPlease hit Cancel and provide images for validation (Directories and preprocessing->Fraction of images for validation) and start training again.\n\nAlternatively press "Continue using last-iteration output" to return the network corresponding to the last training iteration.'), ...
            'Missing validation images',...
            'Options',{'Continue using last-iteration output', 'Cancel'}, ...
            'DefaultOption', 'Cancel', ...
            'Icon','warning');
        if strcmp(selection, 'Cancel'); delete(obj.wb); return; end
        trainingOpt.OutputNetwork = 'last-iteration';
        obj.TrainingOpt.OutputNetwork = 'last-iteration';   % remember, so a second phase does not ask again
    end

    evalTrainingOptions = join([evalTrainingOptions
        "'OutputNetwork', trainingOpt.OutputNetwork,"
        ], ' ');

    % add frequency of checkpoint generations
    if obj.BatchOpt.T_SaveProgress
        evalTrainingOptions = join([evalTrainingOptions
            "'CheckpointFrequency', trainingOpt.CheckpointFrequency,"
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
