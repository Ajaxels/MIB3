function processImagesForInstanceSegmentation(obj, preprocessFor)
% PROCESSIMAGESFORINSTANCESEGMENTATION - Preprocess labels for 2D instance segmentation for training and prediction.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.processImagesForInstanceSegmentation(preprocessFor)
%
% as result, mat-files with the following variables are created:
% - instanceBoxes, matrix  [N×4 double] containing bounding box coordinates of objects, where N is a number of objects on the image
% - instanceNames, array [N×1 categorical] containing names of objects,
% currently the same name should be used for all objects, can be any string
% converted to categorical.
% - instanceMasks, matrix [720×1280×N logical] binary masks where each slice
% represents individual object that should match the corresponding entry in
% instanceBoxes and instanceNames
%
% Input Arguments:
%   - **preprocessFor** - a string with target, 'training', 'prediction'
%

if nargin < 2
    mgsOpt.MsgBoxOnly = true;
    header = sprintf('processImagesForInstanceSegmentation: the second parameter is required!');
    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Preprocessing error', mgsOpt);
    return; 
end

if strcmp(preprocessFor, 'training')
    imageDirIn = obj.BatchOpt.OriginalTrainingImagesDir;
    imageFilenameExtension = obj.BatchOpt.ImageFilenameExtensionTraining{1};
    trainingSwitch = 1;     % a switch indicating processing of images for training    
elseif strcmp(preprocessFor, 'prediction')
    imageDirIn = obj.BatchOpt.OriginalPredictionImagesDir;
    imageFilenameExtension = obj.BatchOpt.ImageFilenameExtension{1};
    trainingSwitch = 0; %#ok<NASGU>

    % instance segmentation prediction reads the raw images directly with
    % segmentObjects (see startPredictionInstances), so no label preprocessing
    % is required. Just verify that the images are in place and inform the user.
    predictionImagesDir = fullfile(imageDirIn, 'Images');
    if ~isfolder(predictionImagesDir)
        predictionImagesDir = imageDirIn;   % fall back to a flat folder of images
    end
    imgFilelist = dir(fullfile(predictionImagesDir, ['*.' lower(imageFilenameExtension)]));
    mgsOpt.MsgBoxOnly = true;
    if isempty(imgFilelist)
        mgsOpt.Icon = 'puffin_error';
        header = sprintf('No prediction images (*.%s) were found in\n\n%s', lower(imageFilenameExtension), predictionImagesDir);
        utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Missing prediction images', mgsOpt);
    else
        mgsOpt.Icon = 'puffin_info';
        header = sprintf(['Preprocessing is not required for instance segmentation prediction.\n\n' ...
            '%d image(s) were found in\n%s\n\nSwitch to the Predict tab and press Predict.'], ...
            numel(imgFilelist), predictionImagesDir);
        utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Prediction preprocessing', mgsOpt);
    end
    return;
else
    mgsOpt.MsgBoxOnly = true;
    header = sprintf('processImagesForInstanceSegmentation: the second parameter is wrong!');
    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Preprocessing error', mgsOpt);
end

%% Load data
if ~isfolder(fullfile(imageDirIn, 'Images'))
    mgsOpt.MsgBoxOnly = true;
    header = sprintf('The images and models should be arranged in "Images" and "Labels" directories under\n\n%s\n\nCopy files there and try again!', imageDirIn);
    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Old project or missing files', mgsOpt);
    return;
end

imgFilelist = dir(fullfile(imageDirIn, 'Images', ['*.' lower(imageFilenameExtension)]));
if isempty(imgFilelist)
    mgsOpt.MsgBoxOnly = true;
    header = sprintf('Image files are missing in\n%s', fullfile(imageDirIn, 'Images'));
    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Missing image files!', mgsOpt);
    return;
end
numImgFiles = numel(imgFilelist);

obj.BatchOpt.showWaitbar = true;
if obj.BatchOpt.showWaitbar
    pwb = core.PoolWaitbar(1, sprintf('Creating labels datastore\nPlease wait...'), obj.view.gui, ...
        sprintf('%s %s: processing for %s', obj.BatchOpt.Workflow{1}, obj.BatchOpt.Architecture{1}, preprocessFor));
else
    pwb = [];
end
warning('off', 'MATLAB:MKDIR:DirectoryExists');

% preparing the directories
% delete exising directories and files
try
    if trainingSwitch
        outputDir = fullfile(imageDirIn, 'LabelsInstances');
        if isfolder(outputDir)
            rmdir(outputDir, 's');
        end
    else
        outputDir = fullfile(imageDirIn, 'GroundTruthLabelsInstances');
        if isfolder(outputDir)
            rmdir(outputDir, 's');
        end
    end
catch err
    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Problems with removing directories');
    if obj.BatchOpt.showWaitbar; delete(pwb); end
    return;
end

% make new directory
mkdir(outputDir);

labelsExists = 0;     % models exists
if strcmp(obj.BatchOpt.ModelFilenameExtension{1}, 'MODEL')
    % read number of materials for the first file
    files = dir(fullfile(imageDirIn, 'Labels', '*.model'));
    if isempty(files) && trainingSwitch
        mgsOpt.MsgBoxOnly = true;
        header = sprintf('Model files are missing in\n%s', fullfile(imageDirIn, 'Labels'));
        utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Missing model files!', mgsOpt);
        if obj.BatchOpt.showWaitbar; delete(pwb); end
        return;
    elseif ~isempty(files)
        labelsExists = 1;     % models exists
    end
