function status = importMaterial(obj, BatchOptIn)
% IMPORTMATERIAL - Import selected materials from a saved model file into the current model.
%
% Syntax:
%   .. code-block:: matlab
%
%       status = obj.importMaterial(BatchOptIn)
%
% Loads a source model file, lets the user select a subset of its materials
% (by index), resizes the source pixel array to the current dataset
% dimensions (nearest-neighbour), then appends the selected materials as
% new slots - names, colors, and voxels - into the active model using an
% overwrite merge policy (existing voxels at the import locations are
% replaced by the source values).
%
% **BigData support:** for disk-backed pyramidal datasets
% (``core.MibBigDataLabels``) the source may have been saved at any pyramid
% resolution.  The closest matching pyramid level of the current dataset is
% selected automatically (``findClosestLevelForImport``), the source is
% resized to that level, and the voxels are written there with
% ``setData63``; coarser levels are updated eagerly and finer levels are
% reconstructed lazily by the level map.
%
% Input Arguments:
%   - **BatchOptIn** - *(optional)* a structure for batch processing mode; when
%     NaN, returns a structure with default options via "SyncBatch" event
%
%     - ``.Filename`` - char, full path to the source model file; leave empty
%       to open the file browser interactively [*default* ``''``]
%     - ``.MaterialIndices`` - char, MATLAB-style index expression for the
%       source materials to import (e.g. ``'1'``, ``'2:4'``, ``'1 3 5'``);
%       leave empty to prompt interactively (or import all in batch mode)
%       [*default* ``''``]
%     - ``.showWaitbar`` - logical, show or not the progress dialog
%       [*default* ``true``]
%     - ``.id`` - *(optional)*, dataset index 1-9, default = obj.getActiveId()
%
%
% Output Arguments:
%   - **status** - logical, true when the import completed successfully
%
% Usage:
%   **Example 1** - interactive: file browser + material selection dialog
%
%   .. code-block:: matlab
%
%      obj.mibModel.importMaterial();
%
%   **Example 2** - batch: import materials 1 and 3 from a specific file
%
%   .. code-block:: matlab
%
%      BatchOpt.Filename        = 'C:\data\source.model';
%      BatchOpt.MaterialIndices = '1 3';
%      BatchOpt.showWaitbar     = false;
%      obj.mibModel.importMaterial(BatchOpt);
%

% Updates
% 

if nargin < 2; BatchOptIn = struct(); end

status = false;

%% Declaration of the BatchOpt structure
BatchOpt = struct();
BatchOpt.Filename        = '';
BatchOpt.MaterialIndices = '';
BatchOpt.showWaitbar     = true;
BatchOpt.id              = obj.getActiveId();

BatchOpt.mibBatchSectionName = 'Ribbon -> Model';
BatchOpt.mibBatchActionName  = 'Import material';
BatchOpt.mibBatchTooltip.Filename        = 'Full path to the source model file from which to import materials; leave empty to open the file browser';
BatchOpt.mibBatchTooltip.MaterialIndices = 'Indices of source materials to import (e.g. ''1'', ''2:4'', ''1 3 5''); leave empty to import all materials';
BatchOpt.mibBatchTooltip.showWaitbar     = 'Show or not the progress bar during execution';

%% Batch mode check
if nargin == 2
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)
            BatchOpt = rmfield(BatchOpt, 'id');
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj, 'SyncBatch', eventdata);
        else
            ErrorDlgOpt.winTitle       = 'BatchOpt Error';
            ErrorDlgOpt.optionalPrefix = 'Error in MibModel.importMaterial';
            ErrorDlgOpt.err            = 'A structure as the 2nd parameter is required!';
            ErrorDlgOpt.WindowHeight   = 150;
            eventdata = core.ToggleEventData(ErrorDlgOpt);
            notify(obj, 'ShowErrorDialog', eventdata);
        end
        return;
    else
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end
end

dlgOpt.mibPath = obj.mibPath;

%% Initial checks

% Abort when selection/segmentation layers are disabled
if obj.I{BatchOpt.id}.enableSelection == 0
    dlgOpt.MsgBoxOnly   = true;
    dlgOpt.Icon         = 'puffin_warning';
    dlgOpt.HeaderLines  = 1;
    dlgOpt.WindowHeight = 160;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), 'The models are switched off!', {''}, ...
        {'Please make sure that the "Enable selection" option in the Preferences dialog (Ribbon->Home->Preferences) is set to "yes" and try again...'}, ...
        'Models are disabled', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

