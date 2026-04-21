function result = loadModel(obj, filenames, options)
% function result = loadModel(obj, filenames, options)
% Load a segmentation model into this dataset from files or a raw array
%
% This is the dataset-level orchestrator for model loading.  It is called
% by MibModel.loadModel after BatchOpt processing, virtual-mode guarding,
% and file browsing have been completed.  It handles:
%
%   FILE PATH  — filenames is a cell array of full file paths.
%                Dispatches to the loader identified by options.loaderInfo.
%
%   IMPORT PATH — options.model contains the raw array (workspace import).
%                 filenames is empty ([]); the loader is bypassed entirely.
%
% After the array is obtained the method validates dimensions against the
% open image, calls createModel(), writes the data, and populates all label
% metadata properties.
%
% Parameters:
% filenames: cell array with full file paths, or [] for the import path
% options: struct with loading parameters
% @li .loaderInfo        - struct returned by ExtensionRegistryLoad.resolveLoader
%                          (required for the file path; ignored for import)
% @li .model             - raw array to import (import path only)
% @li .modelMaterialNames - cell array of names for the import path
% @li .modelMaterialColors - Nx3 RGB matrix for the import path
% @li .modelType         - numeric model type (63/255/65535/4294967295)
% @li .labelText         - annotation text cell array (or [])
% @li .labelPosition     - annotation positions (or [])
% @li .labelValue        - annotation values (or [])
% @li .batchModeSwitch   - [logical, {false}] suppress interactive dialogs
% @li .preferences       - MIB preferences struct (for color fallback)
% @li .ParentFigure      - parent figure handle for dialogs
% @li .mibPath           - path to MIB installation directory
% @li .showWaitbar       - [logical, {true}] show progress dialog
%
% Return values:
% result: struct with loaded metadata, or [] on error or user cancel
% @li .materialNames  - cell array of material names
% @li .materialColors - Nx3 RGB color matrix
% @li .modelType      - numeric type used
% @li .labelsVariable - variable name

%|
% @b Examples:
% @code
% options.loaderInfo = obj.mibModel.extensionRegistryLoad.resolveLoader('file.model','Model','Default');
% options.preferences = obj.mibModel.preferences;
% result = obj.mibModel.I{obj.mibModel.id}.loadModel({'C:\data\Labels.model'}, options);
% @endcode
%
% @code
% % import path
% options.model = myModelArray;
% options.modelMaterialNames = {'Cell','Nucleus'};
% result = obj.mibModel.I{obj.mibModel.id}.loadModel([], options);
% @endcode

% Updates

result = [];

if nargin < 3; options = struct(); end
if nargin < 2; filenames = {}; end

if ~isfield(options, 'batchModeSwitch');   options.batchModeSwitch = false; end
if ~isfield(options, 'showWaitbar');       options.showWaitbar = true; end
if ~isfield(options, 'model');             options.model = []; end
if ~isfield(options, 'modelMaterialNames'); options.modelMaterialNames = {}; end
if ~isfield(options, 'modelMaterialColors'); options.modelMaterialColors = []; end
if ~isfield(options, 'modelType');         options.modelType = []; end
if ~isfield(options, 'labelText');         options.labelText = []; end
if ~isfield(options, 'labelPosition');     options.labelPosition = []; end
if ~isfield(options, 'labelValue');        options.labelValue = []; end

%% Get raw array and metadata

rawModel         = []; %#ok<NASGU> defensive init; used by isempty check after both code paths
materialNames    = {};
materialColors   = [];
modelType        = [];
labelsVariable   = 'mibModel';
labelText        = options.labelText;
labelPosition    = options.labelPosition;
labelValue       = options.labelValue;
boundingBox      = [];

if ~isempty(options.model)
    % ---- IMPORT PATH --------------------------------------------------------
    rawModel = options.model;
    if ~isempty(options.modelMaterialNames)
        materialNames = options.modelMaterialNames;
    end
    if ~isempty(options.modelMaterialColors)
        materialColors = options.modelMaterialColors;
    end
    if ~isempty(options.modelType)
        modelType = options.modelType;
    end
    labelsVariable = 'mibModel';

