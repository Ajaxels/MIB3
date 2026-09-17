function loadModel(obj, model, BatchOptIn)
% LOADMODEL - Load a segmentation model from file or import from a workspace array.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.loadModel(model, BatchOptIn)
%
% This is the top-level BatchOpt-compatible wrapper for model loading.
% It handles:
%
% FILE PATH  - model is empty; a file browser (GUI) or FilenameFilter
% template (batch) is used to locate the file(s); the
% factory-pattern loaders in +io are dispatched through
% MibDataset.loadModel.
%
% IMPORT PATH - model is a numeric array or a struct produced by
% mibImage.getData3D/4D or an export helper; metadata is
% unpacked from the struct before delegating to
% MibDataset.loadModel.
%
% Input Arguments:
%   - **model** - *(optional)* raw model array (numeric) or struct with fields:
%
%     - ``numeric`` - raw [H W D] or [H W D 1 T] label array
%     - ``struct`` - may contain: ``.modelMaterialNames``, ``.modelMaterialColors``,
%       ``.modelType``, ``.modelVariable``, ``.labelText``, ``.labelPosition``,
%       ``.labelValue``, and a field whose name matches ``.modelVariable``
%       (or any field holding the array)
%
%   - **BatchOptIn** - *(optional)* structure for batch processing mode; when NaN,
%     returns default options via the "SyncBatch" event
%
%     - ``.DirectoryName`` - [cell, ``{'Inherit from dataset filename'}``] target dir
%     - ``.FilenameFilter`` - [char, ``{'Labels_[F].model'}``] filename or wildcard filter;
%       ``[F]`` is replaced with the image base name (no extension).
%       Relative paths resolve against ``DirectoryName``; absolute paths bypass it.
%       Wildcards (``*``) are expanded via ``dir()``.
%     - ``.showWaitbar`` - [logical, ``{true}``] show progress dialog
%     - ``.id`` - [numeric, ``{obj.id}``] dataset index 1..9
%
%
% Output Arguments:
%   none
%
% Usage:
%   **Example 1** - interactive file browser
%
%   .. code-block:: matlab
%
%      obj.mibModel.loadModel();
%
%   **Example 2** - batch: load by name template
%
%   .. code-block:: matlab
%
%      BatchOpt.DirectoryName   = {'C:\data'};
%      BatchOpt.FilenameFilter  = 'Labels_[F].model';
%      obj.mibModel.loadModel([], BatchOpt);
%
%   **Example 3** - import from workspace array
%
%   .. code-block:: matlab
%
%      rawArray = obj.mibModel.I{obj.mibModel.id}.getData3D('labels');
%      obj.mibModel.loadModel(rawArray);
%

% Updates

if nargin < 2; model = []; end
if nargin < 3; BatchOptIn = struct; end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
id = obj.getActiveId();

% Build a sensible default directory and filename filter
imageFilename = obj.I{id}.image.filename;
if ~isempty(imageFilename) && ~strcmp(imageFilename, 'none.tif')
    defaultDir = fileparts(imageFilename);
else
    defaultDir = obj.currentDirectory;
end

BatchOpt.DirectoryName   = {'Inherit from dataset filename'};
BatchOpt.DirectoryName{2} = {'Inherit from dataset filename', obj.currentDirectory, 'Inherit from Directory/File loop'};
BatchOpt.FilenameFilter  = 'Labels_[F].model';
BatchOpt.Filenames       = {};   % cell array of full paths; bypasses filter/browser when non-empty
BatchOpt.ZarrGroupPath   = '';   % [OME-Zarr only] nested labels group inside the container
BatchOpt.showWaitbar     = true;
BatchOpt.id              = id;

BatchOpt.mibBatchSectionName = 'Ribbon -> Model';
BatchOpt.mibBatchActionName  = 'Load model';
BatchOpt.mibBatchTooltip.ZarrGroupPath  = sprintf('[OME-Zarr only] labels group inside the container, relative to the file/URL\ne.g. labels/mito; leave empty to search the container and ask');
BatchOpt.mibBatchTooltip.DirectoryName  = sprintf('Directory where the model file is located; "Inherit from dataset filename" uses the directory of the open image');
BatchOpt.mibBatchTooltip.FilenameFilter = sprintf(['Filename or wildcard filter for the model file; ' ...
    '[F] is replaced with the image base name (no extension). ' ...
    'Relative paths resolve against DirectoryName (e.g. "labels\\Labels_[F].model" or "..\\Labels_[F].model"); ' ...
    'absolute paths bypass DirectoryName']);
