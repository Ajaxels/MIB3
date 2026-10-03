function result = loadModel(obj, filenames, options)
% LOADMODEL - Load a segmentation model into this dataset from files or a raw array.
%
% Syntax:
%   .. code-block:: matlab
%
%       result = obj.loadModel(filenames, options)
%
% This is the dataset-level orchestrator for model loading.  It is called
% by MibModel.loadModel after BatchOpt processing, virtual-mode guarding,
% and file browsing have been completed.  It handles:
%
% FILE PATH  - filenames is a cell array of full file paths.
% Dispatches to the loader identified by options.loaderInfo.
%
% IMPORT PATH - options.model contains the raw array (workspace import).
% filenames is empty ([]); the loader is bypassed entirely.
%
% After the array is obtained the method validates dimensions against the
% open image, calls createModel(), writes the data, and populates all label
% metadata properties.
%
% Input Arguments:
%   - **filenames** - cell array with full file paths, or [] for the import path
%   - **options** - struct with loading parameters
%
%     - ``.loaderInfo`` - struct returned by ExtensionRegistryLoad.resolveLoader
%       (required for the file path; ignored for import)
%     - ``.model`` - raw array to import (import path only)
%     - ``.modelMaterialNames`` - cell array of names for the import path
%     - ``.modelMaterialColors`` - Nx3 RGB matrix for the import path
%     - ``.modelType`` - numeric model type (63/255/65535/4294967295)
%     - ``.labelText`` - annotation text cell array (or [])
%     - ``.labelPosition`` - annotation positions (or [])
%     - ``.labelValue`` - annotation values (or [])
%     - ``.batchModeSwitch`` - [logical, {false}] suppress interactive dialogs
%     - ``.preferences`` - MIB preferences struct (for color fallback)
%     - ``.ParentFigure`` - parent figure handle for dialogs
%     - ``.mibPath`` - path to MIB installation directory
%     - ``.showWaitbar`` - [logical, {true}] show progress dialog
%
% Output Arguments:
%   - **result** - struct with loaded metadata, or [] on error or user cancel
%
%     - ``.materialNames`` - cell array of material names
%     - ``.materialColors`` - Nx3 RGB color matrix
%     - ``.modelType`` - numeric type used
%     - ``.labelsVariable`` - variable name
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     options.loaderInfo = obj.mibModel.extensionRegistryLoad.resolveLoader('file.model','Model','Default');
%     options.preferences = obj.mibModel.preferences;
%     result = obj.mibModel.I{obj.mibModel.id}.loadModel({'C:\data\Labels.model'}, options);
%
%
%   **Example 2** - import path
%
%   .. code-block:: matlab
%
%
%     % import path
%     options.model = myModelArray;
%     options.modelMaterialNames = {'Cell','Nucleus'};
%     result = obj.mibModel.I{obj.mibModel.id}.loadModel([], options);
%

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
if ~isfield(options, 'objects3D');         options.objects3D = []; end

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
objects3D        = options.objects3D;

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
    % [OME-Zarr] nested labels group inside the container, honoured by the
    % Zarr2/Zarr3 setup loaders to skip the container search and its picker
    if isfield(options, 'ZarrGroupPath'); loaderOpts.ZarrGroupPath = options.ZarrGroupPath; end
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
        parentFig = [];
        if isfield(loaderOpts, 'ParentFigure'); parentFig = loaderOpts.ParentFigure; end
        utils.dlgs.showErrorDialog(parentFig, sprintf('Loader returned no entries for: %s', filenames{1}), 'MibDataset:loadModel');
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
    if isKey(imginfo, 'modelObjects3D') && ~isempty(imginfo{"modelObjects3D"})
        objects3D = imginfo{"modelObjects3D"};
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
        choice = obj.promptSizeMismatch('Model', modelH, modelW, imgH, imgW, boundingBox, options);
        if choice.cancelled; return; end
        switch choice.action
            case 'Use bounding box'
                % offset comes from the model's own BoundingBox rather than user
                % entry - both bounding boxes are normalized to micrometres by
                % MibImage.updateBoundingBox, which is how the current image's
                % own boundingBox was set in the first place
                shiftY = (boundingBox(3) - obj.image.boundingBox(3)) / obj.image.pixSize.y;
                shiftX = (boundingBox(1) - obj.image.boundingBox(1)) / obj.image.pixSize.x;
                choice.offsetY = min(round(abs(shiftY)), abs(imgH - modelH));
                choice.offsetX = min(round(abs(shiftX)), abs(imgW - modelW));
                action = 'Crop';
            case 'Crop / Place'
                action = 'Crop';
            otherwise
                action = 'Resize';
        end
    else
        % unattended (batch / no parent figure): keep the previous silent
        % top-left crop/pad fallback
        action = 'Crop';
        choice = struct('offsetY', 0, 'offsetX', 0);
    end
    rawModel = core.MibDataset.applySizeMismatch(rawModel, imgH, imgW, action, choice.offsetY, choice.offsetX);
    modelH = imgH;
    modelW = imgW;
end

% Adjust depth: crop if too many slices, insert at current slice if too few
isPartialImport = false;
insertStart     = 1;
insertEnd       = imgD;
if modelD > imgD
    rawModel = rawModel(:, :, 1:imgD, :, :);
    modelD = imgD;
