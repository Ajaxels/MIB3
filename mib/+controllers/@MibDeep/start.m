function start(obj, event)
% START - start calcualtions, depending on the selected tab.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.start(event)
%
% preprocessing, training, or prediction is initialized

    global mibDeepStopTraining     % variable to define stop of training (when true)

    % Every branch below blocks MATLAB behind a modal dialog, a progress bar or a long
    % training / prediction run. A key release in the main MIB window is not delivered
    % while that is going on, so mibController.currentModifier (and the brush radius
    % enlarged by the Ctrl eraser mode) can still claim Ctrl is held long after the user
    % let go - and the next scroll over the image then resizes the brush instead of
    % changing the slice. gui_WindowKeyReleaseFcn is exactly the "no key is held any
    % more" cleanup, so call it on every exit path, error paths included.
    clearStaleModifier = onCleanup(@() localReleaseModifierKeys(obj));

    switch event.Source.Tag
        case 'PreprocessButton'
            obj.startPreprocessing();
        case 'TrainButton'
            switch obj.view.handles.TrainButton.Text
                case 'Stop training'
                    % stop training by pressing the Stop Train button
                    % in the main DeepMIB window

                    mibDeepStopTraining = true;
                    obj.view.handles.TrainButton.Text = 'Stopping...';
                    obj.view.handles.TrainButton.BackgroundColor = utils.themeColors(obj.view.gui).dialogClose;
                    return;
                case 'Stopping...'
                    obj.view.handles.TrainButton.Text = 'Train';
                    obj.view.handles.TrainButton.BackgroundColor = utils.themeColors(obj.view.gui).panelBlue;
                    return;
            end

            if strcmp(obj.view.Figure.GPUDropDown.Value, 'Multi-GPU')
                if obj.BatchOpt.O_CustomTrainingProgressWindow
                    prompts = {'Follow the training progress using:'};
                    defAns = {{'Console printout', 'MATLAB progress window (requires MATLAB)', 1}};
                    dlgTitle = 'Progress window';
                    options.WindowStyle = 'normal';
                    options.Header = sprintf(['!!! Warning !!!\n\n' ...
                        'Multi-GPU training is not compatible with the custom MIB progress window!\n' ...
                        'Would you like to use any of these options?']);
                    options.HeaderLines = 5;
                    options.WindowWidth = 540;
                    [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, dlgTitle, options);
                    if isempty(answer); return; end

                    % turn off custom progress plot
                    obj.view.handles.O_CustomTrainingProgressWindow.Value = 0;
                    customEvent.Source = obj.view.handles.O_CustomTrainingProgressWindow;
                    customEvent.Value = 0;
                    obj.customTrainingProgressWindow_Callback(customEvent);

                    switch answer{1}
                        case 'Console printout'
                            obj.TrainingOpt.Plots = 'none';
                        case 'MATLAB progress window (requires MATLAB)'
                            obj.TrainingOpt.Plots = 'training-progress';
                    end
                end
            end
            if strcmp(obj.BatchOpt.Workflow{1}, '2D Instance')
                obj.startTrainingInstances(); % do instance segmentation
            else
                obj.startTraining(); % do semantic segmentation
            end
        case 'PredictButton'
            if strcmp(obj.BatchOpt.Workflow{1}, '2D Instance')
                % instance segmentation prediction has its own dedicated path,
                % independent of the Blocked-image / Legacy prediction engines
                try
                    obj.startPredictionInstances();
                catch err
                    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Instance prediction error');
                end
                return;
            end
            if strcmp(obj.BatchOpt.P_PredictionMode{1}, 'Blocked-image')
                try
                    obj.startPredictionBlockedImage(); % new version for R2021a and MIB 2.83
                catch err
                    utils.dlgs.showErrorDialog(obj.view.gui, err, 'BlockedImage prediction error');
                    return;
                end
            else
                if ismember(obj.BatchOpt.Workflow{1}, {'2D Patch-wise', '2.5D Semantic'})
                    mgsOpt.MsgBoxOnly = true;
                    mgsOpt.headerLines = 2;
                    mgsOpt.WindowHeight = 180;
                    mgsOpt.Icon = 'puffin_error';
                    header = sprintf('%s workflow can only be processed using the Blocked-image prediction mode', obj.BatchOpt.Workflow{1});
                    msgText = sprintf('Switch the Prediction engine:\n    "Legacy" -> "Blocked-image"');
                    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {msgText}, 'Wrong prediction mode', mgsOpt);
                    return;
                end
                if strcmp(obj.BatchOpt.Workflow{1}(1:2), '2D')
                    obj.startPrediction2D();
                else
                    obj.startPrediction3D();
                end
            end
    end

    % redraw the image if needed
    % notify(obj.mibModel, 'plotImage');

    % for batch need to generate an event and send the BatchOptLoc
    % structure with it to the macro recorder / mibBatchController
    %obj.returnBatchOpt();
end

function localReleaseModifierKeys(obj)
% never let a cleanup failure surface as the outcome of a finished training run
try
    if isvalid(obj) && ~isempty(obj.mibController) && isvalid(obj.mibController)
        obj.mibController.gui_WindowKeyReleaseFcn([], []);
    end
catch
end
end