if ~obj.I{BatchOpt.id}.modelExist
    dlgOpt.MsgBoxOnly   = true;
    dlgOpt.Icon         = 'puffin_warning';
    dlgOpt.HeaderLines  = 1;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), 'No model exists!', {''}, ...
        {'Please create a model first (Ribbon -> Models -> New Model).'}, ...
        'No model', dlgOpt);
    return;
end

id = BatchOpt.id;

% BigData (disk-backed pyramidal) datasets need pyramid-level matching and a
% level-bounded setData63 write; standard/virtual datasets write full-res.
isBigData = isa(obj.I{id}.labels, 'core.MibBigDataLabels');

%% Resolve source model filename

% Build the default directory from the currently open image filename
imageFilename = obj.I{id}.image.filename;
if ~isempty(imageFilename) && ~strcmp(imageFilename, 'none.tif')
    defaultDirectory = fileparts(imageFilename);
else
    defaultDirectory = obj.currentDirectory;
end

if isempty(BatchOpt.Filename)
    % Interactive file browser - single-select
    fileFilter = { ...
        '*.model',                'MIB model (*.model)'; ...
        '*.am',                   'Amira Mesh (*.am)'; ...
        '*.h5;*.hdf5',            'HDF5 (*.h5, *.hdf5)'; ...
        '*.mat',                  'MATLAB file (*.mat)'; ...
        '*.mibCat',               'MIB categorical (*.mibCat)'; ...
        '*.mrc;*.rec;*.st',       'IMOD MRC (*.mrc, *.rec, *.st)'; ...
        '*.nrrd',                 'NRRD (*.nrrd)'; ...
        '*.tif;*.tiff',           'TIFF (*.tif, *.tiff)'; ...
        '*.xml',                  'HDF5+XML (*.xml)'; ...
        '*.*',                    'All files (*.*)'};

    [sourceFilenameResult, sourcePath] = utils.dlgs.mibUiGetFile(fileFilter, ...
        'Select source model file', defaultDirectory, 'off');
    if isequal(sourceFilenameResult, 0); return; end
    if iscell(sourceFilenameResult); sourceFilenameResult = sourceFilenameResult{1}; end
    BatchOpt.Filename = fullfile(sourcePath, sourceFilenameResult);
end

if ~isfile(BatchOpt.Filename)
    dlgOpt.MsgBoxOnly   = true;
    dlgOpt.Icon         = 'puffin_warning';
    dlgOpt.HeaderLines  = 1;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), 'Source model file not found!', {''}, ...
        {sprintf('The specified file was not found:\n%s', BatchOpt.Filename)}, ...
        'File not found', dlgOpt);
    return;
end

%% Load source model via the loader factory (reusing MibModel.loadModel loader path)

% Verify the file extension is supported
[~, ~, sourceExtension] = fileparts(BatchOpt.Filename);
sourceExtension = lower(strrep(sourceExtension, '.', ''));

allowedExtensions      = obj.extensionRegistryLoad.getAllowedExtensions('Model', 'Default', false);
allowedExtensionsNoDot = strrep(allowedExtensions, '.', '');
if ~ismember(sourceExtension, allowedExtensionsNoDot)
    utils.dlgs.showErrorDialog(obj.getProgressBarParent(), ...
        sprintf('The extension ".%s" is not supported for model loading.', sourceExtension), ...
        'Unsupported format');
    return;
end

loaderInfo = obj.extensionRegistryLoad.resolveLoader(BatchOpt.Filename, 'Model', 'Default');
if ischar(loaderInfo)
    % resolveLoader returned an error string instead of a struct
    utils.dlgs.showErrorDialog(obj.getProgressBarParent(), loaderInfo, 'Loader error');
    return;
end

loaderOptions.showWaitbar  = false;
loaderOptions.ParentFigure = obj.mibGUI;
loaderOptions.mibPath      = obj.mibPath;

try
    sourceLoader = io.LoaderFactory.create(loaderInfo, loaderOptions);
catch loaderException
    utils.dlgs.showErrorDialog(obj.getProgressBarParent(), ...
        sprintf('Failed to create loader: %s', loaderException.message), 'Loader error');
    return;
end

[sourceImginfo, sourceFiles] = sourceLoader.loadMetadata({BatchOpt.Filename}, loaderOptions);

if ~isKey(sourceImginfo, 'numEntries') || sourceImginfo{"numEntries"} == 0
    utils.dlgs.showErrorDialog(obj.getProgressBarParent(), ...
        sprintf('Loader returned no entries for:\n%s', BatchOpt.Filename), 'Load error');
    return;
end

