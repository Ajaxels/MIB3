function previewPredictions(obj)
    % function previewPredictions(obj)
    % load images of prediction scores into MIB

    scoreDir = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsScores');

    switch obj.BatchOpt.P_ScoreFiles{1}
        case 'Use AM format'
            fnList = dir(fullfile(scoreDir, '*.am'));
        case {'Use Matlab non-compressed format', 'Use Matlab compressed format'}
            fnList = dir(fullfile(scoreDir, '*.mibImg'));
        otherwise
            fnList = [];
    end

    if isempty(fnList)
        mgsOpt.MsgBoxOnly = true;
        mgsOpt.Header = sprintf('No files with predictions were found in\n%s\n\nPlease update the Directory with resulting images field of the Directories and Preprocessing tab!', scoreDir);
        mgsOpt.Icon = 'puffin_error';
        utils.dlgs.inputUniversalDlg(obj.view.gui, {}, {}, 'Missing files', mgsOpt);
        return;
    end
    if strcmp(obj.BatchOpt.Workflow{1}(1:2), '3D')  % take only the first file for 3D case
        BatchOptIn.Filenames = {{fullfile(scoreDir, fnList(1).name)}};
    else
        BatchOptIn.Filenames = {arrayfun(@(filename) fullfile(scoreDir, cell2mat(filename)), {fnList.name}, 'UniformOutput', false)};  % generate full paths
    end
    BatchOptIn.UseBioFormats = false;
    obj.mibController.mibFilesListbox_cm_Callback([], BatchOptIn);
end

