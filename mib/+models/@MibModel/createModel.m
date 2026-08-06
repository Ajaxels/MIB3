function createModel(obj, ModelType, ModelMaterialNames, BatchOptIn)
% CREATEMODEL - Create a new model - wrapper around core.MibDataset.createModel.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.createModel(ModelType, ModelMaterialNames, BatchOptIn)
%
% Input Arguments:
%   - **ModelType** - *(optional)*, can be empty: []; a number with the model type:
%   - 63 - 63 material model
%   - 255 - 255 material model
%   - 65535 - 65535 material model
%   - 4294967295 - 4294967295 material model
%   - **ModelMaterialNames** - *(optional)* can be empty: []; a cell array with
%     names of materials; not used for ModelType > 255
%   - **BatchOptIn** - a structure for batch processing mode; when NaN, returns a
%     structure with default options via "SyncBatch" event
%   - .ModelType - cell string, {'63', '255', '65535', '4294967295'}
%   - .ModelMaterialNames - string with semicolon-separated material names
%   - .showWaitbar - logical, show or not the waitbar
%   - .id *(optional)*, dataset index from 1 to 9, default = obj.id
%
% Output Arguments:
%
% Usage:
%   **Example 1** - create a new model
%
%   .. code-block:: matlab
%
%      obj.mibModel.createModel();
%

% Updates
% Ported from MIB2 mibModel.createModel

if nargin < 3; ModelMaterialNames = []; end
if nargin < 2; ModelType = []; end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
if ~isempty(ModelType)
    BatchOpt.ModelType = {num2str(ModelType)};
else
    BatchOpt.ModelType = {'63'};
end
BatchOpt.ModelType{2} = {'63', '255', '65535', '4294967295'};
if ~isempty(ModelMaterialNames)
    BatchOpt.ModelMaterialNames = sprintf('%s;', ModelMaterialNames{:});
    BatchOpt.ModelMaterialNames(end) = [];
else
    BatchOpt.ModelMaterialNames = '';
end
BatchOpt.ModelStorePath = '';   % [BigData only] disk path of the .zarr3 model store; empty -> asked interactively
BatchOpt.showWaitbar = true;
BatchOpt.id = obj.getActiveId();

BatchOpt.mibBatchSectionName = 'Ribbon -> Model';
BatchOpt.mibBatchActionName = 'New model';
BatchOpt.mibBatchTooltip.ModelType = ...
    'Specify type of the new model; the model type indicates the maximum number of materials. More materials require more memory and are slower to work with';
BatchOpt.mibBatchTooltip.ModelMaterialNames = sprintf( ...
    '[For 63 and 255 only]\nOptionally, specify names for materials as a semicolon-separated list: "mat1; mat2; mat3"');
BatchOpt.mibBatchTooltip.ModelStorePath = sprintf( ...
    '[BigData only]\nDisk location (.zarr3) for the on-disk model store; if empty you are asked for it');
BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';

%% Batch mode check actions
if nargin == 4  % batch mode
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)
            BatchOpt = rmfield(BatchOpt, 'id');
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj, 'SyncBatch', eventdata);
        else
            ErrorDlgOpt.winTitle = 'BatchOpt Error';
            ErrorDlgOpt.optionalPrefix = 'Error in MibModel.createModel';
            ErrorDlgOpt.err = 'A structure as the 4th parameter is required!';
            ErrorDlgOpt.WindowHeight = 150;
            eventdata = core.ToggleEventData(ErrorDlgOpt);
            notify(obj, 'ShowErrorDialog', eventdata);
        end
        return;
    else
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end
end

%% Initial checks
% BigData: only the packed 63-material disk-backed model is supported; force
% the type and skip the type-selection dialog below.
isBigData = strcmp(obj.I{BatchOpt.id}.datasetType, 'BigData');
if isBigData
    BatchOpt.ModelType{1} = '63';
    ModelType = 63;
end

% Check for virtual stacking mode
if strcmp(obj.I{BatchOpt.id}.datasetType, 'Virtual')
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_warning';
    header = sprintf('Models are not yet available in the virtual stacking mode!\nPlease switch to the memory-resident mode and try again');
    dlgOpt.WindowHeight = 170;
    dlgOpt.HeaderLines = 3;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), header, {}, {}, 'Not implemented', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

