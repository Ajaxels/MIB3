function start(obj, event)
% START - start calcualtions, depending on the selected tab.
%
% Syntax:
%   function start(obj, event)
%
% preprocessing, training, or prediction is initialized

    global mibDeepStopTraining     % variable to define stop of training (when true)

    if strcmp(obj.BatchOpt.Workflow{1}, '2D Instance')
        mgsOpt.MsgBoxOnly = true;
        mgsOpt.Icon = 'puffin_info';
        utils.dlgs.inputUniversalDlg(obj.view.gui, 'Coming soon...', {}, {}, 'In progress', mgsOpt);
        return;
    end


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
                    obj.view.handles.TrainButton.BackgroundColor = [1 .5 0];
                    return;
                case 'Stopping...'
                    obj.view.handles.TrainButton.Text = 'Train';
                    obj.view.handles.TrainButton.BackgroundColor = [0.7686    0.9020    0.9882];
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

