function updateWidgets(obj)
% UPDATEWIDGETS - update widgets of this window.
%
% Syntax:
%   function updateWidgets(obj)
%

    % updateWidgets normally triggered during change of MIB
    % buffers, make sure that any widgets related changes are
    % correctly propagated into the BatchOpt structure
    if isfield(obj.BatchOpt, 'id'); obj.BatchOpt.id = obj.mibModel.Id; end

    % update lined widgets
    event.Source.Tag = 'BioformatsTraining';
    obj.bioformatsCallback(event);
    event.Source.Tag = 'Bioformats';
    obj.bioformatsCallback(event);

    if strcmp(obj.BatchOpt.T_ConvolutionPadding{1}, 'same')
        obj.view.Figure.P_OverlappingTiles.Enable = 'on';
        obj.view.Figure.P_OverlappingTilesPercentage.Enable = 'on';
    else    % valid
        obj.view.Figure.P_OverlappingTiles.Enable = 'off';
        obj.view.Figure.P_OverlappingTiles.Value = false;
        obj.BatchOpt.P_OverlappingTiles = false;
        obj.view.Figure.P_OverlappingTilesPercentage.Enable = 'off';
    end

    if strcmp(obj.BatchOpt.Workflow{1}, obj.view.handles.Workflow.Value) == 0
        obj.view.handles.Workflow.Value = obj.BatchOpt.Workflow{1};
        obj.selectWorkflow();
    end

    % when elements GIU needs to be updated, update obj.BatchOpt
    % structure and after that update elements of GUI by the
    % following function
    obj.view = utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);    %

    % checking the folders
    foldersOk = 1;
    if ~isfolder(obj.BatchOpt.OriginalTrainingImagesDir)
        obj.BatchOpt.OriginalTrainingImagesDir = obj.mibModel.currentDirectory;
        obj.view.Figure.OriginalTrainingImagesDir.Value = obj.mibModel.currentDirectory;
        foldersOk = 0;
    end
    if ~isfolder(obj.BatchOpt.OriginalPredictionImagesDir)
        obj.BatchOpt.OriginalPredictionImagesDir = obj.mibModel.currentDirectory;
        obj.view.Figure.OriginalPredictionImagesDir.Value = obj.mibModel.currentDirectory;
        foldersOk = 0;
    end
    if ~isfolder(obj.BatchOpt.ResultingImagesDir)
        obj.BatchOpt.ResultingImagesDir = obj.mibModel.currentDirectory;
        obj.view.Figure.ResultingImagesDir.Value = obj.mibModel.currentDirectory;
        foldersOk = 0;
    end

    if obj.view.handles.UseParallelComputing.Value
        obj.view.handles.PreprocessingParForWorkers.Enable = 'on';
    else
        obj.view.handles.PreprocessingParForWorkers.Enable = 'off';
    end

    % sync number of classes between training and preprocessing tabs
    obj.view.handles.NumberOfClassesPreprocessing.Value = obj.BatchOpt.T_NumberOfClasses{1};

    obj.selectWorkflow();
    obj.singleModelTrainingFileValueChanged();

    % update preprocessing window widgets
    if strcmp(obj.BatchOpt.PreprocessingMode{1}, 'Preprocessing is not required') || strcmp(obj.BatchOpt.PreprocessingMode{1}, 'Split files for training/validation')
        obj.view.handles.CompressProcessedImages.Enable = 'off';
        obj.view.handles.CompressProcessedModels.Enable = 'off';
    else
        if obj.BatchOpt.Workflow{1}(1) == '2'
            obj.view.handles.SingleModelTrainingFile.Enable = 'on';
        end
        obj.view.handles.CompressProcessedImages.Enable = 'on';
        obj.view.handles.CompressProcessedModels.Enable = 'on';
    end

    if obj.BatchOpt.Workflow{1}(1) == '3'
        obj.view.handles.ModelFilenameExtension.Enable = 'off';
        obj.view.handles.MaskFilenameExtension.Enable = 'off';
    end

    % override settings when the instance segmentation mode is used
    if strcmp(obj.BatchOpt.Workflow{1}, '2D Instance')
        obj.view.handles.CompressProcessedImages.Enable = 'off'; % there is no image preprocessing for the instance segmentation
        obj.view.handles.NumberOfClassesPreprocessing.Enable = 'off';
        obj.view.handles.T_NumberOfClasses.Enable = 'off';
    else
        obj.view.handles.NumberOfClassesPreprocessing.Enable = 'on';
        obj.view.handles.T_NumberOfClasses.Enable = 'on';
    end

    % update widgets in Train panel
    obj.toggleAugmentations();
    obj.activationLayerChangeCallback();
    obj.setSegmentationLayer();

    % update widgets in Predict panel
    if strcmp(obj.BatchOpt.P_PredictionMode{1}, 'Blocked-image')
        obj.view.handles.P_DynamicMasking.Enable = 'on';
    else
        obj.view.handles.P_DynamicMasking.Enable = 'off';
    end

    % update widgets in Options panel
    if  obj.view.handles.O_CustomTrainingProgressWindow.Value
        obj.view.handles.O_RefreshRateIter.Enable = 'on';
        obj.view.handles.O_NumberOfPoints.Enable = 'on';
        obj.view.handles.O_PreviewImagePatches.Enable = 'on';
        if obj.view.handles.O_PreviewImagePatches.Value == 1
            obj.view.handles.O_FractionOfPreviewPatches.Enable = 'on';
        else
            obj.view.handles.O_FractionOfPreviewPatches.Enable = 'off';
        end
    else
        obj.view.handles.O_RefreshRateIter.Enable = 'off';
        obj.view.handles.O_NumberOfPoints.Enable = 'off';
        obj.view.handles.O_PreviewImagePatches.Enable = 'off';
        obj.view.handles.O_FractionOfPreviewPatches.Enable = 'off';
    end

    if foldersOk == 0 && obj.view.gui.Visible == true
        mgsOpt.MsgBoxOnly = true;
        header = sprintf('Some directories specified in the config file are missing!\nPlease check the directories in the Directories and Preprocessing tab');
        utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Wrong directories', mgsOpt);
    end

    obj.view.handles.T_SendReports.Value = obj.SendReports.T_SendReports;
end

