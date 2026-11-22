function converted = convertModel(obj, ModelType, BatchOptIn, convertOptions)
% CONVERTMODEL - Convert the segmentation model to a different type.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.convertModel()
%       obj.convertModel(ModelType)
%       obj.convertModel(ModelType, BatchOptIn)
%       converted = obj.convertModel(ModelType, BatchOptIn, convertOptions)
%
% Converts the segmentation model between capacity types (63, 255, 16383, 65535,
% 4294967295 materials) or generates a new model where each connected
% object receives a unique index (2D or 3D connectivity).
%
% Changing between integer types adjusts memory usage and the maximum
% number of materials.  Converting to an indexed-object type reruns
% connected-component labelling on all materials and replaces the model
% with per-object indices.
%
% Input Arguments:
%   - **ModelType** *(optional)* - numeric model type to convert to:
%
%     - ``63``         - packed uint8; mask and selection stored in bits 7-8
%     - ``16383``      - packed uint16 instance model; mask and selection in bits 15-16
%     - ``1073741823`` - **BigData only**: packed uint32 instance model; mask and
%       selection in bits 31-32. A Standard dataset converts to ``4294967295``
%       instead, the separate-layer type that holds the same indices
%     - ``255``        - separate uint8 labels layer
%     - ``65535``      - separate uint16 labels layer
%     - ``4294967295`` - separate uint32 labels layer
%     - ``2.4``        - detect 2D objects (connectivity 4) and index them
%     - ``2.8``        - detect 2D objects (connectivity 8) and index them
%     - ``3.6``        - detect 3D objects (connectivity 6) and index them
%     - ``3.26``       - detect 3D objects (connectivity 26) and index them
%
%   - **BatchOptIn** *(optional)* - structure for batch processing; pass
%     ``NaN`` to return default options via ``SyncBatch`` event
%
%     - ``.ModelType``    - cell string dropdown, first element is selected value
%     - ``.ModelStorePath`` - char, BigData only: path of the new model store
%       (``.zarr3`` or ``.zarr2``). Empty (default) = next to the current store,
%       with ``_63``, ``_16383`` or ``_1073741823`` added to its name;
%       interactively the user is asked with that as the suggestion
%     - ``.showWaitbar``  - logical, show or not the waitbar [*default* ``true``]
%     - ``.id``           - *(optional)* dataset index 1-9; default = active dataset
%
%   - **convertOptions** *(optional)* - structure with options for callers in
%     code, not part of BatchOpt and never recorded by the batch tool:
%
%     - ``.keepMaterials`` - logical, **BigData only** [*default* ``true``]. When
%       ``false`` the new store gets only the mask and selection bits of
%       the old one, the labels stay empty and the colors are generated. Used by
%       ``controllers.Annotations.convertModelFromAnnotations``, which
%       writes its own objects into the empty store afterwards; the explanation
%       shown before the store path is asked says so. Ignored on Standard
%       datasets, whose callers convert with ``core.MibDataset.convertModel``
%
% Output Arguments:
%   - **converted** - logical, true when the model now has the requested type
%     (also when it already had it). False after a refusal or a cancel; the
%     model is then unchanged
%
% .. note::
%    **BigData** converts between the packed types 63, 16383 and 1073741823, in
%    either direction, into a **new store**: a store's array type is fixed when
%    it is created, so the uint8 packed levels cannot become uint16 (or uint32)
%    in place. Every pyramid level is remapped voxel by voxel in chunk-aligned
%    strips (index kept, mask bit and selection bit moved to the top two bits of
%    the new class: 7/8, 15/16 or 31/32) and the level map is copied, so levels
%    that were still deferred stay deferred and nothing is materialized. From 63,
%    material index k becomes object index k with the colour it had; as on a
%    Standard dataset, one material is one object until it is split. Between the
%    instance types the object indices, their colours and ``objects3D`` carry
%    over. To 63, object k becomes material k and the materials ``1..N`` are
%    listed by number. The instance index is not copied and is rebuilt by the
%    next scan.
%
%    **To a smaller type** every index above the top index of the target
%    (``modelType``) is set to it, so all such objects become one. Unlike the
%    Standard route, which refuses this, the conversion goes ahead because the
%    old store is kept: the dialog shown first warns when
%    ``labels.maxIndexUsed`` (the highest index over every level) is above the
%    target's top index; a protocol, or a call with ``.ModelStorePath`` set,
%    prints the warning to the command window instead. After the copy the
%    number of full-resolution voxels that were clamped is printed too. Clamping
%    is per voxel, so it commutes with the nearest-neighbour pyramid just like
%    the remap. The dataset then switches
%    to the new store and the old one is closed and left on disk unchanged -
%    loading it again is the way back, so the dialog shown first explains
%    rather than warns. Ctrl+Z does not switch back (a disk-backed model cannot
%    be snapshotted), and the undo history is cleared: it holds snapshots of the
%    old type the new store cannot take back. Cancel removes the partly written
%    store and keeps the old model. Virtual datasets are refused.
%
% **Example 1** - convert current model to 255-material type
%
%   .. code-block:: matlab
%
%      obj.mibModel.convertModel(255);
%
% **Example 2** - batch call
%
%   .. code-block:: matlab
%
%      BatchOpt.ModelType = {'65535'};
%      obj.mibModel.convertModel([], BatchOpt);
%

