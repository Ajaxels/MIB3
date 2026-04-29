function previewModels(obj, loadImagesSwitch)
% PREVIEWMODELS - load images for predictions and the resulting modelsinto MIB.
%
% Syntax:
%   function previewModels(obj, loadImagesSwitch)
%
% Input Arguments:
%   - **loadImagesSwitch** — [logical], load or not (assuming that
%     images have already been preloaded) images. When true, both
%     images and models are loaded, when false - only models are
%     loaded
%

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
    header = sprintf('Files were not found in\n%s\n[--> %d file(s)]\n\n%s\n[--> %d file(s)]\n\n- Update the Directory prediction and resulting images fields of the Directories and Preprocessing tab\n- Make sure that the model type is properly choosen under "Predict->Model files"', imgDir, numel(imgList), modelDir, numel(modelList));
    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Missing files', mgsOpt);
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