[sourceModelRaw, ~] = sourceLoader.loadImages(sourceFiles, sourceImginfo, loaderOptions);

% Extract material metadata from imginfo (same keys as MibDataset.loadModel)
sourceMaterialNames  = {};
sourceMaterialColors = [];

if isKey(sourceImginfo, 'modelMaterialNames') && ~isempty(sourceImginfo{"modelMaterialNames"})
    sourceMaterialNames = sourceImginfo{"modelMaterialNames"};
end
if isKey(sourceImginfo, 'modelMaterialColors') && ~isempty(sourceImginfo{"modelMaterialColors"})
    sourceMaterialColors = sourceImginfo{"modelMaterialColors"};
end

% Fallback: Amira Mesh uses Materials_N_Name / Materials_N_Color keys
if isempty(sourceMaterialNames)
    amiraIndex = 1;
    while true
        nameKey  = sprintf('Materials_%d_Name', amiraIndex);
        colorKey = sprintf('Materials_%d_Color', amiraIndex);
        if isKey(sourceImginfo, nameKey)
            sourceMaterialNames{amiraIndex} = sourceImginfo{nameKey}; %#ok<AGROW>
            if isKey(sourceImginfo, colorKey)
                sourceMaterialColors(amiraIndex, :) = sourceImginfo{colorKey}; %#ok<AGROW>
            end
            amiraIndex = amiraIndex + 1;
        else
            break;
        end
    end
end

%% Normalise the raw model array to exactly 3D [height width depth]

sourceModelRaw = squeeze(sourceModelRaw);
sourceRawSize  = size(sourceModelRaw);
sourceHeight   = sourceRawSize(1);
sourceWidth    = sourceRawSize(2);
sourceDepth    = 1;
if numel(sourceRawSize) >= 3
    sourceDepth = sourceRawSize(3);
    % Collapse any colour or time dimensions beyond depth by taking index 1
    if numel(sourceRawSize) == 4
        sourceModelRaw = sourceModelRaw(:, :, :, 1);
    elseif numel(sourceRawSize) >= 5
        sourceModelRaw = sourceModelRaw(:, :, :, 1, 1);
    end
end
sourceModelRaw = reshape(sourceModelRaw, [sourceHeight, sourceWidth, sourceDepth]);

% Determine the number of source materials from metadata or pixel range
nSourceMaterials = numel(sourceMaterialNames);
if nSourceMaterials == 0
    nSourceMaterials = double(max(sourceModelRaw(:)));
    if nSourceMaterials > 0
        sourceMaterialNames = arrayfun(@(x) num2str(x), 1:nSourceMaterials, 'UniformOutput', false);
    end
end

if nSourceMaterials == 0
    dlgOpt.MsgBoxOnly   = true;
    dlgOpt.Icon         = 'puffin_warning';
    dlgOpt.HeaderLines  = 1;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), 'No materials found in source file!', {''}, ...
        {'The source model file contains no labelled voxels (all voxels are background).'}, ...
        'No materials', dlgOpt);
    return;
end

%% Interactive material selection prompt

if isempty(BatchOpt.MaterialIndices) && nSourceMaterials == 1
    % Only one source material - import it directly without prompting
    BatchOpt.MaterialIndices = '1';
elseif isempty(BatchOpt.MaterialIndices)
    % Build a display list of available source materials for the prompt body
    materialListLines = cell(nSourceMaterials, 1);
    for materialListIndex = 1:nSourceMaterials
        materialListLines{materialListIndex} = sprintf('  %d: %s', ...
            materialListIndex, sourceMaterialNames{materialListIndex});
    end
    materialListStr = strjoin(materialListLines, '\n');

    promptText = sprintf(['Specify indices of source materials to import\n' ...
        '(e.g. "1", "2:4", "1 3 5"):\n\n' ...
        'Available source materials:\n%s\n\n[numbers 1-%d]:'], ...
        materialListStr, nSourceMaterials);

    selectionDlgOpt = dlgOpt;
    selectionDlgOpt.WindowWidth = 500;
    selectionDlgOpt.WindowHeight = 205;
    selectionDlgOpt.Focus = 1;
    answer = utils.dlgs.inputSingleDlg(obj.getProgressBarParent(), ...
        {promptText}, ...
        {num2str(1:nSourceMaterials)}, ...
        'Import material', selectionDlgOpt);
    if isempty(answer); return; end
    BatchOpt.MaterialIndices = answer;
end

% Parse and validate material indices
if isempty(BatchOpt.MaterialIndices)
    selectedIndices = 1:nSourceMaterials;   % import all in batch mode when field is empty