% Updates
% Ported from MIB2 mibModel.convertModel

converted = false;
if nargin < 2; ModelType = []; end
if nargin < 4 || isempty(convertOptions); convertOptions = struct(); end
if ~isfield(convertOptions, 'keepMaterials'); convertOptions.keepMaterials = true; end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
if ~isempty(ModelType)
    switch ModelType
        case 2.4;  BatchOpt.ModelType = {'indexed objects 2D/4'};
        case 2.8;  BatchOpt.ModelType = {'indexed objects 2D/8'};
        case 3.6;  BatchOpt.ModelType = {'indexed objects 3D/6'};
        case 3.26; BatchOpt.ModelType = {'indexed objects 3D/26'};
        otherwise; BatchOpt.ModelType = {num2str(ModelType)};
    end
else
    BatchOpt.ModelType = {'63'};
end
BatchOpt.ModelType{2} = {'63', '255', '16383', '65535', '4294967295', '1073741823', ...
    'indexed objects 2D/4', 'indexed objects 2D/8', ...
    'indexed objects 3D/6', 'indexed objects 3D/26'};

BatchOpt.ModelStorePath = '';
BatchOpt.showWaitbar = true;
BatchOpt.id = obj.getActiveId();

BatchOpt.mibBatchSectionName = 'Ribbon -> Model';
BatchOpt.mibBatchActionName  = 'Convert type';
BatchOpt.mibBatchTooltip.ModelType   = 'Type of model to convert to; higher capacity types use more memory. BigData: between 63, 16383 and 1073741823; to a smaller type, indices above its maximum become the maximum. 1073741823 is BigData only (Standard gets 4294967295)';
BatchOpt.mibBatchTooltip.ModelStorePath = 'BigData only: path of the new model store; empty = next to the current store, with _63, _16383 or _1073741823 added to its name';
BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';

%% Batch mode check actions
batchModeSwitch = nargin >= 3 && isstruct(BatchOptIn) && isfield(BatchOptIn, 'mibBatchTooltip');
if nargin >= 3 && ~isempty(BatchOptIn)
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)
            BatchOpt = rmfield(BatchOpt, 'id');
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj, 'SyncBatch', eventdata);
        else
            ErrorDlgOpt.winTitle = 'BatchOpt Error';
            ErrorDlgOpt.optionalPrefix = 'Error in MibModel.convertModel';
            ErrorDlgOpt.err = 'A structure as the 3rd parameter is required!';
            ErrorDlgOpt.WindowHeight = 150;
            eventdata = core.ToggleEventData(ErrorDlgOpt);
            notify(obj, 'ShowErrorDialog', eventdata);
        end
        return;
    else
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end
end

dlgOpt.mibPath = obj.mibPath;

%% Virtual stacking guard
% BigData has its own route below, once the target type is known
if obj.I{BatchOpt.id}.datasetType(1) == 'V'
    dlgOpt.MsgBoxOnly  = true;
    dlgOpt.Icon        = 'puffin_warning';
    dlgOpt.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), 'Not available in Virtual mode!', {''}, ...
        {'Model type conversion requires memory-resident (Standard) mode. Please switch to standard mode and try again.'}, ...
        'Virtual mode', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