BatchOpt.mibBatchTooltip.showWaitbar    = sprintf('Show or not the progress bar during loading');

batchModeSwitch = 0;

ErrorDlgOpt = struct('optionalPrefix', 'Error in MibModel.loadModel', 'WindowHeight', 160);

%% Batch mode check
if nargin == 3 && ~isempty(BatchOptIn)
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)
            BatchOpt2 = rmfield(BatchOpt, {'id', 'Filenames'});
            eventdata = core.ToggleEventData(BatchOpt2);
            notify(obj, 'SyncBatch', eventdata);
        else
            ErrorDlgOpt.winTitle = 'BatchOpt Error';
            ErrorDlgOpt.err = 'A structure as the 3rd parameter is required!';
            eventdata = core.ToggleEventData(ErrorDlgOpt);
            notify(obj, 'ShowErrorDialog', eventdata);
        end
        return;
    else
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
        batchModeSwitch = isfield(BatchOptIn, 'mibBatchTooltip') || isfield(BatchOptIn, 'FilenameFilter');
        % updateBatchOptCombineFields_Shared copies only {1} from cell fields
        % that exist in the default - restore the full list when the caller
        % supplied multiple files (e.g. drag-and-drop of several model files).
        if isfield(BatchOptIn, 'Filenames') && numel(BatchOptIn.Filenames) > 1
            BatchOpt.Filenames = BatchOptIn.Filenames;
        end
    end
end

id = BatchOpt.id;

