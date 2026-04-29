function saveCheckpointNetworkCheck(obj)
% SAVECHECKPOINTNETWORKCHECK - callback for press of Save checkpoint networks (obj.view.handles.T_SaveProgress).
%
% Syntax:
%   function saveCheckpointNetworkCheck(obj)
%
    obj.BatchOpt.T_SaveProgress = obj.view.handles.T_SaveProgress.Value;
    if obj.BatchOpt.T_SaveProgress
        prompts = {'Frequency of saving checkpoint networks, once in N epochs:'};
        defAns = struct('Value', obj.TrainingOpt.CheckpointFrequency, 'Limits', [1 Inf], 'Step', 1, 'Round', true);
        dlgTitle = 'Checkpoint frequency';
        options.PromptLines = 2;
        answer = utils.dlgs.inputSingleDlg(obj.view.gui, prompts, defAns, dlgTitle, options);
        if isempty(answer); return; end
        
        obj.TrainingOpt.CheckpointFrequency = answer;
    end
end