%% Initial checks
if obj.I{BatchOpt.id}.enableSelection == 0
    dlgOpt.MsgBoxOnly  = true;
    dlgOpt.Icon        = 'puffin_warning';
    dlgOpt.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), 'The models are switched off!', {''}, ...
        {'Please enable the "Enable selection" option in Preferences (Ribbon -> Home -> Preferences) and try again.'}, ...
        'Models are disabled', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

if ~obj.I{BatchOpt.id}.modelExist
    dlgOpt.MsgBoxOnly  = true;
    dlgOpt.Icon        = 'puffin_warning';
    dlgOpt.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), 'No model exists!', {''}, ...
        {'Please create a model first (Ribbon -> Models -> New Model).'}, ...
        'No model', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

%% Map string → numeric model type
switch BatchOpt.ModelType{1}
    case 'indexed objects 2D/4';  modelType = 2.4;
    case 'indexed objects 2D/8';  modelType = 2.8;
    case 'indexed objects 3D/6';  modelType = 3.6;
    case 'indexed objects 3D/26'; modelType = 3.26;
    otherwise;                    modelType = str2double(BatchOpt.ModelType{1});
end
% the packed uint32 type is BigData only; on Standard 4294967295 holds the same indices
if modelType == 1073741823 && obj.I{BatchOpt.id}.datasetType(1) ~= 'B'
    modelType = 4294967295;
end

%% Early-exit if already the requested type
if modelType == obj.I{BatchOpt.id}.labels.maxMaterials; converted = true; return; end

%% BigData: to another packed type, into a new store
if obj.I{BatchOpt.id}.datasetType(1) == 'B'
    converted = localConvertBigData(obj, BatchOpt, modelType, batchModeSwitch, dlgOpt, ...
        convertOptions.keepMaterials);
    if converted
        notify(obj, 'UpdateGuiWidgets', core.ToggleEventData({'ribbonModel', 'checkboxes'}));
        notify(obj, 'ShowImage');
        notify(obj, 'SyncBatch', core.ToggleEventData(rmfield(BatchOpt, 'id')));
    else
        notify(obj, 'StopProtocol');
    end
    return;
end

%% Guard: indexed-object detection only works for 63/255-material models
if modelType < 4 && obj.I{BatchOpt.id}.labels.maxMaterials > 256
    utils.dlgs.showErrorDialog(obj.getProgressBarParent(), ...
        'Indexed-object detection is only supported for models with 63 or 255 materials.', ...
        'Wrong model type');
    notify(obj, 'StopProtocol');
    return;
end

%% Guard: the target type must hold the largest index in use
% MibDataset.convertModel clips larger indices onto the top one, merging unrelated
% objects; refuse here, before the backup, so the model stays as it is
labelsLayer = obj.I{BatchOpt.id}.labels;
if modelType >= 4 && labelsLayer.exists
    if isa(labelsLayer, 'core.MibLabels63')
        maxIndex = double(max(bitand(labelsLayer.data, labelsLayer.materialMask), [], 'all'));
    else
        maxIndex = double(max(labelsLayer.data, [], 'all'));
    end
    if maxIndex > modelType
        utils.dlgs.showErrorDialog(obj.getProgressBarParent(), ...
            sprintf(['The model uses index %d, but a %d-material model holds indices up to %d.\n' ...
            'The model was not converted.'], maxIndex, modelType, modelType), ...
            'Too many materials');
        notify(obj, 'StopProtocol');
        return;
    end
end

%% Backup the segmentation layers for undo
% 'modelLayers' keeps the layer objects, so Ctrl+Z restores the previous model
% type together with its pixel data, material names and colours
obj.backup('modelLayers', 1, struct('id', BatchOpt.id));

%% Perform conversion
wb = [];
if BatchOpt.showWaitbar
    wb = uiprogressdlg(obj.getProgressBarParent(), 'Value', 0, ...
        'Message', sprintf('Converting model to "%s"\nPlease wait...', BatchOpt.ModelType{1}), ...
        'Title', 'Convert model');
end

obj.I{BatchOpt.id}.convertModel(modelType, wb);

if BatchOpt.showWaitbar; wb.Value = 1; end

notify(obj, 'UpdateGuiWidgets', core.ToggleEventData({'ribbonModel', 'checkboxes'}));
notify(obj, 'ShowImage');

% Notify batch mode
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);

if BatchOpt.showWaitbar; delete(wb); end
converted = true;
end