else
    files = dir(fullfile(imageDirIn, 'Labels', lower(['*.' obj.BatchOpt.ModelFilenameExtension{1}]))); % extensions on Linux are case sensitive
    if ~isempty(files)
        labelsExists = 1;     % models exists
    end
end

% define usage of parallel computing
if obj.BatchOpt.UseParallelComputing
    parforArg = obj.view.handles.PreprocessingParForWorkers.Value;    % Maximum number of workers running in parallel
    if isempty(gcp('nocreate')); parpool(parforArg); end % create parpool
else
    parforArg = 0;      % Maximum number of workers running in parallel, when 0 a single core used without parallel
end

% create local variables for parfor
mode2D3DParFor = obj.BatchOpt.Workflow{1}(1:2);
showWaitbarParFor = obj.BatchOpt.showWaitbar;
compressModels = obj.BatchOpt.CompressProcessedModels;
singleModelTrainingFileParFor = obj.BatchOpt.SingleModelTrainingFile;

if obj.BatchOpt.showWaitbar
    if pwb.getCancelState(); delete(pwb); return; end
    pwb.updateText(sprintf('Processing instance labels\nPlease wait...'));
    pwb.setIncrement(10);  % set increment step to 10
end

labelsDS = [];
if labelsExists
    if strcmp(obj.BatchOpt.Workflow{1}(1:2), '2D')  % preprocess files for 2D networks
        if singleModelTrainingFileParFor
            fileList = dir(fullfile(imageDirIn, 'Labels', '*.model'));
            fullModelPathFilenames = arrayfun(@(filename) fullfile(imageDirIn, 'Labels', cell2mat(filename)), {fileList.name}, 'UniformOutput', false);  % generate full paths
            labelsDS = matfile(fullModelPathFilenames{1});     % models
        else
            switch obj.BatchOpt.ModelFilenameExtension{1}
                case 'MODEL'
                    labelsDS = imageDatastore(fullfile(imageDirIn, 'Labels'), ...
                        'IncludeSubfolders', false, ...
                        'FileExtensions', '.model', 'ReadFcn', @deepmib.storeLoadModel);
                    % I = readimage(labelsDS,1);  % read model test
                    % reset(labelsDS);
                otherwise
                    labelsDS = imageDatastore(fullfile(imageDirIn, 'Labels'), ...
                        'IncludeSubfolders', false, ...
                        'FileExtensions', lower(['.' obj.BatchOpt.ModelFilenameExtension{1}]));
            end
            if numel(labelsDS.Files) ~= numImgFiles
                mgsOpt.MsgBoxOnly = true;
                header = sprintf('In this mode number of model files should match number of image files!');
                utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Error', mgsOpt);
                if obj.BatchOpt.showWaitbar; delete(pwb); end
                return;
            end
        end
    else    % preprocess files for 3D networks
        
    end    % read corresponding model
end

if singleModelTrainingFileParFor && ~isempty(labelsDS)
    if size(labelsDS.(labelsDS.modelVariable), 3) < numImgFiles
        mgsOpt.MsgBoxOnly = true;
        header = sprintf('Number of slices in the model file is smaller than number of images\n\nYou may want to uncheck the "Single MIB model file" checkbox!');
        utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Wrong model file', mgsOpt);
        if showWaitbarParFor; delete(pwb); end
        return;
    end
end

if showWaitbarParFor
    pwb.setCurrentIteration(0);
    pwb.updateMaxNumberOfIterations(numImgFiles);
end

parfor (imgId=1:numImgFiles, parforArg)
%for imgId=1:numImgFiles
    if labelsExists
        if strcmp(mode2D3DParFor, '2D')
            if singleModelTrainingFileParFor
                labelMap = labelsDS.(labelsDS.modelVariable)(:,:,imgId);    % get 2D slice from the model
                [~, fnModOut] = fileparts(imgFilelist(imgId).name);    % get filename for the model
                fnModOut = sprintf('Labels_%s', fnModOut);  % generate name for the output model file
            else
                labelMap = readimage(labelsDS, imgId);      % read corresponding model
                [~, fnModOut] = fileparts(labelsDS.Files{imgId});    % get filename for the model
            end

            % store the 2D instance label map (each object = unique index, background 0);
            % native-resolution patches are cropped from it on-the-fly during training
            % (see deepmib.readInstancePatch), which avoids building memory-heavy full-image
            % mask stacks for large / whole-slide images
            if ~any(labelMap(:))
                % no labelled objects on this image, skip generating an annotation file
                fprintf('processImagesForInstanceSegmentation: no objects in "%s", skipped\n', imgFilelist(imgId).name);
            else
                instanceLabelMap = uint16(labelMap);
                deepmib.saveInstanceLabelsParFor(fullfile(outputDir, [fnModOut '.mat']), imgFilelist(imgId).name, instanceLabelMap, compressModels)
            end
        else   % 3D case
            
        end
    end
    
    if showWaitbarParFor && mod(imgId, 10) == 1; increment(pwb); end
end
if obj.BatchOpt.showWaitbar; delete(pwb); end

end