% Check that selection/segmentation layers are enabled.
% BigData is intentionally browse-only (enableSelection==0) until a model is
% created - creating the model is what enables segmentation - so skip this gate.
if obj.I{BatchOpt.id}.enableSelection == 0 && ~isBigData
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_warning';
    header = 'The models are switched off!';
    dlgOpt.HeaderLines = 1;
    text = sprintf(['Please make sure that the "Enable selection" option in the Preferences dialog ' ...
        '(Ribbon->Home->Preferences) is set to "yes" and try again...']);
    dlgOpt.WindowHeight = 190;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), header, {text}, {text}, 'Models are disabled', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

% Warn if an existing model will be overwritten
if obj.I{BatchOpt.id}.modelExist && nargin < 4
    button = utils.dlgs.inputQuestDlg(obj.getProgressBarParent(), ...
        sprintf('You are about to start a new model,\nthe existing model will be deleted!'), ...
        'Start new model', 'Continue', 'Cancel', 'Cancel');
    if strcmp(button, 'Cancel'); return; end
end

% Show model-type selection dialog when the type was not provided
% (skipped for BigData, which forced the type to 63 above)
if isempty(ModelType) && nargin < 4 && ~isBigData
    dlg = utils.dlgs.selectModelTypeDlg(obj.getProgressBarParent(), obj.mibPath);
    drawnow;
    selectedType = dlg.run();
    if isempty(selectedType); return; end
    BatchOpt.ModelType{1} = num2str(selectedType);
end

% BigData: ask where to keep the on-disk model store (unless given via batch).
% The model is persisted on disk, so a deliberate location is required rather
% than a hidden temp folder.
if isBigData && isempty(BatchOpt.ModelStorePath) && nargin < 4
    [imgPath, imgStem] = fileparts(obj.I{BatchOpt.id}.image.filename);
    if isempty(imgPath) || strcmp(obj.I{BatchOpt.id}.image.filename, 'none.tif'); imgPath = pwd; end
    if isempty(imgStem); imgStem = 'dataset'; end
    [storeFile, storePathDir] = uiputfile( ...
        {'*.zarr3', 'OME-Zarr v3 model store (*.zarr3)'}, ...
        'Select location for the BigData model store', ...
        fullfile(imgPath, ['Labels_' imgStem '.zarr3']));
    if isequal(storeFile, 0)   % user cancelled
        notify(obj, 'StopProtocol');
        return;
    end
    BatchOpt.ModelStorePath = fullfile(storePathDir, storeFile);
end

%%
if BatchOpt.showWaitbar
    wbMessage = 'Creating model, please wait...';
    if isBigData
        wbMessage = sprintf('Creating the on-disk OME-Zarr v3 model store\n(%d pyramid level(s)), please wait...', ...
            max(1, numel(obj.I{BatchOpt.id}.image.pyramid.levelNames)));
    end
    wb = uiprogressdlg(obj.getProgressBarParent(), 'Value', 0, ...
        'Message', wbMessage, ...
        'Title', 'Create model', 'Indeterminate', 'on');
    drawnow;   % force the dialog to render before the synchronous store creation
end