else
    selectedIndices = str2num(BatchOpt.MaterialIndices); %#ok<ST2NM>
end

if isempty(selectedIndices)
    dlgOpt.MsgBoxOnly   = true;
    dlgOpt.Icon         = 'puffin_warning';
    dlgOpt.HeaderLines  = 1;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), ...
        sprintf('Wrong material indices: "%s"', BatchOpt.MaterialIndices), {''}, ...
        {'The field requires a list of numbers, e.g. "1", "2 4", or "3:5".'}, ...
        'Import material', dlgOpt);
    return;
end

% Clamp to valid source range
selectedIndices = selectedIndices(selectedIndices >= 1 & selectedIndices <= nSourceMaterials);
if isempty(selectedIndices)
    dlgOpt.MsgBoxOnly   = true;
    dlgOpt.Icon         = 'puffin_warning';
    dlgOpt.HeaderLines  = 1;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), 'No valid material indices!', {''}, ...
        {sprintf('All specified indices are out of range. The source model has only %d material(s).', nSourceMaterials)}, ...
        'Import material', dlgOpt);
    return;
end

%% Capacity check: ensure current model can accommodate the new slots

currentMaterialCount = numel(obj.I{id}.labels.materialNames);
maximumMaterials     = obj.I{id}.labels.maxMaterials;

if currentMaterialCount + numel(selectedIndices) > maximumMaterials
    dlgOpt.MsgBoxOnly   = true;
    dlgOpt.Icon         = 'puffin_warning';
    dlgOpt.HeaderLines  = 1;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), 'Model capacity exceeded!', {''}, ...
        {sprintf(['The current model already has %d material(s) and supports at most %d.\n' ...
            'Importing %d material(s) would exceed that capacity.\n\n' ...
            'Please remove some materials first, or convert the model to a larger type ' ...
            '(Ribbon -> Models -> Type).'], ...
            currentMaterialCount, maximumMaterials, numel(selectedIndices))}, ...
        'Capacity exceeded', dlgOpt);
    return;
end

%% Determine the write grid and resize the source to it (nearest-neighbour)
%
% Standard/Virtual: the write grid is the full-resolution model
% [height width depth].  BigData: pick the pyramid level whose resolution is
% closest to the source, then write at that level - the write grid is the
% size getData63 returns for the level over the full-resolution extent.

currentHeight = obj.I{id}.image.height;
currentWidth  = obj.I{id}.image.width;
currentDepth  = obj.I{id}.image.depth;

if isBigData
    % Closest pyramid level for the source resolution (reuses pickLevel logic)
    importLevel = obj.I{id}.labels.findClosestLevelForImport([sourceHeight, sourceWidth, sourceDepth]);

    % Read/write options bounded to the FULL-RESOLUTION extent; orientPhysRanges
    % inside getData63/setData63 maps these full-res coords onto the chosen level.
    bigDataOptions.pyramidLevel = importLevel;
    bigDataOptions.y = [1, currentHeight];
    bigDataOptions.x = [1, currentWidth];
    bigDataOptions.z = [1, currentDepth];

    % WSI safety net (warn-only): a coarse level is small, but a full-res import
    % level on a gigapixel slide is large - warn once before reading it.
    levelSizeYX = obj.I{id}.labels.modelLevelSizes(importLevel, 1:2);
    utils.warnLargeFullResRead(levelSizeYX(1), levelSizeYX(2));

    % Read the current labels at the import level - this defines the exact write
    % grid (size after level-scale division + clamping).
    currentLevelLabels = obj.I{id}.labels.getData63('labels', 3, [], bigDataOptions);
    writeSize  = size(currentLevelLabels, 1:3);
    remapClass = class(currentLevelLabels);
else
    writeSize  = [currentHeight, currentWidth, currentDepth];
    remapClass = class(obj.I{id}.labels.data);
end

if ~isequal([sourceHeight, sourceWidth, sourceDepth], writeSize)
    sourceClass        = class(sourceModelRaw);
    % Index-based nearest resize (toolbox-free, exact label indices, handles z).
    sourceModelResized = core.MibBigDataLabels.resizeBlockNearest(sourceModelRaw, writeSize);
    if ~strcmp(class(sourceModelResized), sourceClass)
        sourceModelResized = cast(sourceModelResized, sourceClass);
    end
else
    sourceModelResized = sourceModelRaw;
end

%% Optional progress dialog

waitbarHandle = [];
if BatchOpt.showWaitbar
    waitbarHandle = uiprogressdlg(obj.getProgressBarParent(), 'Value', 0, ...
        'Message', 'Importing materials, please wait...', ...
        'Title', 'Import material');