%% BigData mode - attach a disk-backed model store by reference
% The BigData model is a pyramidal zarr GROUP (a folder), not a single file, and
% must be attached by reference (openStore) rather than read fully into memory.
% Handled here, before the enableSelection guard, because BigData is browse-only
% until a model exists. Done inline (no core-class signature change).
if strcmp(obj.I{id}.datasetType, 'BigData') && isempty(model)
    if ~isempty(BatchOpt.Filenames)
        storePath = BatchOpt.Filenames{1};
    elseif batchModeSwitch
        [~, baseFilename] = fileparts(obj.I{id}.image.filename);
        storePath = strrep(BatchOpt.FilenameFilter, '[F]', baseFilename);
        if ~isfolder(storePath)
            storePath = fullfile(BatchOpt.DirectoryName{1}, storePath);
        end
    else
        selDir = uigetdir(defaultDir, 'Select the BigData model store (.zarr3 or .zarr2 folder)');
        if isequal(selDir, 0); return; end   % cancelled
        storePath = selDir;
    end

    % A remote store cannot be checked with isfolder; openStore below fails
    % with a clear message if the URL turns out not to hold a store.
    if isempty(storePath) || (~io.RemoteStore.isRemote(storePath) && ~isfolder(storePath))
        ErrorDlgOpt.winTitle = 'Model store not found';
        ErrorDlgOpt.err = sprintf('The BigData model store was not found:\n%s', storePath);
        notify(obj, 'ShowErrorDialog', core.ToggleEventData(ErrorDlgOpt));
        notify(obj, 'StopProtocol');
        return;
    end

    % Attaching a store is not instant and says nothing while it works: a
    % pyramid is opened level by level, and a remote one pays a round trip for
    % each (a 9-level store on S3 takes ~20 s). Indeterminate because the level
    % count is not known until the metadata that is being fetched has arrived.
    % Every exit below goes through onCleanup, including the error returns.
    bigDataProgress = [];
    if BatchOpt.showWaitbar
        progressParent = obj.getProgressBarParent();
        if ~isempty(progressParent) && isvalid(progressParent)
            try
                bigDataProgress = uiprogressdlg(progressParent, 'Indeterminate', 'on', ...
                    'Message', 'Opening the model store...', 'Title', 'Load model');
                drawnow limitrate;
            catch
                bigDataProgress = [];   % a bar is never the work itself
            end
        end
    end
    cleanupBigDataProgress = onCleanup(@() closeProgressDialog(bigDataProgress));

    ds = obj.I{id};
    bigMeta = core.MibImage.initializeImgInfo('pixSize', ds.image.pixSize, ...
        'Height', ds.image.height, 'Width', ds.image.width, ...
        'Depth', ds.image.depth, 'Time', ds.image.time, 'Colors', 1);
    % Which class owns the store depends on who WROTE it, not on its format:
    % MIB's editable pyramid (core.MibBigDataLabels) reads and writes zarr v2
    % and v3 alike, but only for stores it created itself - those hold packed
    % bytes in [y,x,z] and carry the mibModelStore marker. A FOREIGN v2 label
    % store holds another tool's plain label indices in its own axis order, so
    % it gets the read-only overlay (core.MibBigDataLabelsZarr2) instead.
    % Both classes share the same public surface, so everything after this
    % branch is unchanged. The format probe is delegated to the shared helper,
    % which handles a local folder and a URL alike.
    isZarrV2Store = strcmp( ...
        io.ExtensionRegistryLoad.detectZarrFormatExtension(storePath), 'zarr2');
    if isZarrV2Store && ~core.MibBigDataLabels.isMibModelStore(storePath)
        newLabels = core.MibBigDataLabelsZarr2([], bigMeta);
    else
        newLabels = core.MibBigDataLabels([], bigMeta);
    end
    % Both classes above assume the store's finest level IS the image's full
    % resolution, because both number their levels from the store's own level 0.
    % A pyramid published from a coarse level down breaks that assumption rather
    % than failing on it: jrc_mus-kidney's nuc starts at 128 nm over an 8 nm EM,
    % so its own level 0 is the EM's s4 and calling it scale 1 would place every
    % label at one-sixteenth of its true size. Such a store gets the read-only
    % overlay (core.MibBigDataLabelsIndex), which registers against the image's
    % scale space instead.
    %
    % The mismatch is DISCOVERED by opening rather than predicted from metadata,
    % so the wasted level walk is paid only on the path that then needs the
    % overlay - and never on the common case where the store does match.
    mismatchReason = '';
    try
        newLabels.openStore(storePath);
        if newLabels.height ~= ds.image.height || newLabels.width ~= ds.image.width || ...
                newLabels.depth ~= ds.image.depth
            mismatchReason = sprintf(['Model size [%d x %d x %d] does not match the image ' ...
                '[%d x %d x %d].'], ...
                newLabels.height, newLabels.width, newLabels.depth, ...
                ds.image.height, ds.image.width, ds.image.depth);
        end
    catch ME
        % Not necessarily a dead end: a FOREIGN v3 label store lands on
        % core.MibBigDataLabels above, which expects MIB's own packed layout and
        % throws, while the overlay reads either format.
        mismatchReason = sprintf('"%s" is not a BigData model store for this dataset:\n%s', ...
            storePath, ME.message);
    end

    if ~isempty(mismatchReason)
        [overlayLabels, registrationReason] = attachLabelOverlay(ds, bigMeta, storePath);
        if isempty(overlayLabels)
            closeProgressDialog(bigDataProgress);   % modal, and would sit in front of the message
            ErrorDlgOpt.winTitle = 'Model does not match the image';
            ErrorDlgOpt.err = sprintf('%s\n\n%s', mismatchReason, registrationReason);
            notify(obj, 'ShowErrorDialog', core.ToggleEventData(ErrorDlgOpt));
            notify(obj, 'StopProtocol');
            return;
        end
        newLabels = overlayLabels;
    end
    isReadOnlyOverlay = isa(newLabels, 'core.MibBigDataLabelsIndex');

    ds.labels = newLabels;
    % openStore restores material names/colours from the store when present;
    % fall back to the default palette (cycled to cover all 63 packed material
    % slots) when none were saved, and to random colors when the preference
    % palette itself is empty - an empty Colormap crashes labeloverlay in
    % getRGBimage as soon as the model is displayed, so this must never stay empty.
    if isempty(ds.labels.materialColors)
        palette = obj.preferences.Colors.ModelMaterialColors;
        nMat    = ds.labels.maxMaterials; % 63 for the packed BigData model scheme
        if isempty(palette)
            ds.labels.materialColors = rand(nMat, 3);
        else
            nPalette = size(palette, 1);
            ds.labels.materialColors = palette(mod(0:nMat-1, nPalette) + 1, :);
        end
    end
    % Same idea for names: an externally-created store may carry no material
    % metadata at all (checked by openStore: mibMaterials attr, else OME-NGFF
    % image-label). Scanning the whole disk-backed volume to find which of the
    % up-to-63 packed indices actually occur is too expensive here, so - same
    % as the colors fallback above - populate all 63 numbered slots; this
    % mirrors core.MibDataset.loadModel.m's Standard-mode auto-naming and lets
    % the Segmentation panel show/select any material index present in the data.
    % BigData models are always the 63-material packed scheme, so unlike the
    % >255-material case elsewhere, plain numeric names carry no special
    % meaning here - use "matN" throughout.
    if isempty(ds.labels.materialNames)
        ds.labels.materialNames = arrayfun(@(x) sprintf('mat%d', x), (1:ds.labels.maxMaterials)', 'UniformOutput', false);
    end
    % A read-only overlay counted its own objects at open time (from the coarsest
    % level, one request). Its materialNames holds the TWO index-carrying slots the
    % >255-material convention uses, so numel() here would overwrite a real count
    % with 2.
    if ~isReadOnlyOverlay
        ds.labels.materialsCount = numel(ds.labels.materialNames);
    end
    ds.labels.labelsVariable  = 'mibModel';
    ds.labels.filename        = storePath;
    % MibLabels63's constructor hardcodes maskFilename to 'Mask_none.mask' - re-derive
    % it from the dataset's real image filename, same as core.MibDataset.loadModel.m
    % does for Standard datasets, so "Save mask" defaults to the dataset's own name.
    ds.labels.maskFilename    = ds.image.maskFilename;
    ds.modelExist             = true;
    if isReadOnlyOverlay
        % ``enableSelection`` is what every segmentation tool tests before
        % touching a layer (the rule in CLAUDE.md) and what getRGBimage:248 tests
        % before reading the selection, so leaving it false keeps the dataset
        % browse-only in one place instead of a class check per tool. The model
        % still DISPLAYS: the overlay at getRGBimage:216 needs only modelExist
        % and showModel.
        ds.enableSelection    = false;
    else
        ds.enableSelection    = true;   % browse-only BigData becomes segmentable
    end
    ds.selectedMaterial       = 2;
    ds.selectedAddToMaterial  = 2;
    ds.lastSegmSelection      = [2 1];

    obj.showModel = true;
    notify(obj, 'UpdateGuiWidgets');
    notify(obj, 'ShowImage');

    if batchModeSwitch
        BatchOpt.Filenames = {storePath};
        notify(obj, 'SyncBatch', core.ToggleEventData(BatchOpt));
    end
    return;
end

%% Virtual mode guard
if strcmp(obj.I{id}.datasetType, 'Virtual')
    dlgOpt.MsgBoxOnly   = true;
    dlgOpt.Icon         = 'puffin_warning';
    header       = sprintf('Models are not available in the virtual stacking mode!\nPlease switch to the memory-resident mode first.');
    dlgOpt.WindowHeight = 170;
    dlgOpt.HeaderLines  = 2;
    dlgOpt.mibPath      = obj.mibPath;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), header, {}, {}, 'Not implemented', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

