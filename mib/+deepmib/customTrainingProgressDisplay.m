function stopState = customTrainingProgressDisplay(progressStruct, trainingProgressOptions)
% CUSTOMTRAININGPROGRESSDISPLAY - Show custom progress dialog for DeepMIB training.
%
% Syntax:
%   .. code-block:: matlab
%
%      stopState = customTrainingProgressDisplay(progressStruct, trainingProgressOptions)
%
% Input Arguments:
%   - **progressStruct** — struct with current training progress (provided by ``trainNetwork``):
%
%     - ``.Epoch`` — current epoch number
%     - ``.Iteration`` — current iteration number, e.g. ``2``
%     - ``.TimeSinceStart`` — elapsed time in seconds, e.g. ``4.5219``
%     - ``.TrainingLoss`` — current training loss, e.g. ``0.7802``
%     - ``.ValidationLoss`` — validation loss (``[]`` if no validation)
%     - ``.BaseLearnRate`` — current learning rate, e.g. ``0.0100``
%     - ``.TrainingAccuracy`` — training accuracy (%), e.g. ``26.9975``
%     - ``.TrainingRMSE`` — training RMSE (regression tasks), e.g. ``164.7408``
%     - ``.ValidationAccuracy`` — validation accuracy (``[]`` if no validation)
%     - ``.ValidationRMSE`` — validation RMSE (``[]`` if no validation)
%     - ``.State`` — training phase string, e.g. ``'iteration'``
%
%   - **trainingProgressOptions** — struct with display/training parameters:
%
%     - ``.O_NumberOfPoints`` — [numeric] max points in the progress plot
%       (``mibDeepController.BatchOpt.O_NumberOfPoints{1}``)
%     - ``.NetworkFilename`` — [char] network file path
%       (``mibDeepController.BatchOpt.NetworkFilename``)
%     - ``.noColorChannels`` — [numeric] number of colour channels
%       (``str2num(obj.BatchOpt.T_InputPatchSize)(4)``)
%     - ``.Workflow`` — [char] active workflow (``obj.BatchOpt.Workflow{1}``)
%     - ``.Architecture`` — [char] network architecture (``obj.BatchOpt.Architecture{1}``)
%     - ``.refreshRateIter`` — [numeric] UI refresh rate in iterations
%       (``obj.BatchOpt.O_RefreshRateIter{1}``)
%     - ``.matlabVersion`` — [numeric] MATLAB release number (``obj.mibController.matlabVersion``)
%     - ``.iterPerEpoch`` — [numeric] iterations per epoch
%     - ``.sendNextReportAtEpoch`` — [numeric] epoch at which to send the next e-mail report
%     - ``.TrainingOpt.MaxEpochs`` — maximum number of training epochs
%     - ``.TrainingOpt.solverName`` — optimiser name string
%     - ``.TrainingOpt.Shuffle`` — dataset shuffle strategy
%     - ``.TrainingOpt.LearnRateSchedule`` — learning-rate schedule type
%     - ``.TrainingOpt.OutputNetwork`` — which network to save on each checkpoint
%     - ``.TrainingOpt.InitialLearnRate`` — initial learning rate
%     - ``.TrainingOpt.LearnRateDropPeriod`` — period (epochs) for learning-rate drop
%     - ``.TrainingOpt.ValidationPatience`` — early-stop patience (epochs)
%     - ``.TrainingOpt.ValidationFrequency`` — validation frequency (iterations)
%

global mibDeepStopTraining
global mibDeepTrainingProgressStruct

stopState =  false;

% Some trainers provide a reduced progress struct: trainSOLOV2 (2D Instance)
% reports only Epoch, Iteration, TimeElapsed, LearnRate and TrainingLoss.
% Add the remaining fields used below with neutral defaults so the shared
% progress display works for both semantic and instance segmentation.
if ~isfield(progressStruct, 'TrainingAccuracy');   progressStruct.TrainingAccuracy = NaN; end
if ~isfield(progressStruct, 'ValidationLoss');     progressStruct.ValidationLoss = []; end
if ~isfield(progressStruct, 'ValidationAccuracy'); progressStruct.ValidationAccuracy = NaN; end

% trainSOLOV2's per-iteration struct (images.dltrain.internal.MetricLogger) pre-fills every
% metric column with NaN when the log entry is created, and only overwrites the
% "Validation*" columns with a real value on iterations where IsValidationIteration is
% true (MetricLogger.m, evaluateMetrics/evaluateValidationMetrics). So, unlike
% trainNetwork/trainnet - which leave ValidationLoss as [] on non-validation iterations -
% trainSOLOV2 reports a scalar NaN instead. isempty(NaN) is false, so without this
% normalisation every non-validation iteration was being logged into the validation curve
% as a NaN point, breaking the line into isolated dots around the few real values.
if isscalar(progressStruct.ValidationLoss) && isnan(progressStruct.ValidationLoss)
    progressStruct.ValidationLoss = [];
end

