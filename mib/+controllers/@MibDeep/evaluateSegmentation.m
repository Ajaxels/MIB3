function evaluateSegmentation(obj)
% EVALUATESEGMENTATION - evaluate segmentation results by comparing predicted models.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.evaluateSegmentation()
%
% with the ground truth models
% check for evaluation of patches in the patch-wise mode
if exist(fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels', 'patchPredictionResults.mat'), 'file') == 2
    obj.evaluateSegmentationPatches();
    return;
end

if strcmp(obj.BatchOpt.PreprocessingMode{1}, 'Preprocessing is not required') || ...
        strcmp(obj.BatchOpt.PreprocessingMode{1}, 'Split files for training/validation') || ...
        strcmp(obj.BatchOpt.PreprocessingMode{1}, 'Training')
    preprocessedSwitch = false;
    truthDir = fullfile(obj.BatchOpt.OriginalPredictionImagesDir, 'Labels');
    truthList = dir(fullfile(truthDir, lower(['*.' obj.BatchOpt.ModelFilenameExtension{1}])));
else
    preprocessedSwitch = true;
    truthDir = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'GroundTruthLabels');
    truthList = dir(fullfile(truthDir, '*.mibCat'));
end

predictionDir = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels');
switch obj.BatchOpt.P_ModelFiles{1}
    case 'MIB Model format'
        modelFileExtension = '*.model';
    case {'TIF compressed format', 'TIF uncompressed format'}
        modelFileExtension = '*.tif';
end
predictionList = dir(fullfile(predictionDir, lower(modelFileExtension)));

if isempty(truthList) && isempty(predictionList)
    mgsOpt.MsgBoxOnly = true;
    mgsOpt.headerLines = 1;
    mgsOpt.WindowWidth = 600;
    mgsOpt.WindowHeight = 260;
    msgText = sprintf('Ground truth labels folder:\n%s\n\nPredicted labels folder:%s\n\nPlease update the Directory prediction and resulting images fields of the Directories and Preprocessing tab!', truthDir, predictionDir);
    utils.dlgs.inputUniversalDlg(obj.view.gui, 'Ground truth or predicted labels were not found!', {}, {msgText}, 'Missing files', mgsOpt);
    return;
end

prompts = { sprintf('Accuracy:\nthe percentage of correctly identified pixels for each class');...
    sprintf('bfscore:\nthe boundary F1 (BF) contour matching score\nindicates how well the predicted boundary of each\nclass aligns with the true boundary');...
    sprintf('Global Accuracy:\nthe ratio of correctly classified pixels,\nregardless of class, to the total number of pixels'); ...
    sprintf('IOU (Jaccard similarity coefficient):\nIntersection over union, a statistical accuracy\nmeasurement that penalizes false positives'); ...
    sprintf('Weighted IOU:\naverage IoU of each class,\nweighted by the number of pixels in that class');
    };
defAns = {obj.mibModel.preferences.Deep.Metrics.Accuracy; ...
    obj.mibModel.preferences.Deep.Metrics.BFscore; ...
    obj.mibModel.preferences.Deep.Metrics.GlobalAccuracy; ...
    obj.mibModel.preferences.Deep.Metrics.IOU; ...
    obj.mibModel.preferences.Deep.Metrics.WeightedIOU; ...
    };

dlgTitle = 'Evaluation settings';
options.Header = sprintf('Please select the metrics from the options below\nKeep in mind that the evaluation processs in rather slow\nRatio of execution times for each metric: 0.10 x 0.78 x 0.04 x 0.03 x 0.05');
options.WindowStyle = 'normal';
options.PromptLines = [1, 1, 1, 1, 1];
options.WindowWidth = 550;
options.WindowHeight = 400;
options.HeaderLines = 3;
options.LabelPosition = 'left';
options.HelpUrl = 'https://se.mathworks.com/help/vision/ref/evaluatesemanticsegmentation.html';

[answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, dlgTitle, options);
if isempty(answer); return; end

obj.mibModel.preferences.Deep.Metrics.Accuracy = logical(answer{1});
obj.mibModel.preferences.Deep.Metrics.BFscore = logical(answer{2});
obj.mibModel.preferences.Deep.Metrics.GlobalAccuracy = logical(answer{3});
obj.mibModel.preferences.Deep.Metrics.IOU = logical(answer{4});
obj.mibModel.preferences.Deep.Metrics.WeightedIOU = logical(answer{5});

metricsList = {};
if obj.mibModel.preferences.Deep.Metrics.Accuracy;          metricsList = [metricsList, {'accuracy'}]; end
if obj.mibModel.preferences.Deep.Metrics.BFscore;           metricsList = [metricsList, {'bfscore'}]; end
if obj.mibModel.preferences.Deep.Metrics.GlobalAccuracy;    metricsList = [metricsList, {'global-accuracy'}]; end
if obj.mibModel.preferences.Deep.Metrics.IOU;               metricsList = [metricsList, {'iou'}]; end
if obj.mibModel.preferences.Deep.Metrics.WeightedIOU;       metricsList = [metricsList, {'weighted-iou'}]; end
if isempty(metricsList); return; end

% get class names
switch obj.BatchOpt.P_ModelFiles{1}
    case 'MIB Model format'
        modelFn = fullfile(predictionList(1).folder, predictionList(1).name);
        res = load(modelFn, '-mat', 'modelMaterialNames');
        classNames = [{'Exterior'}; res.modelMaterialNames];    % add Exterior
    case {'TIF compressed format', 'TIF uncompressed format'}
        if preprocessedSwitch   % for tifs get the class names from the preprocessed file
            res = load(fullfile(truthDir, truthList(1).name), '-mat', 'options');
            classNames = res.options.modelMaterialNames;
        else % if it is not available, try to get from model file or generate fake names
            switch obj.BatchOpt.ModelFilenameExtension{1}
                case 'MODEL'
                    res = load(fullfile(truthDir, truthList(1).name), '-mat', 'modelMaterialNames');
                    classNames = [{'Exterior'}; res.modelMaterialNames];    % add Exterior
                otherwise
                    % material names not present generate fake ones
                    classNames = arrayfun(@(x) sprintf('Class%.2d', x), 1:obj.BatchOpt.T_NumberOfClasses{1}-1, 'UniformOutput', false);
                    classNames = [{'Exterior'}; classNames'];
            end
        end
end
if strcmp(obj.BatchOpt.Workflow{1}, '2D Patch-wise') % patch-wise mode
    classNames(ismember(classNames, 'Exterior')) = [];
    pixelLabelID = 1:numel(classNames);
else
    pixelLabelID = 0:numel(classNames)-1;
end

try
    fullPathFilenames = arrayfun(@(filename) fullfile(truthDir, cell2mat(filename)), {truthList.name}, 'UniformOutput', false);  % generate full paths
    if preprocessedSwitch
        dsTruth = pixelLabelDatastore(fullPathFilenames, classNames, pixelLabelID, ...
            'FileExtensions', '.mibCat', 'ReadFcn', @deepmib.storeLoadImages);
    else
        switch obj.BatchOpt.ModelFilenameExtension{1}
            case 'MODEL'
                dsTruth = pixelLabelDatastore(fullPathFilenames, classNames, pixelLabelID, ...
                    'FileExtensions', '.model', 'ReadFcn', @deepmib.storeLoadModel);
                % I = readimage(dsTruth,1);  % read model test
                % reset(dsTruth);
            otherwise
                dsTruth = pixelLabelDatastore(fullPathFilenames, classNames, pixelLabelID, ...
                    'FileExtensions', lower(['.' obj.BatchOpt.ModelFilenameExtension{1}]));
        end
    end
catch err
    optionalSuffix = sprintf('Check the ground truth directory:\n%s', truthDir);
    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Wrong class name', '', optionalSuffix);
    return;
end

fullPathFilenames = arrayfun(@(filename) fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels', cell2mat(filename)), {predictionList.name}, 'UniformOutput', false);  % generate full paths
switch obj.BatchOpt.P_ModelFiles{1}
    case 'MIB Model format'
        dsResults = pixelLabelDatastore(fullPathFilenames, classNames, pixelLabelID, ...
            'FileExtensions', '.model', 'ReadFcn', @deepmib.storeLoadModel);
    case {'TIF compressed format', 'TIF uncompressed format'}
        if strcmp(obj.BatchOpt.Workflow{1}(1:2), '2D')
            dsResults = pixelLabelDatastore(fullPathFilenames, classNames, pixelLabelID, ...
                'FileExtensions', '.tif');
        else
            % for 3D tif have to use a separate reading function
            dsResults = pixelLabelDatastore(fullPathFilenames, classNames, pixelLabelID, ...
                'FileExtensions', '.tif', 'ReadFcn', @MibDeep.tif3DFileRead);
        end
end

tic
pw = core.PoolWaitbar(2, sprintf('Starting evaluation\nit may take a while...'), obj.view.gui, 'Evaluate segmentation');
try
    ssm = evaluateSemanticSegmentation(dsResults, dsTruth, 'Metrics', metricsList);
catch err
    optionalSuffix = 'Most likely the class names in the GroundTruth do not match the class names of the model\nor alternatively, the ground truth model is in a single .MODEL file (preprecess the dataset in this case)';
    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Wrong class names', '', optionalSuffix);
end
pw.increment();

% convert ssm object to standard structure
ssmFields = fieldnames(ssm);
ssmStruct = struct();
% add additional info to ssmStruct
ssmStruct.Info.NetworkName = obj.BatchOpt.NetworkFilename;
ssmStruct.Info.PredictionResultsDirectory = predictionDir;
ssmStruct.Info.GroundTruthDirectory = truthDir;
% crate a table with name of files
fnTable = table({predictionList.name}', {truthList.name}', 'VariableNames', {'ModelFilename', 'GroundTruthFilename'});
% add calculated fields
for i=1:numel(ssmFields)
    ssmStruct.(ssmFields{i}) = ssm.(ssmFields{i});
end
% insert filenames into ssmStruct.ImageMetrics
ssmStruct.ImageMetrics = [fnTable ssmStruct.ImageMetrics];
pw.increment();
pw.deletePoolWaitbar();
toc

normConfMatData = ssm.NormalizedConfusionMatrix.Variables;
hF = figure;
screenSize = get (0,'screensize');
hF.Position(2) = screenSize(4)*.1;
hF.Position(4) = screenSize(4)*.7;
hF.Position(3) = hF.Position(4)*0.9;
clf
h = heatmap(classNames,classNames,100*normConfMatData, 'Position', [.15 .45 .7 .48]);
h.XLabel = 'Predicted Class';
h.YLabel = 'True Class';
[~, netName] = fileparts(obj.BatchOpt.NetworkFilename);
h.Title = sprintf('Normalized Confusion Matrix\n(%s)', strrep(netName, '_', '-'));
if max(ismember({'Accuracy','IoU','MeanBFScore'}, ssm.ClassMetrics.Properties.VariableNames))
    %h2 = heatmap(ssm.ClassMetrics.Properties.RowNames, {'IoU'}, ssm.ClassMetrics.IoU', 'Position', [.15 .02 .7 .15]);
    h2 = heatmap(ssm.ClassMetrics.Properties.RowNames, ssm.ClassMetrics.Properties.VariableNames, table2array(ssm.ClassMetrics)', ...
        'Position', [.15 .16 .7 .18]);
    h2.Title = 'Class metrics';
end
if numel(ssm.DataSetMetrics.Properties.VariableNames) > 0
    h3 = heatmap(ssm.DataSetMetrics.Properties.VariableNames, {'Dataset'}, table2array(ssm.DataSetMetrics), ...
        'Position', [.15 .07 .7 .045]);
end

% display results
metricName = ssm.DataSetMetrics.Properties.VariableNames;
metricValue = table2array(ssm.DataSetMetrics);

s = sprintf('Evaluation results\nfor details press the Help button and follow to the Metrics section\n\n');
s = sprintf('%sGlobalAccuracy: ratio of correctly classified pixels to total pixels, regardless of class\n', s);
s = sprintf('%sMeanAccuracy: ratio of correctly classified pixels to total pixels, averaged over all classes in the image\n', s);
s = sprintf('%sMeanIoU: (Jaccard similarity coefficient) average intersection over union (IoU) of all classes in the image\n', s);
s = sprintf('%sWeightedIoU: average IoU of all classes in the image, weighted by the number of pixels in each class\n', s);
s = sprintf('%sMeanBFScore: average boundary F1 (BF) score of each class in the image\n\n', s);

for i=1:numel(metricName)
    %s = sprintf('%s%s: %f\t\t', s, metricName{i}, metricValue(:,i));
    %if mod(i,2) == 0; s = sprintf('%s\n', s); end
    s = sprintf('%s%s: %f\n', s, metricName{i}, metricValue(:,i));
end

if ismember('IoU', ssm.ClassMetrics.Properties.VariableNames)
    s = sprintf('%s\nIoU (Jaccard) metric for each class:\n', s);
    for i=1:numel(ssm.ClassMetrics.Properties.RowNames)
        s = sprintf('%s%s:               %f\n', s, ssm.ClassMetrics.Properties.RowNames{i}, ssm.ClassMetrics.IoU(i));
    end
end
options.HeaderLines = numel(strfind(s, sprintf('\n'))); %#ok<SPRINTFN>
options.HelpUrl = 'https://se.mathworks.com/help/vision/ref/evaluatesemanticsegmentation.html';
prompts = {'Export to Matlab'; 'Save as Matlab file'; 'Save as Excel file'; 'Save as CSV file';...
    sprintf('Calculate occurrence of labels in ground truth and\nresulting images and Sørensen-Dice similarity (takes extra time)');};
defAns = {false; false; false; false; ...
    {'Do not calculate', 'Calculate occurrence', 'Calculate Sørensen-Dice similarity', 'Calculate everything', 1};};
options.LabelPosition = 'left';
options.WindowHeight = 660;
options.WindowWidth = 660;
answer = utils.dlgs.inputUniversalDlg(obj.view.gui, s, prompts, defAns, 'Evaluation results', options);
if isempty(answer); return; end


if ~strcmp(answer{5}, 'Do not calculate')
    calcOccurrenceSwitch = 0;
    calcSorensenSwitch = 0;
    if strcmp(answer{5}, 'Calculate occurrence') || strcmp(answer{5}, 'Calculate everything'); calcOccurrenceSwitch = 1; end
    if strcmp(answer{5}, 'Calculate Sørensen-Dice similarity') || strcmp(answer{5}, 'Calculate everything'); calcSorensenSwitch = 1; end

    % define usage of parallel computing
    if obj.BatchOpt.UseParallelComputing
        parforArg = obj.view.handles.PreprocessingParForWorkers.Value;    % Maximum number of workers running in parallel
        TitleTest = 'Evaluate segmentation (parallel)';
        if isempty(gcp('nocreate')); parpool(parforArg); end % create parpool
    else
        parforArg = 0;      % Maximum number of workers running in parallel
        TitleTest = 'Evaluate segmentation (single)';
    end
    % reset datastores
    dsTruth.reset();
    dsResults.reset();

    % make waitbar
    pw = core.PoolWaitbar(numel(dsTruth.Files), sprintf('Starting evaluation\nit may take a while...'), obj.view.gui, TitleTest);
    pw.setIncrement(10);
    occurrenceGT = [];
    occurrenceRes = [];
    similarity = [];

    if calcOccurrenceSwitch
        occurrenceGT = cell([numel(dsTruth.Files), 1]);
        occurrenceRes = cell([numel(dsTruth.Files), 1]);
    end
    if calcSorensenSwitch
        similarity = zeros([numel(dsTruth.Files), numel(ssm.ClassMetrics.Properties.RowNames)]);     % allocate space
    end

    parfor (fileId=1:numel(dsTruth.Files), parforArg)
        %for fileId = 1:numel(dsTruth.Files)
        gtImg = readimage(dsTruth, fileId);
        resImg = readimage(dsResults, fileId);
        if calcSorensenSwitch
            similarity(fileId, :) = dice(resImg, gtImg);   % returns vector of values for each class
        end

        if calcOccurrenceSwitch
            catList = categories(gtImg(:));
            catCounts = countcats(gtImg(:));
            occurrenceGT{fileId}(ismember(classNames, catList)) = catCounts;
            catList = categories(resImg(:));
            catCounts = countcats(resImg(:));
            occurrenceRes{fileId}(ismember(classNames, catList)) = catCounts;
        end

        if mod(fileId, 10) == 1; increment(pw); end     % update waitbar
    end

    % populate ssmStruct with new metric
    if calcSorensenSwitch
        for classId = 1:numel(classNames)
            ssmStruct.ImageMetrics.(['Dice_' ssm.ClassMetrics.Properties.RowNames{classId}]) = similarity(:,classId);
        end
    end
    if calcOccurrenceSwitch
        occurrenceGT = cell2mat(occurrenceGT);
        occurrenceRes = cell2mat(occurrenceRes);

        for classId = 1:numel(classNames)
            %ssmStruct.ImageMetrics.(['GT_' ssm.ClassMetrics.Properties.RowNames{classId}]) = occurrenceGT(:,classId);
            ssmStruct.ImageMetrics.(['GT_' classNames{classId}]) = occurrenceGT(:,classId);
        end
        for classId = 1:numel(classNames)
            ssmStruct.ImageMetrics.(['Model_' ssm.ClassMetrics.Properties.RowNames{classId}]) = occurrenceRes(:,classId);
        end
    end

    pw.deletePoolWaitbar();
end

% make output directories
outputPath = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages');
if exist(outputPath, 'dir') == false; mkdir(outputPath); end
outputPath = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels');
if exist(outputPath, 'dir') == false; mkdir(outputPath); end

if answer{1}    % export to Matlab
    assignin('base', 'ssm', ssmStruct);
    fprintf('A variable "ssm" was created in Matlab\n');
end
if answer{2}    % save in Matlab format
    fn = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels', 'EvaluationResults.mat');
    save(fn, 'ssmStruct', '-v7.3');
    fprintf('Evaluation results were saved to:\n%s\n', fn);
end
if answer{3}    % save in Excel format
    wbar = uiprogressdlg(obj.view.gui, 'Message', sprintf('Saving to Excel\nPlease wait...'), 'Title', 'Export');

    clear excelHeader;
    fn = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels', 'EvaluationResults.xls');
    if exist(fn, 'file') == 2; delete(fn); end
    excelHeader{1} = sprintf('Evaluation metrics for %s', obj.BatchOpt.NetworkFilename);

    try
        writecell(excelHeader, fn, 'FileType', 'spreadsheet', 'Sheet', 'ClassMetrics', 'Range', 'A1');
        writetable(ssm.ClassMetrics, fn, 'FileType', 'spreadsheet', 'Sheet', 'ClassMetrics', 'WriteRowNames', true, 'Range', 'A3');
    catch err
        utils.dlgs.showErrorDialog(obj.view.gui, err, 'Excel file overwrite', ...
            sprintf('The destination Excel file can not be overwritten!\nIt may be open elsewhere...\n\n%s', fn), '', opts);
        delete(wbar);
        return;
    end
    wbar.Value = 0.2;
    excelHeader{2,1} = 'Prediction results directory:';  excelHeader{2,2} = predictionDir;
    excelHeader{3,1} = 'Ground truth directory:';excelHeader{3,2} = truthDir;
    writecell(excelHeader, fn, 'FileType', 'spreadsheet', 'Sheet', 'ImageMetrics', 'Range', 'A1');
    writetable(ssmStruct.ImageMetrics, fn, 'FileType', 'spreadsheet', 'Sheet', 'ImageMetrics', 'WriteRowNames', true, 'Range', 'A5');

    wbar.Value = 0.4;
    writecell(excelHeader(1), fn, 'FileType', 'spreadsheet', 'Sheet', 'DataSetMetrics', 'Range', 'A1');
    writetable(ssm.DataSetMetrics, fn, 'FileType', 'spreadsheet', 'Sheet', 'DataSetMetrics', 'WriteRowNames', true, 'Range', 'A3');
    wbar.Value = 0.6;
    writecell(excelHeader(1), fn, 'FileType', 'spreadsheet', 'Sheet', 'ConfusionMatrix', 'Range', 'A1');
    writetable(ssm.ConfusionMatrix, fn, 'FileType', 'spreadsheet', 'Sheet', 'ConfusionMatrix', 'WriteRowNames', true, 'Range', 'A3');
    wbar.Value = 0.8;
    writecell(excelHeader(1), fn, 'FileType', 'spreadsheet', 'Sheet', 'NormalizedConfusionMatrix', 'Range', 'A1');
    writetable(ssm.NormalizedConfusionMatrix, fn, 'FileType', 'spreadsheet', 'Sheet', 'NormalizedConfusionMatrix', 'WriteRowNames', true, 'Range', 'A3');

    wbar.Value = 1;
    fprintf('Evaluation results were saved to:\n%s\n', fn);
    delete(wbar);
end

if answer{4}    % save in CSV format
    wbar = uiprogressdlg(obj.view.gui, 'Message', sprintf('Saving to CSV format\nPlease wait...'), 'Title', 'Export');
    fn = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels', 'EvaluationClassMetrics.csv');
    if exist(fn, 'file') == 2; delete(fn); end
    try
        writetable(ssm.ClassMetrics, fn, 'FileType', 'text', 'WriteRowNames', true);

        wbar.Value = 0.2;
        fn = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels', 'EvaluationImageMetrics.csv');
        if exist(fn, 'file') == 2; delete(fn); end
        writetable(ssmStruct.ImageMetrics, fn, 'FileType', 'text', 'WriteRowNames', true);

        wbar.Value = 0.4;
        fn = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels', 'EvaluationDataSetMetrics.csv');
        if exist(fn, 'file') == 2; delete(fn); end
        writetable(ssm.DataSetMetrics, fn, 'FileType', 'text', 'WriteRowNames', true);

        wbar.Value = 0.6;
        fn = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels', 'EvaluationConfusionMatrix.csv');
        if exist(fn, 'file') == 2; delete(fn); end
        writetable(ssm.ConfusionMatrix, fn, 'FileType', 'text', 'WriteRowNames', true);

        wbar.Value = 0.8;
        fn = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels', 'EvaluationNormalizedConfusionMatrix.csv');
        if exist(fn, 'file') == 2; delete(fn); end
        writetable(ssm.NormalizedConfusionMatrix, fn, 'FileType', 'text', 'WriteRowNames', true);

    catch err
        utils.dlgs.showErrorDialog(obj.view.gui, err, 'Excel file overwrite', ...
            sprintf('The destination CSV file can not be overwritten!\nIt may be open elsewhere...\n\n%s', fn));
        delete(wbar);
        return;
    end
    wbar.Value = 1;
    fprintf('Evaluation results were saved to:\n%s\n', fn);
    delete(wbar);
end
end