end

%% Append new material slots (metadata) and build the remapped pixel array

% Each selected source material s maps to a new target index
% t = currentMaterialCount + k (1-based offset into the loop).
% We first add all material slots so the labels metadata is complete,
% then remap voxels in a single pass over the source array.

remappedLabels = zeros(writeSize, remapClass);

for materialImportLoopIndex = 1:numel(selectedIndices)
    sourceIndex = selectedIndices(materialImportLoopIndex);
    targetIndex = currentMaterialCount + materialImportLoopIndex;

    % Append a new slot to the labels metadata (name + auto-random color)
    [addResult, ~] = obj.I{id}.addMaterial(sourceMaterialNames{sourceIndex}, [], []);
    if ~addResult
        if ~isempty(waitbarHandle); delete(waitbarHandle); end
        dlgOpt.MsgBoxOnly   = true;
        dlgOpt.Icon         = 'puffin_warning';
        dlgOpt.HeaderLines  = 1;
        utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), 'Failed to add material slot!', {''}, ...
            {sprintf('Could not allocate a material slot for "%s". The model may be full.', ...
                sourceMaterialNames{sourceIndex})}, ...
            'Import material', dlgOpt);
        return;
    end

    % Overwrite the auto-assigned random color with the source file's color
    if sourceIndex <= size(sourceMaterialColors, 1)
        obj.I{id}.labels.materialColors(targetIndex, :) = sourceMaterialColors(sourceIndex, :);
    end

    % Accumulate this material's voxels in the remapped array
    remappedLabels(sourceModelResized == sourceIndex) = targetIndex;

    if ~isempty(waitbarHandle)
        waitbarHandle.Value = 0.15 + 0.45 * materialImportLoopIndex / numel(selectedIndices);
    end
end

%% Backup, merge imported voxels (overwrite policy), and write back

importMask = remappedLabels > 0;

if isBigData
    % Snapshot the import level (not the current display level) so undo/redo
    % restore at the exact resolution setData63 writes; x/y/z pin the full-res
    % extent because backup -> store records coordinates in full-res pixels.
    backupOptions.id        = id;
    backupOptions.magFactor = obj.I{id}.labels.modelScaleFactors(importLevel, 1);
    backupOptions.x         = [1, currentWidth];
    backupOptions.y         = [1, currentHeight];
    backupOptions.z         = [1, currentDepth];
    obj.backup('labels', 1, backupOptions);

    if ~isempty(waitbarHandle); waitbarHandle.Value = 0.65; end

    % Overlay imported voxels onto the level we already read, then write the
    % whole level back; setData63 propagates to coarser levels, marks the
    % touched tiles, and leaves finer levels to reconstruct lazily.
    combinedLabels             = currentLevelLabels;
    combinedLabels(importMask) = remappedLabels(importMask);
    obj.I{id}.labels.setData63(combinedLabels, 'labels', 3, [], bigDataOptions);

    % Persist the new material names/colours to the store attributes.
    obj.I{id}.labels.writeMaterialMetadata();

    % Persist the level map (sidecar). setData63 wrote the pixels live at the
    % import level + coarser and marked the touched tiles authoritative at that
    % level in the in-memory matLevel; finer levels stay virtual and reconstruct
    % on demand. Without writing the sidecar, reopening the model finds no level
    % map and falls back to "all levels precise" (initLevelMapFallback) - which
    % reads the never-materialized finer level directly and shows the imported
    % material only on slices that happened to be viewed this session. Saving the
    % sidecar lets a reopen reconstruct every finer slice correctly.
    obj.I{id}.labels.saveLevelMap();
else
    backupOptions.id = id;
    obj.backup('labels', 1, backupOptions);

    if ~isempty(waitbarHandle); waitbarHandle.Value = 0.65; end

    getDataOptions.id = id;
    targetLabels = cell2mat(obj.getData3D('labels', [], 3, [], getDataOptions));
    targetLabels(importMask) = remappedLabels(importMask);
    obj.setData3D(targetLabels, 'labels', [], 3, [], getDataOptions);
end

if ~isempty(waitbarHandle); waitbarHandle.Value = 0.9; end

%% Post-action updates

eventdata = core.ToggleEventData({'ribbonModel', 'checkboxes'});
notify(obj, 'UpdateGuiWidgets', eventdata);
notify(obj, 'ShowImage');

% Notify batch mode (remove id - not stored in SyncBatch)
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);

if ~isempty(waitbarHandle); waitbarHandle.Value = 1; delete(waitbarHandle); end

status = true;
end