% =====================================================================
function converted = localConvertBigData(obj, BatchOpt, modelType, batchModeSwitch, dlgOpt, keepMaterials)
% Convert a BigData packed store into a new store of another packed type
% (63, 16383, 1073741823, either direction) and switch to it.
%
% See the BigData note of the main docblock for what is converted, why into a
% new store, and how indices above a smaller target's top index are clamped.
% The remap is per voxel, so it commutes with the nearest-neighbour
% downsampling that built the coarser levels: converting each level on its own
% gives the pyramid the new type would have had from the start, and the copied
% level map keeps its meaning.
%
% With keepMaterials false (``convertOptions.keepMaterials``) the material bits
% are dropped in the same pass: only mask and selection reach the new store.
% The level map is still copied, so a labels tile keeps its level and now holds
% zeros there, which is what a recomputation from that level gives too.
%
% Output Arguments:
%   - **converted** - logical, true when the dataset now uses the new store.
%     False on every refusal, a cancel from the user, or a Cancel during the
%     copy - the old model is then still the one in use
converted = false;
dataset = obj.I{BatchOpt.id};
source = dataset.labels;

% target layout of each packed type
switch modelType
    case 63;         targetClass = 'uint8';
    case 16383;      targetClass = 'uint16';
    case 1073741823; targetClass = 'uint32';
    otherwise;       targetClass = '';
end
isEditableStore = isa(source, 'core.MibBigDataLabels') && ~isa(source, 'core.MibBigDataLabelsZarr2');
if isempty(targetClass) || ~isEditableStore || ...
        ~ismember(source.containerClass, {'uint8', 'uint16', 'uint32'}) || source.maxMaterials == modelType
    localMessage(obj, dlgOpt, 'Not available for this BigData model!', ...
        {['A BigData model converts between the packed types 63, 16383 and 1073741823, ' ...
        'and only when its store was created by MIB.']});
    return;
end
sourceTypeText = sprintf('%d-material', source.maxMaterials);
targetTypeText = sprintf('%d', modelType);
% The material bits of the target type hold indices up to modelType; a higher
% index of a smaller target is clamped to it, which merges all such objects
% into one. maxIndexUsed is the highest index of every level of the store.
targetMaxIndex = modelType;
if modelType == 63; indexWord = 'material'; else; indexWord = 'object'; end
clampWarning = '';
if keepMaterials && double(source.maxIndexUsed) > targetMaxIndex
    clampWarning = sprintf(['The model uses indices up to %d, but a %s model holds indices up to %d. ' ...
        'Every voxel with a higher index gets index %d, so all those objects become %s %d.'], ...
        double(source.maxIndexUsed), targetTypeText, targetMaxIndex, targetMaxIndex, indexWord, targetMaxIndex);
end
warningShown = false;

%% Where the new store goes
sourcePath = char(source.modelStorePath);
[sourceFolder, sourceName, sourceExtension] = fileparts(sourcePath);
targetPath = char(BatchOpt.ModelStorePath);
if isempty(targetPath)
    targetPath = fullfile(sourceFolder, [sourceName '_' targetTypeText sourceExtension]);
    if ~batchModeSwitch
        % An explanation rather than a warning: the old store is kept as it is,
        % so nothing is lost that loading it again would not bring back
        parent = obj.getProgressBarParent();
        if ~isempty(parent) && all(isvalid(parent))
            if ~keepMaterials
                contentsText = ['Only the objects under the annotations are written, with the numbers ' ...
                    'from the annotation names. The mask and selection are kept.'];
            elseif modelType == 63
                contentsText = 'Each object becomes the material with the same number and color.';
            elseif source.maxMaterials > 255
                contentsText = 'Every object keeps its number and color.';
            else
                contentsText = 'Each material becomes one object with the same number and color.';
            end
            icon = 'info';
            if ~isempty(clampWarning)
                contentsText = sprintf('%s\n\nWARNING: %s', contentsText, clampWarning);
                icon = 'warning';
            end
            answer = uiconfirm(parent, sprintf(['The model will be copied into a new %s model store; ' ...
                'you choose where in the next step.\n\n%s\n\n' ...
                'The %s store stays on disk unchanged, so you can return to it by loading it again. ' ...
                'Earlier undo steps are not kept.'], targetTypeText, contentsText, sourceTypeText), ...
                'Convert model', 'Options', {'Continue', 'Cancel'}, ...
                'DefaultOption', 1, 'CancelOption', 2, 'Icon', icon);
            if ~strcmp(answer, 'Continue'); return; end
            warningShown = true;
        end
        [storeFile, storeFolder] = uiputfile( ...
            {'*.zarr3', 'OME-Zarr v3 model store (*.zarr3)'; ...
             '*.zarr2', 'OME-Zarr v2 model store (*.zarr2)'}, ...
            sprintf('Save the %s model as a new store (the %s store is kept)', targetTypeText, sourceTypeText), ...
            targetPath);
        if isequal(storeFile, 0); return; end
        targetPath = fullfile(storeFolder, storeFile);
    end
