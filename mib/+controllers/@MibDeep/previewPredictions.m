function previewPredictions(obj)
% PREVIEWPREDICTIONS - load images of prediction scores into MIB.
%
% Syntax:
%   function previewPredictions(obj)
%

scoreDir = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsScores');

switch obj.BatchOpt.P_ScoreFiles{1}
    case 'Use AM format'
        fnList = dir(fullfile(scoreDir, '*.am'));
    case {'Use Matlab non-compressed format', 'Use Matlab compressed format'}
        fnList = dir(fullfile(scoreDir, '*.mibImg'));
    case 'Use Matlab non-compressed format (range 0-1)'
        fnList = dir(fullfile(scoreDir, '*.mat'));
        mgsOpt.MsgBoxOnly = true;
        mgsOpt.headerLines = 2;
        mgsOpt.WindowWidth = 550;
        mgsOpt.WindowHeight = 210;
        msgText = sprintf('It is possible to load the files manually using the following command:\nload("%s");\nload(%s);', fnList(1).name, fullfile(fnList(1).folder, fnList(1).name));
        utils.dlgs.inputUniversalDlg(obj.view.gui, 'Loading of "Matlab non-compressed format (range 0-1)" is not yet implemented', {}, {msgText}, 'Ops!', mgsOpt);
        return;

    otherwise
        fnList = [];
end

if isempty(fnList)
    mgsOpt.MsgBoxOnly = true;
    mgsOpt.headerLines = 1;
    mgsOpt.WindowHeight = 220;
    msgText = sprintf('No files with predictions were found in\n%s\n\nPlease update the Directory with resulting images field of the Directories and Preprocessing tab!', scoreDir);
    utils.dlgs.inputUniversalDlg(obj.view.gui, 'No files with predictions were found', {}, {msgText}, 'Missing files', mgsOpt);
    return;
end
if strcmp(obj.BatchOpt.Workflow{1}(1:2), '3D')  % take only the first file for 3D case
    BatchOptIn.Filenames = {fullfile(scoreDir, fnList(1).name)};
else
    BatchOptIn.Filenames = arrayfun(@(filename) fullfile(scoreDir, cell2mat(filename)), {fnList.name}, 'UniformOutput', false);  % generate full paths
end
BatchOptIn.UseBioFormats = false;
obj.mibModel.currentDirectory = scoreDir;
obj.mibModel.loadImages([], BatchOptIn);
end