% trainSOLOV2 has no training-time accuracy-like metric, but when
% mAPInstanceSegmentationMetric is enabled as a validation metric (see
% preprareTrainingOptionsInstances) it reports "ValidationmAP" (a 0..1 fraction) instead of
% ValidationAccuracy. Map it onto ValidationAccuracy, as a percentage, so the existing
% Validation gauge/text code below needs no separate path for it.
if isfield(progressStruct, 'ValidationmAP') && ~isempty(progressStruct.ValidationmAP) && ~isnan(progressStruct.ValidationmAP)
    progressStruct.ValidationAccuracy = progressStruct.ValidationmAP * 100;
end

% get max number of points in the progress plot to show
maxPoints = trainingProgressOptions.O_NumberOfPoints;

% trainNetwork/trainnet fire the first OutputFcn call at Iteration 0, but trainSOLOV2
% fires it at Iteration 1 — so also initialise when the progress struct has not been
% set up yet (startTrainingInstances/startTraining reset it before each run)
if (isempty(progressStruct.Iteration) || progressStruct.Iteration == 0 || ...
        ~isfield(mibDeepTrainingProgressStruct, 'sendNextReportAtEpoch'))
    mibDeepTrainingProgressStruct.TrainXvec = zeros([maxPoints, 1]);  % vector of iteration numbers for training
    mibDeepTrainingProgressStruct.TrainLoss = zeros([maxPoints, 1]);  % training loss vector
    mibDeepTrainingProgressStruct.TrainAccuracy = zeros([maxPoints, 1]);  % training accuracy vector
    mibDeepTrainingProgressStruct.ValidationXvec = zeros([maxPoints, 1]);     % vector of iteration numbers for validation
    mibDeepTrainingProgressStruct.ValidationLoss = zeros([maxPoints, 1]); % validation loss vector
    mibDeepTrainingProgressStruct.ValidationAccuracy = zeros([maxPoints, 1]); % validation accuracy vector
    mibDeepTrainingProgressStruct.TrainXvecIndex = 1;    % index of the next point to be added to the training vectors
    mibDeepTrainingProgressStruct.ValidationXvecIndex = 1; % index of the next point to be added to the validation vectors
    mibDeepTrainingProgressStruct.NetworkFilename = trainingProgressOptions.NetworkFilename;   % add network name to mibDeepTrainingProgressStruct to send it into mibDeepSaveTrainingPlot

    % define next epoch point to send report
    mibDeepTrainingProgressStruct.sendNextReportAtEpoch = trainingProgressOptions.sendNextReportAtEpoch;

    % Create progress window
    mibDeepTrainingProgressStruct.UIFigure = uifigure('Visible', 'off');
    ScreenSize = get(0, 'ScreenSize');
    FigPos(1) = 1/2*(ScreenSize(3)-800);
    FigPos(2) = 2/3*(ScreenSize(4)-600);
    mibDeepTrainingProgressStruct.UIFigure.Position = [FigPos(1), FigPos(2), 800, 600];
    [~, netName] = fileparts(trainingProgressOptions.NetworkFilename);
    mibDeepTrainingProgressStruct.UIFigure.Name = sprintf('Training progress (%s)', netName);

    % Create GridLayouts
    mibDeepTrainingProgressStruct.GridLayout = uigridlayout(mibDeepTrainingProgressStruct.UIFigure, [2, 1]);
    mibDeepTrainingProgressStruct.GridLayout.ColumnWidth = {'1x'};

    mibDeepTrainingProgressStruct.GridLayout2 = uigridlayout(mibDeepTrainingProgressStruct.GridLayout);
    mibDeepTrainingProgressStruct.GridLayout2.ColumnWidth = {'0.8x', '3.2x', '2x'};
    mibDeepTrainingProgressStruct.GridLayout2.RowHeight = {'1x'};
    mibDeepTrainingProgressStruct.GridLayout2.Layout.Row = 2;
    mibDeepTrainingProgressStruct.GridLayout2.Layout.Column = 1;

    % Create Panels
    mibDeepTrainingProgressStruct.AccuracyPanel = uipanel(mibDeepTrainingProgressStruct.GridLayout2);
    mibDeepTrainingProgressStruct.AccuracyPanel.Title = 'Accuracy';
    mibDeepTrainingProgressStruct.AccuracyPanel.Layout.Row = 1;
    mibDeepTrainingProgressStruct.AccuracyPanel.Layout.Column = 1;

    mibDeepTrainingProgressStruct.InformationPanel = uipanel(mibDeepTrainingProgressStruct.GridLayout2);
    mibDeepTrainingProgressStruct.InformationPanel.Title = 'Training progress and settings';
    mibDeepTrainingProgressStruct.InformationPanel.Layout.Row = 1;
    mibDeepTrainingProgressStruct.InformationPanel.Layout.Column = 2;

    mibDeepTrainingProgressStruct.InputPatchPreviewPanel = uipanel(mibDeepTrainingProgressStruct.GridLayout2);
    mibDeepTrainingProgressStruct.InputPatchPreviewPanel.Title = 'Input patch preview';
    mibDeepTrainingProgressStruct.InputPatchPreviewPanel.Layout.Row = 1;
    mibDeepTrainingProgressStruct.InputPatchPreviewPanel.Layout.Column = 3;

    % Create widgets
    mibDeepTrainingProgressStruct.AccTrainGauge = uigauge(mibDeepTrainingProgressStruct.AccuracyPanel, 'linear');
    mibDeepTrainingProgressStruct.AccTrainGauge.Orientation = 'vertical';
    mibDeepTrainingProgressStruct.AccTrainGauge.Position = [6 28 40 190];

    mibDeepTrainingProgressStruct.AccValGauge = uigauge(mibDeepTrainingProgressStruct.AccuracyPanel, 'linear');
    mibDeepTrainingProgressStruct.AccValGauge.Orientation = 'vertical';
    mibDeepTrainingProgressStruct.AccValGauge.Position = [54 28 40 190];

    mibDeepTrainingProgressStruct.TrainingLabel = uilabel(mibDeepTrainingProgressStruct.AccuracyPanel);
    mibDeepTrainingProgressStruct.TrainingLabel.Position = [10 221 48 22];
    mibDeepTrainingProgressStruct.TrainingLabel.Text = 'Train';

    mibDeepTrainingProgressStruct.ValidationLabel = uilabel(mibDeepTrainingProgressStruct.AccuracyPanel);
    mibDeepTrainingProgressStruct.ValidationLabel.HorizontalAlignment = 'center';
    mibDeepTrainingProgressStruct.ValidationLabel.Position = [46 221 57 22];
    mibDeepTrainingProgressStruct.ValidationLabel.Text = 'Valid.';

    mibDeepTrainingProgressStruct.AccTrainingValue = uilabel(mibDeepTrainingProgressStruct.AccuracyPanel);
    mibDeepTrainingProgressStruct.AccTrainingValue.Position = [7 3 48 22];
    mibDeepTrainingProgressStruct.AccTrainingValue.Text = '0';

    mibDeepTrainingProgressStruct.AccValidationValue = uilabel(mibDeepTrainingProgressStruct.AccuracyPanel);
    mibDeepTrainingProgressStruct.AccValidationValue.Position = [55 3 48 22];
    mibDeepTrainingProgressStruct.AccValidationValue.Text = '0';

    if strcmp(trainingProgressOptions.Workflow, '2D Instance')
        % trainSOLOV2 never computes a training-time accuracy-like metric (only Loss); grey
        % out the Training gauge/value so it does not show a misleading NaN%. The
        % Validation gauge is left enabled: when mAPInstanceSegmentationMetric is used (see
        % preprareTrainingOptionsInstances), it is fed a real value via ValidationmAP above.
        mibDeepTrainingProgressStruct.AccTrainGauge.Enable = 'off';
        mibDeepTrainingProgressStruct.AccTrainingValue.Enable = 'off';
        mibDeepTrainingProgressStruct.AccTrainingValue.Text = 'N/A';

        % when the user disabled accuracy calculation (BatchOpt.O_CalculateAccuracyInstances),
        % the validation mAP metric is not added, so no ValidationmAP is ever reported - grey
        % out the Validation gauge/value too, so it does not sit at a misleading 0%
        if isfield(trainingProgressOptions, 'calculateAccuracy') && ~trainingProgressOptions.calculateAccuracy
            mibDeepTrainingProgressStruct.AccValGauge.Enable = 'off';
            mibDeepTrainingProgressStruct.AccValidationValue.Enable = 'off';
            mibDeepTrainingProgressStruct.AccValidationValue.Text = 'N/A';
        end
    end

    mibDeepTrainingProgressStruct.TrainingProgress = uilabel(mibDeepTrainingProgressStruct.InformationPanel);
    mibDeepTrainingProgressStruct.TrainingProgress.Position = [7 218 220 22];
    mibDeepTrainingProgressStruct.TrainingProgress.FontWeight = 'bold';
    mibDeepTrainingProgressStruct.TrainingProgress.Text = trainingProgressOptions.gpuDevice;
    
    mibDeepTrainingProgressStruct.StartTime = uilabel(mibDeepTrainingProgressStruct.InformationPanel);
    mibDeepTrainingProgressStruct.StartTime.Position = [7 196 175 22];
    mibDeepTrainingProgressStruct.StartTime.Text = sprintf('Started: %s', datetime('now'));

    mibDeepTrainingProgressStruct.ElapsedTime = uilabel(mibDeepTrainingProgressStruct.InformationPanel);
    mibDeepTrainingProgressStruct.ElapsedTime.Position = [7 176 175 22];
    mibDeepTrainingProgressStruct.ElapsedTime.Text = 'Elapsed: --.--.--';

    mibDeepTrainingProgressStruct.TimeToGo = uilabel(mibDeepTrainingProgressStruct.InformationPanel);
    mibDeepTrainingProgressStruct.TimeToGo.Position = [7 156 175 22];
    mibDeepTrainingProgressStruct.TimeToGo.Text = 'Time to go: --.--.--';

    mibDeepTrainingProgressStruct.ProgressGauge = uigauge(mibDeepTrainingProgressStruct.InformationPanel, 'semicircular');
    mibDeepTrainingProgressStruct.ProgressGauge.Position = [30 5 120 65];

    mibDeepTrainingProgressStruct.Epoch = uilabel(mibDeepTrainingProgressStruct.InformationPanel);
    mibDeepTrainingProgressStruct.Epoch.Position = [7 120 170 22];
    mibDeepTrainingProgressStruct.Epoch.Text = sprintf('Epoch: 0 of %d', trainingProgressOptions.TrainingOpt.MaxEpochs);

    mibDeepTrainingProgressStruct.IterationNumber = uilabel(mibDeepTrainingProgressStruct.InformationPanel);
    mibDeepTrainingProgressStruct.IterationNumber.Position = [7 100 170 22];
    mibDeepTrainingProgressStruct.IterationNumber.Text = 'Iteration number:';

    mibDeepTrainingProgressStruct.IterationNumberValue = uilabel(mibDeepTrainingProgressStruct.InformationPanel);
    mibDeepTrainingProgressStruct.IterationNumberValue.Position = [26 80 160 22];
    mibDeepTrainingProgressStruct.IterationNumberValue.Text = sprintf('0 of %d', trainingProgressOptions.iterPerEpoch*trainingProgressOptions.TrainingOpt.MaxEpochs);

    mibDeepTrainingProgressStruct.IterationsPerEpoch = uilabel(mibDeepTrainingProgressStruct.InformationPanel);
    mibDeepTrainingProgressStruct.IterationsPerEpoch.Position = [192 196 202 22];
    mibDeepTrainingProgressStruct.IterationsPerEpoch.Text = sprintf('Iterations per epoch: %d', trainingProgressOptions.iterPerEpoch);

    mibDeepTrainingProgressStruct.Solver = uilabel(mibDeepTrainingProgressStruct.InformationPanel);
    mibDeepTrainingProgressStruct.Solver.Position = [192 176 202 22];
    mibDeepTrainingProgressStruct.Solver.Text = sprintf('Solver name: %s', trainingProgressOptions.TrainingOpt.solverName);

    mibDeepTrainingProgressStruct.TrainingOpt.Shuffle = uilabel(mibDeepTrainingProgressStruct.InformationPanel);
    mibDeepTrainingProgressStruct.TrainingOpt.Shuffle.Position = [192 156 202 22];
    mibDeepTrainingProgressStruct.TrainingOpt.Shuffle.Text = sprintf('Shuffle: %s', trainingProgressOptions.TrainingOpt.Shuffle);

    mibDeepTrainingProgressStruct.TrainingOpt.LearnRateSchedule = uilabel(mibDeepTrainingProgressStruct.InformationPanel);
    mibDeepTrainingProgressStruct.TrainingOpt.LearnRateSchedule.Position = [192 136 202 22];
    mibDeepTrainingProgressStruct.TrainingOpt.LearnRateSchedule.Text = sprintf('Learn rate schedule: %s', trainingProgressOptions.TrainingOpt.LearnRateSchedule);

    zLinePos = 106;
    if trainingProgressOptions.matlabVersion >= 9.11
        mibDeepTrainingProgressStruct.TrainingOpt.OutputNetwork = uilabel(mibDeepTrainingProgressStruct.InformationPanel);
        mibDeepTrainingProgressStruct.TrainingOpt.OutputNetwork.Position = [192 116 202 22];
        mibDeepTrainingProgressStruct.TrainingOpt.OutputNetwork.Text = sprintf('Output network: %s', trainingProgressOptions.TrainingOpt.OutputNetwork);
        zLinePos = 86;
    end

    mibDeepTrainingProgressStruct.TrainingOpt.InitialLearnRate = uilabel(mibDeepTrainingProgressStruct.InformationPanel);
    mibDeepTrainingProgressStruct.TrainingOpt.InitialLearnRate.Position = [192 zLinePos 202 22];
    mibDeepTrainingProgressStruct.TrainingOpt.InitialLearnRate.Text = sprintf('Initial learn rate: %f', trainingProgressOptions.TrainingOpt.InitialLearnRate);

    zLinePos = zLinePos - 20;
    mibDeepTrainingProgressStruct.BaseLearnRate = uilabel(mibDeepTrainingProgressStruct.InformationPanel);
    mibDeepTrainingProgressStruct.BaseLearnRate.Position = [192 zLinePos 202 22];
    mibDeepTrainingProgressStruct.BaseLearnRate.Text = sprintf('Base learn rate: %.3e', trainingProgressOptions.TrainingOpt.InitialLearnRate);

    zLinePos = zLinePos - 20;
    mibDeepTrainingProgressStruct.TrainingOpt.LearnRateDropPeriod = uilabel(mibDeepTrainingProgressStruct.InformationPanel);
    mibDeepTrainingProgressStruct.TrainingOpt.LearnRateDropPeriod.Position = [192 zLinePos 202 22];
    mibDeepTrainingProgressStruct.TrainingOpt.LearnRateDropPeriod.Text = sprintf('LearnRate Drop Period: %d', trainingProgressOptions.TrainingOpt.LearnRateDropPeriod);

    zLinePos = zLinePos - 20;
    mibDeepTrainingProgressStruct.TrainingOpt.ValidationPatience = uilabel(mibDeepTrainingProgressStruct.InformationPanel);
    mibDeepTrainingProgressStruct.TrainingOpt.ValidationPatience.Position = [192 zLinePos 202 22];
    mibDeepTrainingProgressStruct.TrainingOpt.ValidationPatience.Text = sprintf('Validation patience: %d', trainingProgressOptions.TrainingOpt.ValidationPatience);

    zLinePos = zLinePos - 20;
    mibDeepTrainingProgressStruct.TrainingOpt.ValidationFrequency = uilabel(mibDeepTrainingProgressStruct.InformationPanel);
    mibDeepTrainingProgressStruct.TrainingOpt.ValidationFrequency.Position = [192 zLinePos 202 22];
    mibDeepTrainingProgressStruct.TrainingOpt.ValidationFrequency.Text = sprintf('Validation frequency: %.1f /epoch', trainingProgressOptions.TrainingOpt.ValidationFrequency);

    mibDeepTrainingProgressStruct.StopTrainingButton = uibutton(mibDeepTrainingProgressStruct.InputPatchPreviewPanel, 'push',...
        'ButtonPushedFcn', @deepmib.stopTrainingCallback);
    mibDeepTrainingProgressStruct.StopTrainingButton.BackgroundColor = [0 1 0];
    mibDeepTrainingProgressStruct.StopTrainingButton.Position = [140 8 100 22];
    mibDeepTrainingProgressStruct.StopTrainingButton.Text = 'Stop training';
    mibDeepTrainingProgressStruct.StopTrainingButton.Tooltip = 'Stop and finalize the run, it may take significant time for large datasets';

    mibDeepTrainingProgressStruct.EmergencyBrakeButton = uibutton(mibDeepTrainingProgressStruct.InputPatchPreviewPanel, 'push',...
        'ButtonPushedFcn', @deepmib.stopTrainingCallback);
    mibDeepTrainingProgressStruct.EmergencyBrakeButton.BackgroundColor = [1 0 0];
    mibDeepTrainingProgressStruct.EmergencyBrakeButton.Position = [101 39 139 22];
    mibDeepTrainingProgressStruct.EmergencyBrakeButton.Text = 'Emergency brake';
    mibDeepTrainingProgressStruct.EmergencyBrakeButton.Tooltip = 'Instantly stop the run, the final network file will be generated from the recent existing checkpoint';

    mibDeepTrainingProgressStruct.saveTrainingPlotBtn = uibutton(mibDeepTrainingProgressStruct.InputPatchPreviewPanel, 'push',...
        'ButtonPushedFcn', @(src, evnt)deepmib.saveTrainingPlot(src, evnt, mibDeepTrainingProgressStruct));
    mibDeepTrainingProgressStruct.saveTrainingPlotBtn.Position = [10 8 70 22];
    mibDeepTrainingProgressStruct.saveTrainingPlotBtn.Text = 'Save plot';
    mibDeepTrainingProgressStruct.saveTrainingPlotBtn.Tooltip = 'Save the custom training plot to a file';

    % Create axes
    mibDeepTrainingProgressStruct.UILossAxes = uiaxes(mibDeepTrainingProgressStruct.GridLayout);
    mibDeepTrainingProgressStruct.UILossAxes.Units = 'pixels';
    title(mibDeepTrainingProgressStruct.UILossAxes, 'Loss function plot');
    xlabel(mibDeepTrainingProgressStruct.UILossAxes, 'Iteration');
    ylabel(mibDeepTrainingProgressStruct.UILossAxes, {'Loss value'; ''});
    mibDeepTrainingProgressStruct.UILossAxes.XGrid = 'on';
    mibDeepTrainingProgressStruct.UILossAxes.YGrid = 'on';
    mibDeepTrainingProgressStruct.UILossAxes.Layout.Row = 1;
    mibDeepTrainingProgressStruct.UILossAxes.Layout.Column = 1;
    mibDeepTrainingProgressStruct.hPlot = plot(mibDeepTrainingProgressStruct.UILossAxes, 0, 0, '-', 0, 0, '-o');
    mibDeepTrainingProgressStruct.hPlot(2).MarkerSize = 4;
    mibDeepTrainingProgressStruct.hPlot(2).MarkerFaceColor = 'r';
    legend(mibDeepTrainingProgressStruct.UILossAxes, 'Training', 'Validation');

    % add a context menu to the axes
    % Create ContextMenu
    mibDeepTrainingProgressStruct.UILossAxes_cm = uicontextmenu(mibDeepTrainingProgressStruct.UIFigure);
    % define menu entries
    mibDeepTrainingProgressStruct.UILossAxes_cm_setYmin = uimenu(mibDeepTrainingProgressStruct.UILossAxes_cm);
    mibDeepTrainingProgressStruct.UILossAxes_cm_setYmin.MenuSelectedFcn = @(src, evnt)mibDeepTrainingProgressStructUpdateAxesLimits(src, evnt, 'setYlimits');
    mibDeepTrainingProgressStruct.UILossAxes_cm_setYmin.Text = 'Set Y limits';
    % Assign app.ContextMenu
    mibDeepTrainingProgressStruct.UILossAxes.ContextMenu = mibDeepTrainingProgressStruct.UILossAxes_cm;

    mibDeepTrainingProgressStruct.imgPatch = uiaxes(mibDeepTrainingProgressStruct.InputPatchPreviewPanel);
    mibDeepTrainingProgressStruct.imgPatch.XTick = [];
    mibDeepTrainingProgressStruct.imgPatch.XTickLabel = '';
    mibDeepTrainingProgressStruct.imgPatch.YTick = [];
    mibDeepTrainingProgressStruct.imgPatch.YTickLabel = '';
    mibDeepTrainingProgressStruct.imgPatch.XColor = 'none';
    mibDeepTrainingProgressStruct.imgPatch.YColor = 'none';
    mibDeepTrainingProgressStruct.imgPatch.Position = [6 123 116 116];
    mibDeepTrainingProgressStruct.imgPatch.Box = 'on';
    mibDeepTrainingProgressStruct.imgPatch.Units = 'pixels';
    mibDeepTrainingProgressStruct.imgPatch.DataAspectRatio = [1 1 1];
    mibDeepTrainingProgressStruct.imgPatch.Toolbar.Visible = 'off';
    if trainingProgressOptions.noColorChannels == 1
        mibDeepTrainingProgressStruct.imgPatch.Colormap = gray;
    end

    if ~strcmp(trainingProgressOptions.Workflow, '2D Patch-wise')
        mibDeepTrainingProgressStruct.labelPatch = uiaxes(mibDeepTrainingProgressStruct.InputPatchPreviewPanel);
        mibDeepTrainingProgressStruct.labelPatch.XTick = [];
        mibDeepTrainingProgressStruct.labelPatch.XTickLabel = '';
        mibDeepTrainingProgressStruct.labelPatch.YTick = [];
        mibDeepTrainingProgressStruct.labelPatch.YTickLabel = '';
        mibDeepTrainingProgressStruct.labelPatch.XColor = 'none';
        mibDeepTrainingProgressStruct.labelPatch.YColor = 'none';
        mibDeepTrainingProgressStruct.labelPatch.Position = [127 123 116 116];
        mibDeepTrainingProgressStruct.labelPatch.Box = 'on';
        mibDeepTrainingProgressStruct.labelPatch.Units = 'pixels';
        mibDeepTrainingProgressStruct.labelPatch.DataAspectRatio = [1 1 1];
        mibDeepTrainingProgressStruct.labelPatch.Toolbar.Visible = 'off';
    else
        mibDeepTrainingProgressStruct.labelPatch = uilabel(mibDeepTrainingProgressStruct.InputPatchPreviewPanel);
        mibDeepTrainingProgressStruct.labelPatch.Position = [127 200 202 40];
        mibDeepTrainingProgressStruct.labelPatch.FontSize = 14;
        mibDeepTrainingProgressStruct.labelPatch.FontWeight = 'bold';
        mibDeepTrainingProgressStruct.labelPatch.Text = 'Patch Label';
    end

    % Show the figure after all components are created
    mibDeepTrainingProgressStruct.UIFigure.Visible = 'on';
    mibDeepTrainingProgressStruct.maxIter = trainingProgressOptions.iterPerEpoch*trainingProgressOptions.TrainingOpt.MaxEpochs;
    mibDeepTrainingProgressStruct.stopTraining = false;
    % deepmib.stopTrainingCallback needs these to decide whether the architecture has
    % BatchNormalization layers that an Emergency brake would leave unfinalized
    mibDeepTrainingProgressStruct.Workflow = trainingProgressOptions.Workflow;
    mibDeepTrainingProgressStruct.Architecture = trainingProgressOptions.Architecture;
