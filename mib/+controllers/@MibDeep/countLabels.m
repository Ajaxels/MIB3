function countLabels(obj)
% function countLabels(obj)
% count occurrences of labels in model files
% callback for press of the "Count labels" in the Options panel
% define directory with label files
if ~isfield(obj.sessionSettings, 'countLabelsDir')
    obj.sessionSettings.countLabelsDir = obj.BatchOpt.OriginalTrainingImagesDir;
end
selpath = uigetdir(obj.sessionSettings.countLabelsDir, 'Select folder with labels');
if selpath == 0; return; end
obj.sessionSettings.countLabelsDir = selpath;
% define extension of the label files
prompts = {'Label filenames extension:'; 'Number of classes including exterior, (for TIF and PNG or put largest possible value):'};
defAns = {{'model', 'mibCat', 'png', 'tif', 'tiff', 1}, num2str(obj.BatchOpt.T_NumberOfClasses{1})};
dlgTitle = 'Options';
dlgOptions.PromptLines = [1, 2];
[answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, dlgTitle, dlgOptions);
if isempty(answer); return; end
labelExtension = answer{1};
numClasses = str2double(answer{2});

% get list of files
labelFileList = dir(fullfile(obj.sessionSettings.countLabelsDir, lower(['*.' labelExtension])));
if numel(labelFileList) == 0
    mgsOpt.MsgBoxOnly = true;
    mgsOpt.Icon = 'puffin_error';
    header = sprintf('Directory:\n%s\ndoes not contain any files with "%s" extension', obj.sessionSettings.countLabelsDir, labelExtension);
    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Missing label files', mgsOpt);
    return
end

% generate class names
classNames = {};
if strcmp(labelExtension, 'model')
    modelFn = fullfile(labelFileList(1).folder, labelFileList(1).name);
    res = load(modelFn, '-mat', 'modelMaterialNames');
    classNames = [{'Exterior'}; res.modelMaterialNames];
elseif strcmp(labelExtension, 'mibCat')
    modelFn = fullfile(labelFileList(1).folder, labelFileList(1).name);
    res = load(modelFn, '-mat', 'options');
    classNames = res.options.modelMaterialNames;
else
    for i=0:numClasses-1
        classNames = [classNames; {sprintf('Class%.3d', i)}]; %#ok<AGROW>
    end
end
pixelLabelID = 0:numel(classNames)-1;

% make datastores
try
    fullPathFilenames = arrayfun(@(filename) fullfile(obj.sessionSettings.countLabelsDir, cell2mat(filename)), ...
        {labelFileList.name}, 'UniformOutput', false);  % generate full paths
    switch labelExtension
        case 'model'
            dsLabels = pixelLabelDatastore(fullPathFilenames, classNames, pixelLabelID, ...
                'FileExtensions', '.model', 'ReadFcn', @utils.deepmib.storeLoadModel);
        case 'mibCat'
            %dsLabels = pixelLabelDatastore(fullPathFilenames, classNames, pixelLabelID, ...
            %    'FileExtensions', '.mibCat', 'ReadFcn', @utils.deepmib.storeLoadImages);
            dsLabels = imageDatastore(fullPathFilenames, ...
                'FileExtensions', '.mibCat', 'IncludeSubfolders', false, ...
                'ReadFcn', @utils.deepmib.storeLoadCategorical);
        otherwise
            dsLabels = pixelLabelDatastore(fullPathFilenames, classNames, pixelLabelID, ...
                'FileExtensions', lower(['.' labelExtension]));
    end
catch err
    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Wrong class name', ...
        '', sprintf('Check the ground truth directory:\n%s', obj.sessionSettings.countLabelsDir));
    return;
end

% generate output structure
% add list of files
[~, ImageMetrics.GroundTruthFilename] = arrayfun(@(fn) fileparts(cell2mat(fn)), dsLabels.Files, 'UniformOutput', false);

% define usage of parallel computing
if obj.BatchOpt.UseParallelComputing
    parforArg = obj.view.handles.PreprocessingParForWorkers.Value;    % Maximum number of workers running in parallel
    TitleTest = 'Count labels (parallel)';
    if isempty(gcp('nocreate')); parpool(parforArg); end  % create parpool
else
    parforArg = 0;      % Maximum number of workers running in parallel
    TitleTest = 'Count labels (single)';
end
% reset datastores
dsLabels.reset();

% make waitbar
pw = core.PoolWaitbar(numel(dsLabels.Files), sprintf('Counting labels\nit may take a while...'), obj.view.gui, TitleTest);
pw.setIncrement(10);
occurrenceGT = cell([numel(dsLabels.Files), 1]);

parfor (fileId=1:numel(dsLabels.Files), parforArg)
    % for fileId = 1:numel(dsLabels.Files)
    gtImg = readimage(dsLabels, fileId);
    if iscell(gtImg(1)); gtImg = gtImg{1}; end

    catList = categories(gtImg(:));
    catCounts = countcats(gtImg(:));
    occurrenceGT{fileId}(ismember(classNames, catList)) = catCounts;

    if mod(fileId, 10) == 1; increment(pw); end     % update waitbar
end
occurrenceGT = cell2mat(occurrenceGT);
for classId = 1:numel(classNames)
    ImageMetrics.(['GT_' classNames{classId}]) = occurrenceGT(:,classId);
end
% convert to table
tableOut = struct2table(ImageMetrics);
pw.deletePoolWaitbar();

fn = fullfile(obj.sessionSettings.countLabelsDir, 'labelCounts.mat');
[filename, pathname, filterindex] = uiputfile( ...
    {'*.mat','MAT-files (*.mat)';...
    '*.xls', 'Microsoft Excel';...
    '*.csv','Comma-separated values';...
    '*.*',  'All Files (*.*)'}, 'Output filename', fn);
if filename == 0; return; end
fn = fullfile(pathname, filename);

switch filterindex
    case 1  % mat
        save(fn, 'tableOut', '-v7.3');
        fprintf('Label counts were were saved to:\n%s\n', fn);
    case 2  % excel
        wbar = waitbar(0, sprintf('Saving to Excel\nPlease wait...'), 'Name', 'Export');
        clear excelHeader;
        if exist(fn, 'file') == 2; delete(fn); end
        excelHeader{1} = sprintf('Label counts for %s\\*.%s', obj.sessionSettings.countLabelsDir, labelExtension);
        writecell(excelHeader, fn, 'FileType', 'spreadsheet', 'Sheet', 'LabelCounts', 'Range', 'A1');
        writetable(tableOut, fn, 'FileType', 'spreadsheet', 'Sheet', 'LabelCounts', 'WriteRowNames', true, 'Range', 'A3');
        waitbar(1, wbar);
        fprintf('Label counts were were saved to:\n%s\n', fn);
        delete(wbar);
    case 3  % csv
        wbar = waitbar(0, sprintf('Saving to CSV format\nPlease wait...'), 'Name', 'Export');
        if exist(fn, 'file') == 2; delete(fn); end
        writetable(tableOut, fn, 'FileType', 'text', 'WriteRowNames', true);
        fprintf('Label counts were were saved to:\n%s\n', fn);
        delete(wbar);
end
end