if isBigData
    % BigData: build the disk-backed packed (63-material) model here so the
    % chosen store path is honored WITHOUT changing core.MibDataset.createModel's
    % signature - a parameter-count change cannot hot-reload while the running
    % app holds dataset instances (MATLAB only hot-swaps method bodies).
    ds = obj.I{BatchOpt.id};
    bigMeta = core.MibImage.initializeImgInfo( ...
        'pixSize', ds.image.pixSize, ...
        'Height',  ds.image.height, ...
        'Width',   ds.image.width,  ...
        'Depth',   ds.image.depth,  ...
        'Time',    ds.image.time,   ...
        'Colors',  1);
    ds.labels = core.MibBigDataLabels([], bigMeta);
    ds.labels.createStore([ds.image.height, ds.image.width, ds.image.depth], ...
        BatchOpt.ModelStorePath, ds.image.pyramid);   % mirror the image pyramid levels
    ds.labels.materialColors  = obj.preferences.Colors.ModelMaterialColors;
    ds.labels.labelsVariable  = 'mibModel';
    ds.labels.filename        = '';
    % MibLabels63's constructor hardcodes maskFilename to 'Mask_none.mask' - re-derive
    % it from the dataset's real image filename, same as core.MibDataset.loadModel.m
    % does for Standard datasets, so "Save mask" defaults to the dataset's own name.
    ds.labels.maskFilename    = ds.image.maskFilename;
    bigNames = BatchOpt.ModelMaterialNames;
    if ~isempty(bigNames)
        splitCells = regexp(bigNames, '([^ ;,]*)', 'tokens');
        bigNames = cat(2, splitCells{:});
        bigNames = bigNames(~cellfun(@isempty, bigNames));
        ds.labels.materialNames  = bigNames(:);
        ds.labels.materialsCount = numel(bigNames);
    else
        ds.labels.materialNames  = {};
        ds.labels.materialsCount = 0;
    end
    ds.modelExist          = true;
    ds.enableSelection     = true;   % browse-only BigData becomes segmentable
    ds.selectedMaterial    = 2;
    ds.selectedAddToMaterial = 2;
    ds.lastSegmSelection   = [2 1];
    ds.annotations.clearContents();
    ds.labels.writeMaterialMetadata();   % persist names/colours into the store

    % One-time explainer: the BigData model persists live to disk; Save finalizes levels.
    % Honour a session-scoped "Do not show again" flag (see generateSessionSettings).
    if nargin < 4   % interactive only
        if ~isfield(obj.preferences, 'DoNotShowDialogs') || ~isstruct(obj.preferences.DoNotShowDialogs)
            obj.preferences.DoNotShowDialogs = struct();
        end
        if ~isfield(obj.preferences.DoNotShowDialogs, 'BigDataModelCreated') || ...
                ~obj.preferences.DoNotShowDialogs.BigDataModelCreated
            htmlBody = sprintf(['<html><p style="font-size:10pt">The model is written to ' ...
                'disk <b>live</b> - every edit goes straight to its <b>.zarr3</b> store. Each edit is ' ...
                'saved immediately at the magnification you are working at, plus the coarser overview ' ...
                'levels; higher-resolution zoom levels are reconstructed on the fly when you zoom in ' ...
                '(and cached), so editing stays fast at any zoom.<br><br>' ...
                'Press <b>Save model</b> to <b>finalize</b> the store - this materializes every ' ...
                'resolution level so the on-disk model is complete for export and external readers. ' ...
                'Your work is durable without it (edits persist at their drawn level), but Save makes ' ...
                'all zoom levels consistent on disk.<br><br>' ...
                'Model store:<br><i>%s</i><br><br>Use <b>Load model</b> to reopen this store in a ' ...
                'later session and continue segmenting.</p></html>'], char(ds.labels.modelStorePath));
            dlgOpt = struct();
            dlgOpt.MsgBoxOnly      = true;
            dlgOpt.Icon            = 'puffin_info';
            dlgOpt.HeaderLines     = 1;
            dlgOpt.WindowHeight    = 260;
            dlgOpt.WindowWidth    = 650;
            dlgOpt.DoNotShowAgain  = true;
            dlgOpt.mibPath         = obj.mibPath;
            [~, ~, obj.preferences.DoNotShowDialogs.BigDataModelCreated] = ...
                utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), ...
                'BigData model: saved live, finalized with Save', {htmlBody}, {htmlBody}, ...
                'BigData model', dlgOpt);
        end
    end
else
    switch BatchOpt.ModelType{1}
        case {'63', '255'}
            ModelMaterialNames = BatchOpt.ModelMaterialNames;
            if ~isempty(ModelMaterialNames)
                splitCells = regexp(ModelMaterialNames, '([^ ;,]*)', 'tokens');
                ModelMaterialNames = cat(2, splitCells{:});
            end
            obj.I{BatchOpt.id}.createModel(str2double(BatchOpt.ModelType{1}), ModelMaterialNames);
            % Update material colors from preferences
            obj.I{BatchOpt.id}.labels.materialColors = obj.preferences.Colors.ModelMaterialColors;
        case '65535'
            obj.I{BatchOpt.id}.createModel(65535);
        case '4294967295'
            obj.I{BatchOpt.id}.createModel(4294967295);
    end
end

% Make the model layer visible
obj.showModel = true;

% update checkboxes
eventdata = core.ToggleEventData({'ribbonModel', 'checkboxes'});
notify(obj, 'UpdateGuiWidgets', eventdata);
% show image
notify(obj, 'ShowImage');

% Notify batch mode
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);

if BatchOpt.showWaitbar; delete(wb); end
end
