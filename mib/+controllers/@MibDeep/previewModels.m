function previewModels(obj, loadImagesSwitch)
% PREVIEWMODELS - load images for predictions and the resulting modelsinto MIB.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.previewModels(loadImagesSwitch)
%
% Input Arguments:
%   - **loadImagesSwitch** - [logical], load or not (assuming that
%     images have already been preloaded) images. When true, both
%     images and models are loaded, when false - only models are
%     loaded
%
% For ZARR images (``BatchOpt.ImageFilenameExtension = 'ZARR'``) one image is
% previewed at a time, chosen from a list when several have a model: with the
% "Zarr3 (BigData model)" output the buffer is switched to the BigData mode and
% the model store is attached to the image; with the MIB/TIF outputs the buffer
% is switched to the Standard mode and the image is loaded at the predicted
% level, so the model matches it (local function ``previewZarrPrediction``).
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDeep.previewModels: triggered\n');
end

% zarr images are stores (folders) predicted at one pyramid level: they are
% previewed one image at a time, see previewZarrPrediction below
if strcmp(obj.BatchOpt.ImageFilenameExtension{1}, 'ZARR')
    previewZarrPrediction(obj, loadImagesSwitch);
    return;
end

imgDir = 0;
if loadImagesSwitch
    imagesSubfolder = 'Images';
    if ~isfolder(fullfile(obj.BatchOpt.OriginalPredictionImagesDir, 'Images'))
        res = uiconfirm(obj.view.gui, ...
            sprintf(['It is recommended to keep images for prediction under "Images" subfolder within the directory specified in \n\n' ...
            '"Directories and Preprocessing" -> \n\t\t\t"Directory with images for prediction"\n\n' ...
            'However "Images" subfolder was not found!\n\nWould you like to continue and load images that are located under:\n' ...
            '%s'], obj.BatchOpt.OriginalPredictionImagesDir), ...
            'Missing Images subfolder', ...
            'Options', {'Load images for prediction','Cancel'}, ...
            'Icon', 'warning');
        if strcmp(res, 'Cancel');  if obj.BatchOpt.showWaitbar; delete(obj.wb); end; return; end
        imagesSubfolder = [];
    end

    imgDir = fullfile(obj.BatchOpt.OriginalPredictionImagesDir, imagesSubfolder);
    imgList = dir(fullfile(imgDir, ['*.' lower(obj.BatchOpt.ImageFilenameExtension{1})]));
else
    imgList = 0; % init with a number
end
modelDir = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels');
switch obj.BatchOpt.P_ModelFiles{1}
    case 'MIB Model format'
        modelFileExtension = '*.model';
    case {'TIF compressed format', 'TIF uncompressed format'}
        modelFileExtension = '*.tif';
end
modelList = dir(fullfile(modelDir, lower(modelFileExtension)));

if isempty(imgList) || isempty(modelList)
    mgsOpt.MsgBoxOnly = true;
    mgsOpt.headerLines = 1;
    mgsOpt.WindowWidth = 580;
    mgsOpt.WindowHeight = 320;
    header = 'Missing file!';
    text = sprintf('Files were not found in\n%s\n[--> %d file(s)]\n\n%s\n[--> %d file(s)]\n\n- Update the Directory prediction and resulting images fields of the Directories and Preprocessing tab\n- Make sure that the model type is properly choosen under "Predict->Model files"', imgDir, numel(imgList), modelDir, numel(modelList));
    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {text}, 'Missing files', mgsOpt);
    return;
end

if strcmp(obj.BatchOpt.Workflow{1}(1:2), '3D')  % take only the first file for 3D case
    if loadImagesSwitch
        BatchOptIn1.Filenames = {fullfile(imgDir, imgList(1).name)};
    end
    BatchOptIn2.DirectoryName = {modelDir};
    BatchOptIn2.FilenameFilter = modelList(1).name;
else
    if loadImagesSwitch
        BatchOptIn1.Filenames = arrayfun(@(filename) fullfile(imgDir, cell2mat(filename)), {imgList.name}, 'UniformOutput', false);  % generate full paths
    end
    BatchOptIn2.DirectoryName = {modelDir};
    BatchOptIn2.FilenameFilter = modelFileExtension;
end