% Check that selection/segmentation layers are enabled
if obj.I{id}.enableSelection == 0
    dlgOpt.MsgBoxOnly   = true;
    header       = 'The segmentation layers are switched off!';
    dlgOpt.HeaderLines  = 1;
    bodyText = sprintf(['Please make sure that the "Enable selection" option in the Preferences dialog ' ...
        '(Ribbon->Home->Preferences) is set to "yes" and try again.']);
    dlgOpt.WindowHeight = 190;
    dlgOpt.mibPath      = obj.mibPath;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), header, {bodyText}, {bodyText}, 'Segmentation disabled', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

%% Prepare common delegate options
dsOpts = struct();
dsOpts.batchModeSwitch = batchModeSwitch;
dsOpts.showWaitbar     = BatchOpt.showWaitbar;
% [OME-Zarr] point the setup loader at a nested labels group, skipping the
% container search; accepts a path relative to the container or an absolute one.
if isfield(BatchOpt, 'ZarrGroupPath') && ~isempty(BatchOpt.ZarrGroupPath)
    dsOpts.ZarrGroupPath = BatchOpt.ZarrGroupPath;
end
dsOpts.preferences     = obj.preferences;
dsOpts.mibPath         = obj.mibPath;
dsOpts.ParentFigure    = obj.mibGUI;

