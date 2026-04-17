function saveCheckpointNetworkCheck(obj)
    % function saveCheckpointNetworkCheck(obj)
    % callback for press of Save checkpoint networks (obj.view.handles.T_SaveProgress)
    obj.BatchOpt.T_SaveProgress = obj.view.handles.T_SaveProgress.Value;
    if obj.mibController.matlabVersion >= 9.11 && obj.BatchOpt.T_SaveProgress
        prompts = {'Frequency of saving checkpoint networks, once in N epochs:'};
        defAns = {num2str(obj.TrainingOpt.CheckpointFrequency)};
        dlgTitle = 'Checkpoint frequency';
        options.PromptLines = 2;
        answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, dlgTitle, options);
        if isempty(answer); return; end
        obj.TrainingOpt.CheckpointFrequency = str2double(answer{1});
    end
end