if loadImagesSwitch % load images
    BatchOptIn1.UseBioFormats = obj.BatchOpt.Bioformats;
    BatchOptIn1.BioFormatsIndices = num2str(obj.BatchOpt.BioformatsIndex{1});
    obj.mibModel.currentDirectory = imgDir;
    obj.mibModel.loadImages([], BatchOptIn1);
end
obj.mibModel.loadModel([], BatchOptIn2);  % load models
end

function previewZarrPrediction(obj, loadImagesSwitch)
% PREVIEWZARRPREDICTION - load a zarr image and its predicted model into MIB.
%
% One image at a time (chosen from a list when several have a model):
%
%   - "Zarr3 (BigData model)" output: the buffer is switched to the BigData mode,
%     the image is opened and its model store ``Labels_<image name>.zarr3`` (or
%     ``.zarr2``) is attached. The store is looked for in the folder of the last
%     prediction (``obj.sessionSettings.lastModelStoreFolder``), else where
%     ``obj.ZarrModelOpt.Location`` puts it; when none is there, a folder is asked
%   - MIB / TIF output: the buffer is switched to the Standard mode and the image
%     is loaded at the predicted level (``BatchOpt.BioformatsIndex``), so it
%     matches ``Labels_<image name>.model`` / ``.tif`` in ResultsModels
%
% With ``loadImagesSwitch == false`` only the model is loaded, onto the open
% image, which must be in the matching mode.

    bigDataOutput = strcmp(obj.BatchOpt.P_ModelFiles{1}, 'Zarr3 (BigData model)');
    datasetId = obj.mibModel.getActiveId();
    mgsOpt.MsgBoxOnly = true;

    % zarr images, as listed for prediction by checkZarrStores
    imageDir = fullfile(obj.BatchOpt.OriginalPredictionImagesDir, 'Images');
    if ~isfolder(imageDir); imageDir = obj.BatchOpt.OriginalPredictionImagesDir; end
    listing = dir(imageDir);
    listing = listing([listing.isdir] & ~cellfun(@isempty, regexpi({listing.name}, '\.zarr[23]?$', 'once')));
    imageList = fullfile({listing.folder}, {listing.name});
    imageList = imageList(~cellfun(@core.MibBigDataLabels.isMibModelStore, imageList));
    imageNames = cell(size(imageList));
    for imageId = 1:numel(imageList)
        [~, imageNames{imageId}] = fileparts(imageList{imageId});
        imageNames{imageId} = regexprep(imageNames{imageId}, '\.ome$', '', 'ignorecase');
    end

    % models of the images
    if bigDataOutput
        modelFolder = '';
        if isfield(obj.sessionSettings, 'lastModelStoreFolder') && isfolder(obj.sessionSettings.lastModelStoreFolder)
            modelFolder = obj.sessionSettings.lastModelStoreFolder;
        elseif strcmp(obj.ZarrModelOpt.Location, 'ResultsModels')
            modelFolder = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels');
        elseif ~strcmp(obj.ZarrModelOpt.Location, 'Ask')
            modelFolder = imageDir;
        end
        modelExtensions = {'.zarr3', '.zarr2'};
    else
        modelFolder = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels');
        if strcmp(obj.BatchOpt.P_ModelFiles{1}, 'MIB Model format')
            modelExtensions = {'.model'};
        else
            modelExtensions = {'.tif'};
        end
    end
    modelPaths = findModels(modelFolder, imageNames, modelExtensions);
    if bigDataOutput && ~any(~cellfun(@isempty, modelPaths)) && ~isempty(imageList)
        selection = uiconfirm(obj.view.gui, ...
            sprintf('Model stores (Labels_<image name>.zarr3) were not found in\n%s\n\nSelect the folder with the model stores?', modelFolder), ...
            'Model stores not found', 'Options', {'Choose folder...', 'Cancel'}, ...
            'DefaultOption', 1, 'CancelOption', 2, 'Icon', 'warning');
        if strcmp(selection, 'Cancel'); return; end
        chosenFolder = uigetdir(imageDir, 'Select folder with the model stores');
        figure(obj.view.gui);
        if isequal(chosenFolder, 0); return; end
        modelFolder = chosenFolder;
        modelPaths = findModels(modelFolder, imageNames, modelExtensions);
    end

    available = ~cellfun(@isempty, modelPaths);
    if ~any(available)
        mgsOpt.WindowWidth = 560;
        utils.dlgs.inputUniversalDlg(obj.view.gui, 'Missing files!', {}, ...
            {sprintf('No zarr image with a predicted model (Labels_<image name>%s) was found\n\nimages: %s [%d]\nmodels: %s', ...
            modelExtensions{1}, imageDir, numel(imageList), modelFolder)}, 'Missing files', mgsOpt);
        return;
    end
    imageList = imageList(available);
    imageNames = imageNames(available);
    modelPaths = modelPaths(available);

    imageId = 1;
    if loadImagesSwitch && numel(imageList) > 1
        options.WindowStyle = 'normal';
        [answer, selectedIndices] = utils.dlgs.inputUniversalDlg(obj.view.gui, '', {'Image to preview:'}, ...
            {[imageNames, {1}]}, 'Preview predictions', options);
        if isempty(answer); return; end
        imageId = selectedIndices(1);
    elseif ~loadImagesSwitch
        % the model of the open image
        [~, openName] = fileparts(obj.mibModel.I{datasetId}.image.filename);
        imageId = find(strcmp(imageNames, regexprep(openName, '\.ome$', '', 'ignorecase')), 1);
        if isempty(imageId)
            utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                sprintf('The open dataset (%s) has no predicted model\n\nUse "Load images and models" instead', openName), ...
                {}, {}, 'Missing model', mgsOpt);
            return;
        end
    end

    if bigDataOutput; targetMode = 'BigData'; else; targetMode = 'Standard'; end
    if loadImagesSwitch
        % same steps as SelectFromUrl.ensureDatasetMode: the placeholder must
        % match the mode, and the Datasets panel caches the mode per buffer
        if ~strcmp(obj.mibModel.I{datasetId}.datasetType, targetMode)
            if bigDataOutput
                modeIndex = 3;
                placeholder = {fullfile(obj.mibModel.mibPath, 'assets', 'images', 'default.h5')};
            else
                modeIndex = 1;
                placeholder = [];
            end
            achievedMode = obj.mibModel.I{datasetId}.switchDatasetMode(modeIndex, ...
                obj.mibModel.preferences.System.EnableSelection, placeholder);
            if achievedMode ~= modeIndex
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    sprintf('Could not switch the dataset buffer to the %s mode', targetMode), 'Preview predictions');
                return;
            end
            datasetsInSet = obj.mibModel.Sets.datasetsInSet;
            obj.mibModel.Sets.datasetTypes{floor((datasetId - 1) / datasetsInSet) + 1, mod(datasetId - 1, datasetsInSet) + 1} = ...
                obj.mibModel.I{datasetId}.datasetType;
        end

        imageOptions.Filenames = imageList(imageId);
        imageOptions.UseBioFormats = false;
        if ~bigDataOutput
            imageOptions.ZarrLevel = num2str(obj.BatchOpt.BioformatsIndex{1});   % the predicted level
        end
        obj.mibModel.currentDirectory = imageDir;
        obj.mibModel.loadImages([], imageOptions);
    elseif ~strcmp(obj.mibModel.I{datasetId}.datasetType, targetMode)
        utils.dlgs.inputUniversalDlg(obj.view.gui, ...
            sprintf('The model of this prediction is shown in the %s mode, but the open dataset is in the %s mode\n\nUse "Load images and models" instead', ...
            targetMode, obj.mibModel.I{datasetId}.datasetType), {}, {}, 'Wrong dataset mode', mgsOpt);
        return;
    end

    if bigDataOutput
        modelOptions.Filenames = modelPaths(imageId);     % attaches the store
    else
        [modelOptions.DirectoryName{1}, modelName, modelExtension] = fileparts(modelPaths{imageId});
        modelOptions.FilenameFilter = [modelName modelExtension];
    end
    obj.mibModel.loadModel([], modelOptions);
end

function modelPaths = findModels(modelFolder, imageNames, modelExtensions)
% FINDMODELS - full path of Labels_<image name><extension> for each image, '' when missing.
    modelPaths = repmat({''}, size(imageNames));
    if isempty(modelFolder); return; end
    for imageId = 1:numel(imageNames)
        for extensionId = 1:numel(modelExtensions)
            candidate = fullfile(modelFolder, ['Labels_' imageNames{imageId} modelExtensions{extensionId}]);
            if isfolder(candidate) || isfile(candidate)
                modelPaths{imageId} = candidate;
                break;
            end
        end
    end
end