%% IMPORT PATH - model array or struct provided
if ~isempty(model)
    if isstruct(model)
        % Unpack struct exported from workspace
        dsOpts.modelMaterialNames  = [];
        dsOpts.modelMaterialColors = [];
        dsOpts.modelType           = [];
        dsOpts.labelText           = [];
        dsOpts.labelPosition       = [];
        dsOpts.labelValue          = [];

        % Find the variable that holds the raw array
        labVar = '';
        if isfield(model, 'modelVariable') && ~isempty(model.modelVariable) ...
                && isfield(model, model.modelVariable)
            labVar = model.modelVariable;
        else
            skipFields = {'modelMaterialNames', 'modelMaterialColors', 'modelType', ...
                'BoundingBox', 'labelText', 'labelPosition', 'labelValue', 'modelVariable'};
            fnames = fieldnames(model);
            for k = 1:numel(fnames)
                if ~ismember(fnames{k}, skipFields)
                    labVar = fnames{k};
                    break;
                end
            end
        end

        if ~isempty(labVar) && isfield(model, labVar)
            dsOpts.model = model.(labVar);
        else
            dsOpts.model = model;  % treat struct itself as array (edge case)
        end

        if isfield(model, 'modelMaterialNames')
            dsOpts.modelMaterialNames = model.modelMaterialNames;
        end
        if isfield(model, 'modelMaterialColors')
            dsOpts.modelMaterialColors = model.modelMaterialColors;
        end
        if isfield(model, 'modelType')
            dsOpts.modelType = model.modelType;
        end
        if isfield(model, 'labelText')
            dsOpts.labelText = model.labelText;
        end
        if isfield(model, 'labelPosition')
            dsOpts.labelPosition = model.labelPosition;
        end
        if isfield(model, 'labelValue')
            dsOpts.labelValue = model.labelValue;
        end
    else
        % Numeric array
        dsOpts.model = model;
    end

    result = obj.I{id}.loadModel([], dsOpts);
    if isempty(result); return; end

    obj.showModel = true;
    notify(obj, 'UpdateGuiWidgets');
    notify(obj, 'ShowImage');

    if batchModeSwitch
        if ~isempty(BatchOpt.Filenames)
            BatchOpt.Filenames = BatchOpt.Filenames(1);
        end
        eventdata = core.ToggleEventData(BatchOpt);
        notify(obj, 'SyncBatch', eventdata);
    end
    return;
end

%% FILE PATH - resolve directory and filenames

% Expand DirectoryName
if strcmp(BatchOpt.DirectoryName{1}, 'Inherit from dataset filename')
    BatchOpt.DirectoryName{1} = defaultDir;
end
if strcmp(BatchOpt.DirectoryName{1}, 'Inherit from Directory/File loop')
    % do nothing - already a real path when running in loop
end

if ~isempty(BatchOpt.Filenames)
    % ---- DIRECT FILENAMES (e.g. drag-and-drop): bypass filter / browser ----
    filenames = BatchOpt.Filenames;
    if ischar(filenames); filenames = {filenames}; end
elseif batchModeSwitch
    % ---- BATCH MODE: expand [F] template and glob ----
    [~, baseFilename] = fileparts(obj.I{id}.image.filename);
    filterExpanded = strrep(BatchOpt.FilenameFilter, '[F]', baseFilename);

    % Check whether filterExpanded is a full path already
    if isfile(filterExpanded)
        filenames = {filterExpanded};
    else
        d = dir(fullfile(BatchOpt.DirectoryName{1}, filterExpanded));
        d = d(~[d.isdir]);
        if isempty(d)
            ErrorDlgOpt.winTitle = 'File not found';
            ErrorDlgOpt.err = sprintf('No model file matching "%s" was found in:\n%s', ...
                filterExpanded, BatchOpt.DirectoryName{1});
            eventdata = core.ToggleEventData(ErrorDlgOpt);
            notify(obj, 'ShowErrorDialog', eventdata);
            notify(obj, 'StopProtocol');
            return;
        end
        filenames = arrayfun(@(x) fullfile(x.folder, x.name), d, ...
            'UniformOutput', false);
    end