else
    % ---- FILE PATH ----------------------------------------------------------
    if isempty(filenames)
        warning('MibDataset:loadModel', 'No filenames provided and no model array in options');
        return;
    end

    if ~isfield(options, 'loaderInfo') || ~isstruct(options.loaderInfo)
        warning('MibDataset:loadModel', 'options.loaderInfo is required for file loading');
        return;
    end

    % Create the loader
    loaderOpts = struct();
    if isfield(options, 'ParentFigure'); loaderOpts.ParentFigure = options.ParentFigure; end
    if isfield(options, 'mibPath');      loaderOpts.mibPath      = options.mibPath; end
    loaderOpts.showWaitbar = options.showWaitbar;

    try
        loader = io.LoaderFactory.create(options.loaderInfo, loaderOpts);
    catch ME
        warning('MibDataset:loadModel', 'Failed to create loader: %s', ME.message);
        return;
    end

    % Load metadata
    [imginfo, files] = loader.loadMetadata(filenames, loaderOpts);

    % Check success
    if ~isKey(imginfo, 'numEntries') || imginfo{"numEntries"} == 0
        warning('MibDataset:loadModel', 'Loader returned no entries for: %s', filenames{1});
        return;
    end

    % Load image data
    [rawModel, ~] = loader.loadImages(files, imginfo, loaderOpts);

    % Extract model-specific metadata from imginfo
    if isKey(imginfo, 'modelMaterialNames') && ~isempty(imginfo{"modelMaterialNames"})
        materialNames = imginfo{"modelMaterialNames"};
    end
    if isKey(imginfo, 'modelMaterialColors') && ~isempty(imginfo{"modelMaterialColors"})
        materialColors = imginfo{"modelMaterialColors"};
    end
    if isKey(imginfo, 'modelType') && ~isempty(imginfo{"modelType"})
        modelType = imginfo{"modelType"};
    end
    if isKey(imginfo, 'labelsVariable') && ~isempty(imginfo{"labelsVariable"})
        labelsVariable = imginfo{"labelsVariable"};
    end
    if isKey(imginfo, 'labelText') && ~isempty(imginfo{"labelText"})
        labelText = imginfo{"labelText"};
    end
    if isKey(imginfo, 'labelPosition') && ~isempty(imginfo{"labelPosition"})
        labelPosition = imginfo{"labelPosition"};
    end
    if isKey(imginfo, 'labelValue') && ~isempty(imginfo{"labelValue"})
        labelValue = imginfo{"labelValue"};
    end
    if isKey(imginfo, 'BoundingBox') && ~isempty(imginfo{"BoundingBox"})
        boundingBox = imginfo{"BoundingBox"};
    end

    % Extract Amira material info from imginfo (Materials_N_Name / Materials_N_Color)
    if isempty(materialNames)
        idx = 1;
        while true
            nameKey  = sprintf('Materials_%d_Name', idx);
            colorKey = sprintf('Materials_%d_Color', idx);
            if isKey(imginfo, nameKey)
                materialNames{idx} = imginfo{nameKey}; %#ok<AGROW>
                if isKey(imginfo, colorKey)
                    materialColors(idx, :) = imginfo{colorKey}; %#ok<AGROW>
                end
                idx = idx + 1;
            else
                break;
            end
        end
    end
end

if isempty(rawModel)
    warning('MibDataset:loadModel', 'No model data returned');
    return;
end

%% Auto-detect modelType if still empty

if isempty(modelType)
    switch class(rawModel)
        case 'uint8'
            if max(rawModel(:)) <= 63
                modelType = 63;
            else
                modelType = 255;
            end
        case 'uint16'
            modelType = 65535;
        case {'uint32', 'double', 'single'}
            modelType = 4294967295;
        otherwise
            modelType = 255;
    end
end

% Handle double/single: prompt in GUI mode, auto-convert in batch
if isa(rawModel, 'double') || isa(rawModel, 'single')
    if ~options.batchModeSwitch && ~isempty(options.ParentFigure)
        header = 'Convert to uint32?';
        dlgOpt.HeaderLines = 1;
        dlgOpt.Icon = 'puffin_question';
        dlgOpt.WindowHeight = 160;
        if isfield(options, 'mibPath'); dlgOpt.mibPath = options.mibPath; end
        answer = utils.dlgs.inputUniversalDlg(options.ParentFigure, header, ...
            {sprintf('The model array is class "%s".\nIt will be converted to uint32.\nContinue?', class(rawModel))}, ...
            {{'Yes','No',1}}, 'Convert model', dlgOpt);
        if isempty(answer) || strcmp(answer{1}, 'No'); return; end
    end
    rawModel = uint32(rawModel);
    modelType = 4294967295;
end

%% Dimension validation

imgH = obj.image.height;
imgW = obj.image.width;
imgD = obj.image.depth;

% Squeeze to remove singleton dims from on-disk 3D format
rawModel = squeeze(rawModel);
sz = size(rawModel);
modelH = sz(1);
modelW = sz(2);
modelD = 1;
modelT = 1;
if numel(sz) >= 3; modelD = sz(3); end
if numel(sz) >= 5; modelT = sz(5); end

