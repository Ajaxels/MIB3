function stopState = customTrainingProgressDisplayTrainNet(progressStruct, trainingProgressOptions)
% CUSTOMTRAININGPROGRESSDISPLAYTRAINNET - Show custom progress dialog for DeepMIB training
% (alternative version for the ``trainnet`` engine).
%
% Syntax:
%   .. code-block:: matlab
%
%      stopState = customTrainingProgressDisplayTrainNet(progressStruct, trainingProgressOptions)
%
% Input Arguments:
%   - **progressStruct** - struct with current training progress (provided by ``trainnet``):
%
%     - ``.Epoch`` - current epoch number
%     - ``.Iteration`` - current iteration number
%     - ``.TimeElapsed`` - elapsed time as ``duration``, e.g. ``00:00:02``
%       (called ``TimeSinceStart`` in ``trainNetwork``)
%     - ``.LearnRate`` - current learning rate, e.g. ``0.0050``
%       (called ``BaseLearnRate`` in ``trainNetwork``)
%     - ``.TrainingLoss`` - current training loss, e.g. ``0.7802``
%     - ``.ValidationLoss`` - validation loss (``[]`` when training without validation)
%     - ``.TrainingAccuracy`` - training accuracy (%), e.g. ``26.9975``
%     - ``.ValidationAccuracy`` - validation accuracy (``[]`` when training without validation)
%     - ``.State`` - training phase string, e.g. ``'iteration'``
%
%   - **trainingProgressOptions** - struct with display/training parameters:
%
%     - ``.O_NumberOfPoints`` - [numeric] max points in the progress plot
%       (``mibDeepController.BatchOpt.O_NumberOfPoints{1}``)
%     - ``.NetworkFilename`` - [char] network file path
%       (``mibDeepController.BatchOpt.NetworkFilename``)
%     - ``.noColorChannels`` - [numeric] number of colour channels
%       (``str2num(obj.BatchOpt.T_InputPatchSize)(4)``)
%     - ``.Workflow`` - [char] active workflow (``obj.BatchOpt.Workflow{1}``)
%     - ``.Architecture`` - [char] network architecture (``obj.BatchOpt.Architecture{1}``)
%     - ``.refreshRateIter`` - [numeric] UI refresh rate in iterations
%       (``obj.BatchOpt.O_RefreshRateIter{1}``)
%     - ``.matlabVersion`` - [numeric] MATLAB release number (``obj.mibController.matlabVersion``)
%     - ``.iterPerEpoch`` - [numeric] iterations per epoch
%     - ``.sendNextReportAtEpoch`` - [numeric] epoch at which to send the next e-mail report
%     - ``.TrainingOpt.MaxEpochs`` - maximum number of training epochs
%     - ``.TrainingOpt.solverName`` - optimiser name string
%     - ``.TrainingOpt.Shuffle`` - dataset shuffle strategy
%     - ``.TrainingOpt.LearnRateSchedule`` - learning-rate schedule type
%     - ``.TrainingOpt.OutputNetwork`` - which network to save on each checkpoint
%     - ``.TrainingOpt.InitialLearnRate`` - initial learning rate
%     - ``.TrainingOpt.LearnRateDropPeriod`` - period (epochs) for learning-rate drop
%     - ``.TrainingOpt.ValidationPatience`` - early-stop patience (epochs)
%     - ``.TrainingOpt.ValidationFrequency`` - validation frequency (iterations)
%

global mibDeepStopTraining
global mibDeepTrainingProgressStruct

stopState =  false;

% get max number of points in the progress plot to show
maxPoints = trainingProgressOptions.O_NumberOfPoints;

if isempty(progressStruct.Iteration); return; end

if ~isfield(progressStruct, 'ValidationLoss'); progressStruct.ValidationLoss = []; end
if ~isfield(progressStruct, 'ValidationAccuracy'); progressStruct.ValidationAccuracy = []; end