end
if strcmpi(strrep(targetPath, '/', '\'), strrep(sourcePath, '/', '\'))
    localMessage(obj, dlgOpt, 'The new store needs a path of its own!', ...
        {sprintf('The %s model is written next to the current one, which stays as it is. Choose another name.', targetTypeText)});
    return;
end
if batchModeSwitch && isfolder(targetPath)
    % uiputfile asked about overwriting; a protocol never replaces a folder
    localMessage(obj, dlgOpt, 'The target model store already exists!', {targetPath});
    return;
end
if ~isempty(clampWarning) && ~warningShown
    % a protocol, or a caller that named the store: nobody to ask, so it is said
    fprintf(2, 'Convert model: WARNING: %s\n', clampWarning);
end

%% Copy, level by level
wb = [];
if BatchOpt.showWaitbar
    wb = uiprogressdlg(obj.getProgressBarParent(), 'Value', 0, 'Cancelable', 'on', ...
        'Message', sprintf('Converting the model to %s objects\nPlease wait...', targetTypeText), 'Title', 'Convert model');
end

meta = core.MibImage.initializeImgInfo('pixSize', dataset.image.pixSize, ...
    'Height', dataset.image.height, 'Width', dataset.image.width, ...
    'Depth', dataset.image.depth, 'Time', dataset.image.time, 'Colors', 1);
% The new store copies the geometry of the old one - level sizes, scale factors
% and chunk shapes - not the image pyramid: a model store can have fewer levels
% than its image (seen: 3 against 4), and a level-for-level copy needs the two
% stores to agree, which this makes true by construction.
levelSizes = source.modelLevelSizes;
storeGeometry = struct('axisOrder', 'yxz', 'levelImageSizes', levelSizes, ...
    'levelScaleFactors', source.modelScaleFactors, ...
    'chunkSizes', {cell(1, size(levelSizes, 1))});
for level = 1:size(levelSizes, 1)
    storeGeometry.chunkSizes{level} = double(source.modelArrays{level}.info().chunkShape);   % [y x z]
end
target = core.MibBigDataLabels([], meta);
target.setLayout(targetClass);
target.createStore([source.height, source.width, source.depth], targetPath, storeGeometry);

totalVoxels = sum(prod(levelSizes, 2));
voxelsDone = 0;
highestIndex = 0;
clampedVoxels = 0;     % full-resolution voxels whose index was above targetMaxIndex
for level = 1:size(levelSizes, 1)
    levelSize = levelSizes(level, :);
    chunkShape = double(target.modelArrays{level}.info().chunkShape);   % [y x z]
    planesPerStrip = min(chunkShape(3), levelSize(3));
    % ~32 M voxels of the source per strip (the target block is up to 4x its bytes)
    rowsPerStrip = max(chunkShape(1), floor(2^25 / (levelSize(2) * planesPerStrip) / chunkShape(1)) * chunkShape(1));
    for firstPlane = 1:planesPerStrip:levelSize(3)
        planes = [firstPlane, min(firstPlane + planesPerStrip - 1, levelSize(3))];
        for firstRow = 1:rowsPerStrip:levelSize(1)
            if ~isempty(wb) && wb.CancelRequested
                localRemoveStore(target, targetPath);
                delete(wb);
                fprintf('Convert model: cancelled, the %s model is still in use\n', sourceTypeText);
                return;
            end
            rows = [firstRow, min(firstRow + rowsPerStrip - 1, levelSize(1))];
            block = source.readPackedLevel(level, rows, [1 levelSize(2)], planes);
            voxelsDone = voxelsDone + numel(block);
            if any(block(:))   % an untouched block stays at the fill value 0
                materials = bitand(block, source.materialMask);
                if ~keepMaterials; materials(:) = 0; end
                blockHighest = double(max(materials, [], 'all'));
                if blockHighest > targetMaxIndex
                    % a smaller target: everything above its top index becomes it
                    above = materials > targetMaxIndex;
                    if level == 1; clampedVoxels = clampedVoxels + nnz(above); end
                    materials(above) = targetMaxIndex;
                    blockHighest = targetMaxIndex;
                end
                highestIndex = max(highestIndex, blockHighest);
                % the index now fits the target type as it is; mask and selection
                % move to its top two bits
                remapped = cast(materials, targetClass) + ...
                    cast(bitget(block, source.maskBit), targetClass) * cast(target.maskValue, targetClass) + ...
                    cast(bitget(block, source.selectionBit), targetClass) * cast(target.selectionValue, targetClass);
                target.writePackedLevel(level, remapped, rows, [1 levelSize(2)], planes);
            end
            if ~isempty(wb); wb.Value = voxelsDone / totalVoxels; end
        end
    end
end

%% Carry the session state over and switch
target.matLevel = source.matLevel;
target.selectionTiles = source.selectionTiles;
target.selectionBBoxFull = source.selectionBBoxFull;
target.maxIndexUsed = highestIndex;       % taken over every level, so deferred ones count too
target.materialsCount = highestIndex;
if source.maxMaterials > 255 && modelType > 255 && keepMaterials
    target.objects3D = source.objects3D;  % instance to instance: the numbering means what it meant
else
    target.objects3D = true;              % a material is numbered through the volume
end
if modelType == 63
    % a material model lists its materials; index k becomes material k
    target.materialNames = arrayfun(@num2str, (1:max(highestIndex, 1))', 'UniformOutput', false);
else
    target.materialNames = {'1'; '2'};
end
colors = rand(65535, 3);
if keepMaterials && size(source.materialColors, 2) == 3
    % material (or object) k becomes object k, so it keeps the colour it is
    % drawn in now; the display takes the colour of index k from row
    % mod(k - 1, 65535) + 1, the same in both types
    keptRows = min(size(source.materialColors, 1), 65535);
    colors(1:keptRows, :) = source.materialColors(1:keptRows, :);
end
target.materialColors = colors;
target.filename = targetPath;
target.labelsVariable = source.labelsVariable;
target.maskFilename = source.maskFilename;
target.writeMaterialMetadata();
target.saveLevelMap();

source.closeStore();                      % persists its level map; the store stays on disk
dataset.labels = target;
dataset.instanceIndex = [];
dataset.selectedMaterial = 3;             % slot 3 is the first material or object
dataset.selectedAddToMaterial = 3;
% the entries hold snapshots of the old store's type, which the new one cannot take back
obj.Backup.clearContents();

if ~isempty(wb); delete(wb); end
if clampedVoxels > 0
    fprintf(2, 'Convert model: %d voxels of the full-resolution level had an index above %d and got index %d\n', ...
        clampedVoxels, targetMaxIndex, targetMaxIndex);
end
converted = true;
end

% =====================================================================
function localRemoveStore(labels, storePath)
% Close and delete a store this conversion created, with its level map
try labels.closeStore(); catch; end %#ok<CTCH>
if isfolder(storePath); rmdir(storePath, 's'); end
levelMapPath = core.MibBigDataLabels.levelMapPathFor(storePath);
if isfile(levelMapPath); delete(levelMapPath); end
end

% =====================================================================
function localMessage(obj, dlgOpt, message, details)
% Tell the user why the conversion did not happen. With no window to put a
% message box on - a batch protocol or a test - it goes to the command window,
% since inputUniversalDlg would otherwise open a modal dialog nobody can close.
parent = obj.getProgressBarParent();
if isempty(parent) || ~all(isvalid(parent))
    fprintf(2, 'Convert model: %s\n', message);
    fprintf(2, '    %s\n', details{:});
    return;
end
dlgOpt.MsgBoxOnly  = true;
dlgOpt.Icon        = 'puffin_warning';
dlgOpt.HeaderLines = 1;
utils.dlgs.inputUniversalDlg(parent, message, {''}, details, 'BigData mode', dlgOpt);
end