else
    if mibDeepStopTraining == true % stop training
        % The dltrain-based trainer behind trainSOLOV2 ('2D Instance') only leaves the
        % inner per-epoch loop when asked to stop; its outer "for epoch = 1:MaxEpochs"
        % loop still runs to the end, re-saving a checkpoint on every idle epoch. See
        % deepmib.suspendCheckpointSaving for the full description.
        % make the idle epochs cheap: without a reachable checkpoint folder they cost a
        % datastore reset and shuffle instead of a full network save.
        % The Emergency brake is NOT raised here - images.dltrain calls this OutputFcn from
        % a notify() listener, and notify() catches listener errors and turns them into a
        % warning, which both swallows the abort and stops the trainer from ever seeing the
        % stop request. It is raised from deepmib.readInstancePatch instead.
        if isfield(mibDeepTrainingProgressStruct, 'dltrainBasedTrainer') && mibDeepTrainingProgressStruct.dltrainBasedTrainer
            % from here on every read is a throwaway prefetch, see deepmib.readInstancePatch
            mibDeepTrainingProgressStruct.spinDownActive = true;
            deepmib.suspendCheckpointSaving('suspend');
        end
        stopState = true;
        return;
    end

    % the progress window / plot handles may be invalid: the user closed the window
    % mid-training, or a previous run left dead handles in the global struct. There is
    % nothing to update in that case, so request a clean stop instead of erroring on a
    % deleted graphics object.
    if ~isfield(mibDeepTrainingProgressStruct, 'UIFigure') || ~isvalid(mibDeepTrainingProgressStruct.UIFigure) || ...
            ~isfield(mibDeepTrainingProgressStruct, 'hPlot') || ~all(isvalid(mibDeepTrainingProgressStruct.hPlot))
        stopState = true;
        mibDeepStopTraining = true;
        return;
    end

    if progressStruct.Epoch == mibDeepTrainingProgressStruct.sendNextReportAtEpoch
        %trainingProgressOptions.sendNextReportAtEpoch = trainingProgressOptions.sendNextReportAtEpoch + trainingProgressOptions.TrainingOpt.CheckpointFrequency;
        mibDeepTrainingProgressStruct.sendNextReportAtEpoch = mibDeepTrainingProgressStruct.sendNextReportAtEpoch + trainingProgressOptions.TrainingOpt.CheckpointFrequency;
        [~, fn] = fileparts(trainingProgressOptions.NetworkFilename);
        mgsText = sprintf(['DeepMIB training of "%s" network\n' ...
            '%s\n' ...
            'Iteration Number: %s\n\n' ...
            '%s\n%s\n%s\n\n' ...
            'Training Loss: %f\n' ...
            'Training Accuracy: %f\n' ...
            ], ...
            fn, ...
            mibDeepTrainingProgressStruct.Epoch.Text, mibDeepTrainingProgressStruct.IterationNumberValue.Text, ...
            mibDeepTrainingProgressStruct.StartTime.Text, mibDeepTrainingProgressStruct.ElapsedTime.Text, mibDeepTrainingProgressStruct.TimeToGo.Text, ...
            progressStruct.TrainingLoss(end), progressStruct.TrainingAccuracy(end) );
        try
            sendmail(trainingProgressOptions.sendReportToEmail, sprintf('DeepMIB: training of %s in progress...(%s)', fn, mibDeepTrainingProgressStruct.IterationNumberValue.Text), mgsText);
        catch err
            % can not send the report
            mibDeepTrainingProgressStruct.sendNextReportAtEpoch = -1;
        end
    end

    % draw plot for eath 5th iteration or for validation loss
    % check
    if mod(progressStruct.Iteration, trainingProgressOptions.refreshRateIter) ~= 1 && isempty(progressStruct.ValidationLoss); return; end

    mibDeepTrainingProgressStruct.TrainXvec(mibDeepTrainingProgressStruct.TrainXvecIndex) = progressStruct.Iteration;
    mibDeepTrainingProgressStruct.TrainLoss(mibDeepTrainingProgressStruct.TrainXvecIndex) = progressStruct.TrainingLoss;
    mibDeepTrainingProgressStruct.TrainAccuracy(mibDeepTrainingProgressStruct.TrainXvecIndex) = progressStruct.TrainingAccuracy;
    mibDeepTrainingProgressStruct.TrainXvecIndex = mibDeepTrainingProgressStruct.TrainXvecIndex + 1;

    mibDeepTrainingProgressStruct.hPlot(1).XData = mibDeepTrainingProgressStruct.TrainXvec(1:mibDeepTrainingProgressStruct.TrainXvecIndex-1);
    mibDeepTrainingProgressStruct.hPlot(1).YData = mibDeepTrainingProgressStruct.TrainLoss(1:mibDeepTrainingProgressStruct.TrainXvecIndex-1);
    if ~isnan(progressStruct.TrainingAccuracy)
        mibDeepTrainingProgressStruct.AccTrainGauge.Value = progressStruct.TrainingAccuracy;
        % leave the 'N/A' text (set for '2D Instance' at window creation) in place when
        % there is no training accuracy metric at all - only overwrite it with a real value
        mibDeepTrainingProgressStruct.AccTrainingValue.Text = sprintf('%.2f%%', progressStruct.TrainingAccuracy);
    end

    if isfield(progressStruct, 'TimeSinceStart') % when trainNetwork is used
        mibDeepTrainingProgressStruct.ElapsedTime.Text = ...
            sprintf('Elapsed time: %.0f h %.0f min %.2d sec', floor(progressStruct.TimeSinceStart/3600), floor(mod(round(progressStruct.TimeSinceStart),3600)/60), mod(round(progressStruct.TimeSinceStart),60));
        timerValue = progressStruct.TimeSinceStart/progressStruct.Iteration*(mibDeepTrainingProgressStruct.maxIter-progressStruct.Iteration);
        mibDeepTrainingProgressStruct.TimeToGo.Text = ...
            sprintf('Time to go: ~%.0f h %.0f min %.2d sec', floor(timerValue/3600), floor(mod(round(timerValue),3600)/60), mod(round(timerValue),60));
        mibDeepTrainingProgressStruct.BaseLearnRate.Text = sprintf('Base learn rate: %.3e', progressStruct.BaseLearnRate);
    else %  when trainnet is used
        mibDeepTrainingProgressStruct.ElapsedTime.Text = sprintf('Elapsed time: %s sec', progressStruct.TimeElapsed);
        timerValue = progressStruct.TimeElapsed/progressStruct.Iteration*(mibDeepTrainingProgressStruct.maxIter-progressStruct.Iteration);
        mibDeepTrainingProgressStruct.TimeToGo.Text = sprintf('Time to go: ~%s sec', timerValue);
        mibDeepTrainingProgressStruct.BaseLearnRate.Text = sprintf('Base learn rate: %.3e', progressStruct.LearnRate); % renamed to LearnRate
    end
    mibDeepTrainingProgressStruct.Epoch.Text = sprintf('Epoch: %d of %d', progressStruct.Epoch, trainingProgressOptions.TrainingOpt.MaxEpochs);
    mibDeepTrainingProgressStruct.IterationNumberValue.Text = sprintf('%d of %d', progressStruct.Iteration, round(mibDeepTrainingProgressStruct.maxIter));
    mibDeepTrainingProgressStruct.ProgressGauge.Value = progressStruct.Iteration/mibDeepTrainingProgressStruct.maxIter*100;
    

    if ~isempty(progressStruct.ValidationLoss)
        mibDeepTrainingProgressStruct.ValidationXvec(mibDeepTrainingProgressStruct.ValidationXvecIndex) = progressStruct.Iteration;
        mibDeepTrainingProgressStruct.ValidationLoss(mibDeepTrainingProgressStruct.ValidationXvecIndex) = progressStruct.ValidationLoss;
        mibDeepTrainingProgressStruct.ValidationAccuracy(mibDeepTrainingProgressStruct.ValidationXvecIndex) = progressStruct.ValidationAccuracy;
        mibDeepTrainingProgressStruct.ValidationXvecIndex = mibDeepTrainingProgressStruct.ValidationXvecIndex + 1;

        mibDeepTrainingProgressStruct.hPlot(2).XData = mibDeepTrainingProgressStruct.ValidationXvec(1:mibDeepTrainingProgressStruct.ValidationXvecIndex-1);
        mibDeepTrainingProgressStruct.hPlot(2).YData = mibDeepTrainingProgressStruct.ValidationLoss(1:mibDeepTrainingProgressStruct.ValidationXvecIndex-1);
        if ~isnan(progressStruct.ValidationAccuracy)
            mibDeepTrainingProgressStruct.AccValGauge.Value = progressStruct.ValidationAccuracy;
            mibDeepTrainingProgressStruct.AccValidationValue.Text = sprintf('%.2f%%', progressStruct.ValidationAccuracy);
        end

    end
    %drawnow;

    % decrease number of points
    if mibDeepTrainingProgressStruct.TrainXvecIndex > maxPoints
        mibDeepTrainingProgressStruct.TrainXvecIndex = maxPoints/2+1;
        linvec = linspace(1, mibDeepTrainingProgressStruct.TrainXvec(maxPoints), maxPoints/2);
        mibDeepTrainingProgressStruct.TrainLoss(1:maxPoints/2) = ...
            interp1(mibDeepTrainingProgressStruct.TrainXvec, mibDeepTrainingProgressStruct.TrainLoss, linvec);
        mibDeepTrainingProgressStruct.TrainAccuracy(1:maxPoints/2) = ...
            interp1(mibDeepTrainingProgressStruct.TrainXvec, mibDeepTrainingProgressStruct.TrainAccuracy, linvec);
        mibDeepTrainingProgressStruct.TrainXvec(1:maxPoints/2) = linvec;
    end

    if mibDeepTrainingProgressStruct.ValidationXvecIndex > maxPoints
        mibDeepTrainingProgressStruct.ValidationXvecIndex = maxPoints/2+1;
        linvec = linspace(1, mibDeepTrainingProgressStruct.ValidationXvec(maxPoints), maxPoints/2);
        mibDeepTrainingProgressStruct.ValidationLoss(1:maxPoints/2) = ...
            interp1(mibDeepTrainingProgressStruct.ValidationXvec, mibDeepTrainingProgressStruct.ValidationLoss, linvec);
        mibDeepTrainingProgressStruct.ValidationAccuracy(1:maxPoints/2) = ...
            interp1(mibDeepTrainingProgressStruct.ValidationXvec, mibDeepTrainingProgressStruct.ValidationAccuracy, linvec);
        mibDeepTrainingProgressStruct.ValidationXvec(1:maxPoints/2) = linvec;

        mibDeepTrainingProgressStruct.ValidationLoss(2:maxPoints/2) = ...
            (mibDeepTrainingProgressStruct.ValidationLoss(2:2:maxPoints-1) + mibDeepTrainingProgressStruct.ValidationLoss(3:2:maxPoints)) / 2;
        mibDeepTrainingProgressStruct.ValidationAccuracy(2:maxPoints/2) = ...
            (mibDeepTrainingProgressStruct.ValidationAccuracy(2:2:maxPoints-1) + mibDeepTrainingProgressStruct.ValidationAccuracy(3:2:maxPoints)) / 2;
    end
end

stopState = mibDeepStopTraining;
drawnow;
end