if progressStruct.Iteration == 0
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
    FigPos(2) = 2/3*(ScreenSize(4)-620);
    mibDeepTrainingProgressStruct.UIFigure.Position = [FigPos(1), FigPos(2), 800, 620];
    [~, netName] = fileparts(trainingProgressOptions.NetworkFilename);
    mibDeepTrainingProgressStruct.UIFigure.Name = sprintf('Training progress (%s)', netName);

    % Create GridLayouts
    mibDeepTrainingProgressStruct.GridLayout = uigridlayout(mibDeepTrainingProgressStruct.UIFigure, [2, 1]);
    mibDeepTrainingProgressStruct.GridLayout.ColumnWidth = {'1x'};
    % The panel row is pinned to a pixel height instead of sharing the figure evenly with
    % the plot. Everything inside the three panels is positioned in absolute pixels, so a
    % row that grows and shrinks with the window leaves them stranded at the bottom. 305 is
    % 285 (what an even split of the old 600 px figure gave) plus the 20 px the new
    % Time/epoch line needs; the figure grew by the same 20 so the plot keeps its height.
    mibDeepTrainingProgressStruct.GridLayout.RowHeight = {'1x', 305};

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
    mibDeepTrainingProgressStruct.AccTrainGauge.Position = [6 28 40 210];
    mibDeepTrainingProgressStruct.AccValGauge = uigauge(mibDeepTrainingProgressStruct.AccuracyPanel, 'linear');
    mibDeepTrainingProgressStruct.AccValGauge.Orientation = 'vertical';
    mibDeepTrainingProgressStruct.AccValGauge.Position = [54 28 40 210];

    mibDeepTrainingProgressStruct.TrainingLabel = uilabel(mibDeepTrainingProgressStruct.AccuracyPanel);
    mibDeepTrainingProgressStruct.TrainingLabel.Position = [10 241 48 22];
    mibDeepTrainingProgressStruct.TrainingLabel.Text = 'Train';

    mibDeepTrainingProgressStruct.ValidationLabel = uilabel(mibDeepTrainingProgressStruct.AccuracyPanel);
    mibDeepTrainingProgressStruct.ValidationLabel.HorizontalAlignment = 'center';
    mibDeepTrainingProgressStruct.ValidationLabel.Position = [46 241 57 22];
    mibDeepTrainingProgressStruct.ValidationLabel.Text = 'Valid.';

    mibDeepTrainingProgressStruct.AccTrainingValue = uilabel(mibDeepTrainingProgressStruct.AccuracyPanel);
    mibDeepTrainingProgressStruct.AccTrainingValue.Position = [7 3 48 22];
    mibDeepTrainingProgressStruct.AccTrainingValue.Text = '0';

    mibDeepTrainingProgressStruct.AccValidationValue = uilabel(mibDeepTrainingProgressStruct.AccuracyPanel);
    mibDeepTrainingProgressStruct.AccValidationValue.Position = [55 3 48 22];
    mibDeepTrainingProgressStruct.AccValidationValue.Text = '0';

    mibDeepTrainingProgressStruct.TrainingProgress = uilabel(mibDeepTrainingProgressStruct.InformationPanel);
    % 385 wide (the full panel width from x=7) rather than 220: the plain device name
    % already needed 182 px, and the memory figure appended by
    % deepmib.updateGpuMemoryStatus takes it to 296, or 361 with the overcommit marker
    mibDeepTrainingProgressStruct.TrainingProgress.Position = [7 238 385 22];
    mibDeepTrainingProgressStruct.TrainingProgress.FontWeight = 'bold';
    mibDeepTrainingProgressStruct.TrainingProgress.Text = trainingProgressOptions.gpuDevice;

    % GPU memory / overcommit tracking, see deepmib.updateGpuMemoryStatus
    mibDeepTrainingProgressStruct.gpuBaseLabel = '';
    mibDeepTrainingProgressStruct.gpuTotalMemory = 0;
    mibDeepTrainingProgressStruct.gpuPeakUsed = 0;
    mibDeepTrainingProgressStruct.gpuRateSamples = [];
    mibDeepTrainingProgressStruct.gpuBaselineRate = NaN;
    mibDeepTrainingProgressStruct.gpuPrevIteration = 0;
    mibDeepTrainingProgressStruct.gpuPrevElapsed = 0;
    mibDeepTrainingProgressStruct.gpuSpillWarned = false;
    if isfield(trainingProgressOptions, 'executionEnvironment') && ...
            strcmp(trainingProgressOptions.executionEnvironment, 'gpu')
        try
            mibDeepTrainingProgressStruct.gpuTotalMemory = gpuDevice().TotalMemory;
            mibDeepTrainingProgressStruct.gpuBaseLabel = trainingProgressOptions.gpuDevice;
        catch
            % no usable device, leave gpuBaseLabel empty and the reporting stays off
        end
    end

    mibDeepTrainingProgressStruct.StartTime = uilabel(mibDeepTrainingProgressStruct.InformationPanel);
    mibDeepTrainingProgressStruct.StartTime.Position = [7 216 184 22];
    mibDeepTrainingProgressStruct.StartTime.Text = sprintf('Started: %s', datetime('now'));

    mibDeepTrainingProgressStruct.ElapsedTime = uilabel(mibDeepTrainingProgressStruct.InformationPanel);
    mibDeepTrainingProgressStruct.ElapsedTime.Position = [7 196 184 22];
    mibDeepTrainingProgressStruct.ElapsedTime.Text = 'Elapsed: --.--.--';

    mibDeepTrainingProgressStruct.TimeToGo = uilabel(mibDeepTrainingProgressStruct.InformationPanel);
    mibDeepTrainingProgressStruct.TimeToGo.Position = [7 176 184 22];
    mibDeepTrainingProgressStruct.TimeToGo.Text = 'Time to go: --.--.--';

    % Last of the four time lines, on the same 20 px pitch as the three above it, which
    % leaves the wider gap before Epoch untouched
    mibDeepTrainingProgressStruct.TimePerEpoch = uilabel(mibDeepTrainingProgressStruct.InformationPanel);
    mibDeepTrainingProgressStruct.TimePerEpoch.Position = [7 156 184 22];
    mibDeepTrainingProgressStruct.TimePerEpoch.Text = 'Time/epoch: --.--.--';
    mibDeepTrainingProgressStruct.TimePerEpoch.Tooltip = ...
        'Average wall-clock time one epoch takes so far, and the same figure per iteration';

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
    mibDeepTrainingProgressStruct.IterationsPerEpoch.Position = [192 216 202 22];
    mibDeepTrainingProgressStruct.IterationsPerEpoch.Text = sprintf('Iterations per epoch: %d', trainingProgressOptions.iterPerEpoch);

    mibDeepTrainingProgressStruct.Solver = uilabel(mibDeepTrainingProgressStruct.InformationPanel);
    mibDeepTrainingProgressStruct.Solver.Position = [192 196 202 22];
    mibDeepTrainingProgressStruct.Solver.Text = sprintf('Solver name: %s', trainingProgressOptions.TrainingOpt.solverName);

    mibDeepTrainingProgressStruct.TrainingOpt.Shuffle = uilabel(mibDeepTrainingProgressStruct.InformationPanel);
    mibDeepTrainingProgressStruct.TrainingOpt.Shuffle.Position = [192 176 202 22];
    mibDeepTrainingProgressStruct.TrainingOpt.Shuffle.Text = sprintf('Shuffle: %s', trainingProgressOptions.TrainingOpt.Shuffle);

    mibDeepTrainingProgressStruct.TrainingOpt.LearnRateSchedule = uilabel(mibDeepTrainingProgressStruct.InformationPanel);
    mibDeepTrainingProgressStruct.TrainingOpt.LearnRateSchedule.Position = [192 156 202 22];
    mibDeepTrainingProgressStruct.TrainingOpt.LearnRateSchedule.Text = sprintf('Learn rate schedule: %s', trainingProgressOptions.TrainingOpt.LearnRateSchedule);

    zLinePos = 126;
    if trainingProgressOptions.matlabVersion >= 9.11
        mibDeepTrainingProgressStruct.TrainingOpt.OutputNetwork = uilabel(mibDeepTrainingProgressStruct.InformationPanel);
        mibDeepTrainingProgressStruct.TrainingOpt.OutputNetwork.Position = [192 136 202 22];
        mibDeepTrainingProgressStruct.TrainingOpt.OutputNetwork.Text = sprintf('Output network: %s', trainingProgressOptions.TrainingOpt.OutputNetwork);
        zLinePos = 106;
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
    mibDeepTrainingProgressStruct.UILossAxes_cm_setYmin.MenuSelectedFcn = @(src, evnt)deepmib.trainingStructUpdateAxes(src, evnt, 'setYlimits');
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
    mibDeepTrainingProgressStruct.imgPatch.Position = [6 143 116 116];
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
        stopState = true;
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
            ], ...
            fn, ...
            mibDeepTrainingProgressStruct.Epoch.Text, mibDeepTrainingProgressStruct.IterationNumberValue.Text, ...
            mibDeepTrainingProgressStruct.StartTime.Text, mibDeepTrainingProgressStruct.ElapsedTime.Text, mibDeepTrainingProgressStruct.TimeToGo.Text, ...
            progressStruct.TrainingLoss(end) );
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
    % when 'Metrics', 'accuracy' is defined progressStruct.TrainingAccuracy
    % is defined but it is empty in the semantic segmetation tasks, but
    % present in the quantification tasks
    % if ~isempty(progressStruct.TrainingAccuracy)
    %     mibDeepTrainingProgressStruct.TrainAccuracy(mibDeepTrainingProgressStruct.TrainXvecIndex) = progressStruct.TrainingAccuracy;
    % else
    %     mibDeepTrainingProgressStruct.TrainAccuracy(mibDeepTrainingProgressStruct.TrainXvecIndex) = NaN;
    % end
    mibDeepTrainingProgressStruct.TrainXvecIndex = mibDeepTrainingProgressStruct.TrainXvecIndex + 1;

    mibDeepTrainingProgressStruct.hPlot(1).XData = mibDeepTrainingProgressStruct.TrainXvec(1:mibDeepTrainingProgressStruct.TrainXvecIndex-1);
    mibDeepTrainingProgressStruct.hPlot(1).YData = mibDeepTrainingProgressStruct.TrainLoss(1:mibDeepTrainingProgressStruct.TrainXvecIndex-1);
    if ~isnan(progressStruct.TrainingAccuracy)
        mibDeepTrainingProgressStruct.AccTrainGauge.Value = progressStruct.TrainingAccuracy;
    end
    mibDeepTrainingProgressStruct.AccTrainingValue.Text = sprintf('%.2f%%', progressStruct.TrainingAccuracy);

    if isfield(progressStruct, 'TimeSinceStart') % when trainNetwork is used
        mibDeepTrainingProgressStruct.ElapsedTime.Text = ...
            sprintf('Elapsed time: %.0f h %.0f min %.2d sec', floor(progressStruct.TimeSinceStart/3600), floor(mod(round(progressStruct.TimeSinceStart),3600)/60), mod(round(progressStruct.TimeSinceStart),60));
        timerValue = progressStruct.TimeSinceStart/progressStruct.Iteration*(mibDeepTrainingProgressStruct.maxIter-progressStruct.Iteration);
        mibDeepTrainingProgressStruct.TimeToGo.Text = ...
            sprintf('Time to go: ~%.0f h %.0f min %.2d sec', floor(timerValue/3600), floor(mod(round(timerValue),3600)/60), mod(round(timerValue),60));
        mibDeepTrainingProgressStruct.BaseLearnRate.Text = sprintf('Base learn rate: %.3e', progressStruct.BaseLearnRate);
        elapsedSeconds = progressStruct.TimeSinceStart;
    else %  when trainnet is used
        mibDeepTrainingProgressStruct.ElapsedTime.Text = sprintf('Elapsed time: %s sec', progressStruct.TimeElapsed);
        timerValue = progressStruct.TimeElapsed/progressStruct.Iteration*(mibDeepTrainingProgressStruct.maxIter-progressStruct.Iteration);
        mibDeepTrainingProgressStruct.TimeToGo.Text = sprintf('Time to go: ~%s sec', timerValue);
        mibDeepTrainingProgressStruct.BaseLearnRate.Text = sprintf('Base learn rate: %.3e', progressStruct.LearnRate); % renamed to LearnRate
        elapsedSeconds = progressStruct.TimeElapsed;
        % trainnet reports this as a duration while trainNetwork uses plain seconds;
        % comparing a duration against a double below would error, so normalize first
        if isduration(elapsedSeconds); elapsedSeconds = seconds(elapsedSeconds); end
    end

    % Pace of the run. Derived from the iteration count rather than progressStruct.Epoch,
    % which is an integer and would leave the line empty for the whole of a long first
    % epoch; iteration/iterPerEpoch gives a usable number from the first refresh.
    if trainingProgressOptions.iterPerEpoch > 0 && progressStruct.Iteration > 0 && elapsedSeconds > 0
        secondsPerIteration = elapsedSeconds / progressStruct.Iteration;
        secondsPerEpoch = secondsPerIteration * trainingProgressOptions.iterPerEpoch;
        mibDeepTrainingProgressStruct.TimePerEpoch.Text = ...
            sprintf('Time/epoch: %.0f h %.0f min %.2d sec', floor(secondsPerEpoch/3600), ...
            floor(mod(round(secondsPerEpoch),3600)/60), mod(round(secondsPerEpoch),60));
        mibDeepTrainingProgressStruct.TimePerEpoch.Tooltip = ...
            sprintf('%.3g sec per iteration over %d iterations of %g per epoch', ...
            secondsPerIteration, progressStruct.Iteration, trainingProgressOptions.iterPerEpoch);
    end

    % GPU memory headroom, plus the one-off warning when the card is overcommitted
    deepmib.updateGpuMemoryStatus(progressStruct.Iteration, elapsedSeconds);
    mibDeepTrainingProgressStruct.Epoch.Text = sprintf('Epoch: %d of %d', progressStruct.Epoch, trainingProgressOptions.TrainingOpt.MaxEpochs);
    mibDeepTrainingProgressStruct.IterationNumberValue.Text = sprintf('%d of %d', progressStruct.Iteration, round(mibDeepTrainingProgressStruct.maxIter));
    % maxIter is an estimate (iterations per epoch x epochs), so clamp: the gauge limits
    % are [0 100] and a needle drawn past the edge looks like a fault rather than an
    % off-by-one in the estimate
    mibDeepTrainingProgressStruct.ProgressGauge.Value = min(100, progressStruct.Iteration/mibDeepTrainingProgressStruct.maxIter*100);
    

    if ~isempty(progressStruct.ValidationLoss)
        mibDeepTrainingProgressStruct.ValidationXvec(mibDeepTrainingProgressStruct.ValidationXvecIndex) = progressStruct.Iteration;
        mibDeepTrainingProgressStruct.ValidationLoss(mibDeepTrainingProgressStruct.ValidationXvecIndex) = progressStruct.ValidationLoss;
        mibDeepTrainingProgressStruct.ValidationAccuracy(mibDeepTrainingProgressStruct.ValidationXvecIndex) = progressStruct.ValidationAccuracy;
        mibDeepTrainingProgressStruct.ValidationXvecIndex = mibDeepTrainingProgressStruct.ValidationXvecIndex + 1;

        mibDeepTrainingProgressStruct.hPlot(2).XData = mibDeepTrainingProgressStruct.ValidationXvec(1:mibDeepTrainingProgressStruct.ValidationXvecIndex-1);
        mibDeepTrainingProgressStruct.hPlot(2).YData = mibDeepTrainingProgressStruct.ValidationLoss(1:mibDeepTrainingProgressStruct.ValidationXvecIndex-1);
        if ~isnan(progressStruct.ValidationAccuracy)
            mibDeepTrainingProgressStruct.AccValGauge.Value = progressStruct.ValidationAccuracy;
        end
        mibDeepTrainingProgressStruct.AccValidationValue.Text = sprintf('%.2f%%', progressStruct.ValidationAccuracy);

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