else
    % ---- GUI MODE: file browser ----
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

    [file, path] = utils.dlgs.mibUiGetFile(fileFilter, ...
        'Select model file(s)', BatchOpt.DirectoryName{1}, 'on');

    if isequal(file, 0); return; end  % user cancelled

    if ischar(file); file = {file}; end
    filenames = cellfun(@(f) fullfile(path, f), file, 'UniformOutput', false);
end

%% Resolve loader and delegate to MibDataset.loadModel

% Determine loader from first file
[~, ~, ext] = fileparts(filenames{1});
ext = lower(strrep(ext, '.', ''));

% A URL pointing straight at a label group ('.../labels/mito') has no filename
% extension at all, so probe the store itself; 'zarr2'/'zarr3' are already in
% the Model.Default set. Skipped when the URL carries a known extension, so an
% ordinary remote image keeps its route without a network round trip.
if io.RemoteStore.isRemote(filenames{1}) && (isempty(ext) || strcmp(ext, 'zarr'))
    probedExtension = io.ExtensionRegistryLoad.probeRemoteZarr(filenames{1});
    if ~isempty(probedExtension); ext = probedExtension; end
end

% Check extension is supported in Model.Default
allowedExt = obj.extensionRegistryLoad.getAllowedExtensions('Model', 'Default', false);
% getAllowedExtensions returns with dot
allowedExtNoDot = strrep(allowedExt, '.', '');
if ~ismember(ext, allowedExtNoDot)
    ErrorDlgOpt.winTitle = 'Unsupported format';
    ErrorDlgOpt.err = sprintf('The extension ".%s" is not supported for model loading.', ext);
    eventdata = core.ToggleEventData(ErrorDlgOpt);
    notify(obj, 'ShowErrorDialog', eventdata);
    notify(obj, 'StopProtocol');
    return;
end

loaderInfo = obj.extensionRegistryLoad.resolveLoader(filenames{1}, 'Model', 'Default');
if ischar(loaderInfo)
    % resolveLoader returned an error string
    ErrorDlgOpt.winTitle = 'Loader error';
    ErrorDlgOpt.err = loaderInfo;
    eventdata = core.ToggleEventData(ErrorDlgOpt);
    notify(obj, 'ShowErrorDialog', eventdata);
    notify(obj, 'StopProtocol');
    return;
end

dsOpts.loaderInfo = loaderInfo;

result = obj.I{id}.loadModel(filenames, dsOpts);
if isempty(result); return; end

obj.showModel = true;
notify(obj, 'UpdateGuiWidgets');
notify(obj, 'ShowImage');

if batchModeSwitch
    BatchOpt.Filenames = filenames(1);   % report the resolved file back to BatchProcessing
    eventdata = core.ToggleEventData(BatchOpt);
    notify(obj, 'SyncBatch', eventdata);
end
end

% =========================================================================
function [overlayLabels, reason] = attachLabelOverlay(ds, bigMeta, storePath)
% ATTACHLABELOVERLAY - Try to serve a non-matching label pyramid as a view-only overlay.
%
% Hands the store to ``core.MibBigDataLabelsIndex``, described against the open
% image by that class's own ``imageReference`` - shared with
% ``controllers.SelectFromUrl.resolveLabelRoute``, so the route the info panel
% promises before Open and the one taken here cannot diverge. Returns ``[]`` plus
% the reason when the pyramid cannot be placed, which the caller reports beside
% whatever went wrong on the direct route.

overlayLabels = [];

imageReference = core.MibBigDataLabelsIndex.imageReference(ds.image);
if ~imageReference.ok
    reason = imageReference.reason;
    return;
end
reason = '';

candidate = core.MibBigDataLabelsIndex([], bigMeta);
try
    candidate.openStore(storePath, imageReference);
catch ME
    reason = ME.message;
    return;
end
overlayLabels = candidate;
end

% =========================================================================
function closeProgressDialog(progressDialog)
% CLOSEPROGRESSDIALOG - Close the BigData progress bar if one is up.
%
% Called explicitly before every error dialog in the BigData branch - the bar is
% modal and would otherwise sit in front of the message explaining what went
% wrong - and again from onCleanup on the way out, so it is written to be safe
% the second time.
if ~isempty(progressDialog) && isvalid(progressDialog)
    delete(progressDialog);
end
end