% Check H/W mismatch
if modelH ~= imgH || modelW ~= imgW
    if ~options.batchModeSwitch && ~isempty(options.ParentFigure)
        header = 'Dimension mismatch';
        dlgOpt.HeaderLines = 1;
        dlgOpt.Icon = 'puffin_warning';
        dlgOpt.MsgBoxOnly = true;
        dlgOpt.WindowHeight = 180;
        if isfield(options, 'mibPath'); dlgOpt.mibPath = options.mibPath; end
        msg = sprintf('<html><p style="font-size:10pt">Model size [%dx%d] does not match image [%dx%d].<br>The model will be padded or cropped to fit.</p></html>', ...
            modelH, modelW, imgH, imgW);
        utils.dlgs.inputUniversalDlg(options.ParentFigure, header, {msg}, {''}, ...
            'Size mismatch', dlgOpt);
    end
    % Crop or pad to image H×W
    newModel = zeros(imgH, imgW, modelD, 1, modelT, class(rawModel));
    copyH = min(modelH, imgH);
    copyW = min(modelW, imgW);
    newModel(1:copyH, 1:copyW, :, :, :) = rawModel(1:copyH, 1:copyW, :, :, :);
    rawModel = newModel;
    modelH = imgH;
    modelW = imgW;
end

% Adjust depth: crop if too many slices, pad if too few
if modelD > imgD
    rawModel = rawModel(:, :, 1:imgD, :, :);
    modelD = imgD;
elseif modelD < imgD
    padded = zeros(modelH, modelW, imgD, 1, modelT, class(rawModel));
    padded(:, :, 1:modelD, :, :) = rawModel;
    rawModel = padded;
    modelD = imgD;
end

% Ensure 5D: [H W D 1 T]
rawModel = reshape(rawModel, [modelH, modelW, modelD, 1, modelT]);

%% Create model and assign data

% createModel handles: layer-type transitions (type-63 ↔ type-255 pack/unpack
% of sel/mask bits), selectedMaterial, selectedAddToMaterial, lastSegmSelection,
% and annotations.clearContents().
obj.createModel(modelType);

% Rebuild the labels object from rawModel using the class constructor so that
% ALL dimension properties (height, width, depth, colors, time, dim_yxzct,
% maxInt, dataClass) are derived from the actual data via MibImage.initialize().
% Direct assignment (obj.labels.data{1} = rawModel) leaves those properties stale
% when createModel took the type-63 fast path and reused the existing object.
modelMeta = core.MibImage.initializeImgInfo( ...
    'pixSize', obj.image.pixSize, ...
    'Height',  modelH, 'Width', modelW, 'Depth', modelD, 'Time', modelT, 'Colors', 1);
if modelType == 63
    obj.labels = core.MibLabels63(rawModel, modelMeta);
else
    obj.labels = core.MibLabels(rawModel, modelMeta);
    obj.labels.maxMaterials = modelType;
end

%% Assign material metadata

% Fill material colors if missing
if isempty(materialColors)
    if modelType <= 255 && isfield(options, 'preferences') && ...
            isfield(options.preferences, 'Colors') && ...
            isfield(options.preferences.Colors, 'ModelMaterialColors')
        palette = options.preferences.Colors.ModelMaterialColors;
        nMat    = numel(materialNames);
        if nMat == 0
            nMat = max(0, double(max(rawModel(:))));
        end
        nPalette = size(palette, 1);
        if nMat > 0
            materialColors = palette(mod((0:nMat-1), nPalette) + 1, :);
        end
    else
        % Large model or no preferences: random colors
        nMat = numel(materialNames);
        if nMat == 0; nMat = max(0, double(max(rawModel(:)))); end
        if nMat > 0
            materialColors = rand(nMat, 3);
        end
    end
end

% Auto-generate numeric material names if none provided
if isempty(materialNames)
    nMat = size(materialColors, 1);
    if nMat == 0; nMat = max(0, double(max(rawModel(:)))); end
    materialNames = arrayfun(@(x) num2str(x), 1:nMat, 'UniformOutput', false);
end

obj.labels.materialNames  = materialNames;
obj.labels.materialColors = materialColors;
obj.labels.labelsVariable = labelsVariable;
obj.labels.countMaterials();

% Set model filename (first file or empty for import)
if ~isempty(filenames) && iscell(filenames) && ~isempty(filenames{1})
    obj.labels.filename = filenames{1};
end

% Apply bounding box if present
if ~isempty(boundingBox) && numel(boundingBox) == 6
    obj.updateBoundingBox(boundingBox);
end

obj.modelExist = true;
obj.lastSegmSelection = [2 1];

%% Handle annotations

obj.annotations.clearContents();
if ~isempty(labelText) && ~isempty(labelPosition)
    try
        obj.annotations.addLabels(labelText, labelPosition, labelValue);
    catch ME
        warning('MibDataset:loadModel', 'Could not import annotations: %s', ME.message);
    end
end

%% Return result struct

result.materialNames  = materialNames;
result.materialColors = materialColors;
result.modelType      = modelType;
result.labelsVariable = labelsVariable;
end