elseif modelD < imgD
    % Place the sub-stack starting at the currently viewed slice
    isPartialImport = true;
    insertStart  = obj.slices{3}(1);
    insertEnd    = min(insertStart + modelD - 1, imgD);
    insertCount  = insertEnd - insertStart + 1;
    padded = zeros(modelH, modelW, imgD, 1, modelT, class(rawModel));
    padded(:, :, insertStart:insertEnd, :, :) = rawModel(:, :, 1:insertCount, :, :);
    rawModel = padded;
    modelD = imgD;
end

% Ensure 5D: [H W D 1 T]
rawModel = reshape(rawModel, [modelH, modelW, modelD, 1, modelT]);

%% Preserve existing labels on non-imported slices

% When a sub-stack is imported into an existing same-type model, save the
% current label data before createModel wipes the layer, so the slices
% outside the insertion window can be restored afterwards.
existingLabelsData = [];
if isPartialImport && obj.modelExist && obj.labels.exists && obj.labels.maxMaterials == modelType
    existingLabelsData = obj.labels.data;
end

%% Create model and assign data

% createModel handles: layer-type transitions (type-63 ↔ type-255 pack/unpack
% of sel/mask bits), selectedMaterial, selectedAddToMaterial, lastSegmSelection,
% and annotations.clearContents().
obj.createModel(modelType);

% Rebuild the labels object from rawModel using the class constructor so that
% ALL dimension properties (height, width, depth, colors, time, dim_yxzct,
% maxInt, dataClass) are derived from the actual data via MibImage.initialize().
% Direct assignment (obj.labels.data = rawModel) leaves those properties stale
% when createModel took the type-63 fast path and reused the existing object.
modelMeta = core.MibImage.initializeImgInfo( ...
    'pixSize', obj.image.pixSize, ...
    'Height',  modelH, 'Width', modelW, 'Depth', modelD, 'Time', modelT, 'Colors', 1);
if modelType == 63
    obj.labels = core.MibLabels63(rawModel, modelMeta);
    obj.labels.maskFilename = obj.image.maskFilename;
else
    obj.labels = core.MibLabels(rawModel, modelMeta);
    obj.labels.maxMaterials = modelType;
end

% Merge existing labels back into the slices outside the insertion window
if ~isempty(existingLabelsData)
    mergedData = existingLabelsData;
    mergedData(:, :, insertStart:insertEnd, :, :) = rawModel(:, :, insertStart:insertEnd, :, :);
    obj.labels.data = mergedData;
end

%% Assign material metadata

% Fill material colors if missing
if isempty(materialColors)
    if modelType > 255
        % >255-material models pick the colour directly by material index, so the
        % palette has to span the whole range (same as core.MibDataset.createModel)
        materialColors = rand(65535, 3);
    elseif modelType <= 255 && isfield(options, 'preferences') && ...
            isfield(options.preferences, 'Colors') && ...
            isfield(options.preferences.Colors, 'ModelMaterialColors') && ...
            ~isempty(options.preferences.Colors.ModelMaterialColors)
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
        % Large model, no preferences, or an empty preference palette: random colors
        nMat = numel(materialNames);
        if nMat == 0; nMat = max(0, double(max(rawModel(:)))); end
        if nMat > 0
            materialColors = rand(nMat, 3);
        end
    end
end

% Auto-generate material names if none provided
if isempty(materialNames)
    nMat = size(materialColors, 1);
    if nMat == 0; nMat = max(0, double(max(rawModel(:)))); end
    if modelType <= 255
        materialNames = arrayfun(@(x) sprintf('mat%d', x), 1:nMat, 'UniformOutput', false);
    else
        % >255-material models: the segmentation table offers only two material
        % slots and the plain numeric name of each slot carries the material index
        % currently shown there (see "How to work with models having more than 255
        % materials" in docs/user-interface/ribbon/model/index.md). Generating one
        % name per material index instead would desynchronise the slots from the
        % table rows and break renaming of materials.
        materialNames = {'1'; '2'};
    end
end

% Large models address colours by material index, so the palette must always
% cover the full range even when the file supplied a shorter one
if modelType > 255 && size(materialColors, 1) < 65535
    nExistingColors = size(materialColors, 1);
    materialColors(nExistingColors+1:65535, :) = rand(65535 - nExistingColors, 3);
end

obj.labels.materialNames  = materialNames;
obj.labels.materialColors = materialColors;
obj.labels.labelsVariable = labelsVariable;
obj.labels.countMaterials();

% An instance model numbers its objects either through the volume or afresh on
% every slice, and nothing in the array tells the two apart. Files written
% before the flag existed, and every format other than .model, do not carry it,
% so the user is asked. Without a dialog - batch mode or no parent - the answer
% is 3D: its next free index is unused on every slice, while a per-slice one can
% repeat the number of an object elsewhere in a stitched model.
if modelType > 255
    if isempty(objects3D)
        objects3D = true;
        if ~options.batchModeSwitch && isfield(options, 'ParentFigure') && ~isempty(options.ParentFigure)
            dlgOpt = struct('HeaderLines', 1, 'Icon', 'puffin_question', 'WindowHeight', 200);
            if isfield(options, 'mibPath'); dlgOpt.mibPath = options.mibPath; end
            answer = utils.dlgs.inputUniversalDlg(options.ParentFigure, ...
                'Are the objects of this model 2D or 3D?', ...
                {sprintf(['3D: each index is one object through the whole volume (a stitched model)\n' ...
                          '2D: the numbering restarts on every slice'])}, ...
                {{'3D objects', '2D objects', 1}}, 'Instance model', dlgOpt);
            if ~isempty(answer)
                objects3D = strcmp(answer{1}, '3D objects');
            end
        end
    end
    obj.labels.objects3D = logical(objects3D);
end

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
