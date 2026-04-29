function loadModel(obj, model, BatchOptIn)
% LOADMODEL - Load a segmentation model from file or import from a workspace array.
%
% Syntax:
%   function loadModel(obj, model, BatchOptIn)
%
% This is the top-level BatchOpt-compatible wrapper for model loading.
% It handles:
%
% FILE PATH  — model is empty; a file browser (GUI) or FilenameFilter
% template (batch) is used to locate the file(s); the
% factory-pattern loaders in +io are dispatched through
% MibDataset.loadModel.
%
% IMPORT PATH — model is a numeric array or a struct produced by
% mibImage.getData3D/4D or an export helper; metadata is
% unpacked from the struct before delegating to
% MibDataset.loadModel.
%
% Input Arguments:
%   - **model** — *(optional)* raw model array (numeric) or struct with fields:
%
%     - ``numeric`` — raw [H W D] or [H W D 1 T] label array
%     - ``struct`` — may contain: ``.modelMaterialNames``, ``.modelMaterialColors``,
%       ``.modelType``, ``.modelVariable``, ``.labelText``, ``.labelPosition``,
%       ``.labelValue``, and a field whose name matches ``.modelVariable``
%       (or any field holding the array)
%
%   - **BatchOptIn** — *(optional)* structure for batch processing mode; when NaN,
%     returns default options via the "SyncBatch" event
%
%     - ``.DirectoryName`` — [cell, ``{'Inherit from dataset filename'}``] target dir
%     - ``.FilenameFilter`` — [char, ``{'Labels_[F].model'}``] filename filter;
%       ``[F]`` is expanded to the base name of the currently open image
%     - ``.showWaitbar`` — [logical, ``{true}``] show progress dialog
%     - ``.id`` — [numeric, ``{obj.id}``] dataset index 1..9
%
%
% Output Arguments:
%   none
%
% Usage:
%   **Example 1** — interactive file browser
%
%   .. code-block:: matlab
%
%      obj.mibModel.loadModel();
%
%   **Example 2** — batch: load by name template
%
%   .. code-block:: matlab
%
%      BatchOpt.DirectoryName   = {'C:\data'};
%      BatchOpt.FilenameFilter  = 'Labels_[F].model';
%      obj.mibModel.loadModel([], BatchOpt);
%
%   **Example 3** — import from workspace array
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
BatchOpt.showWaitbar     = true;
BatchOpt.id              = id;

BatchOpt.mibBatchSectionName = 'Ribbon -> Model';
BatchOpt.mibBatchActionName  = 'Load model';
BatchOpt.mibBatchTooltip.DirectoryName  = sprintf('Directory where the model file is located; "Inherit from dataset filename" uses the directory of the open image');
BatchOpt.mibBatchTooltip.FilenameFilter = sprintf('Filename or filter for the model file; [F] is replaced with the base name of the open image');
BatchOpt.mibBatchTooltip.showWaitbar    = sprintf('Show or not the progress bar during loading');

batchModeSwitch = 0;

ErrorDlgOpt = struct('optionalPrefix', 'Error in MibModel.loadModel', 'WindowHeight', 160);

%% Batch mode check
if nargin == 3 && ~isempty(BatchOptIn)
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)
            BatchOpt2 = rmfield(BatchOpt, 'id');
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
    end
end

id = BatchOpt.id;

%% Virtual mode guard
if strcmp(obj.I{id}.datasetType, 'Virtual')
    dlgOpt.MsgBoxOnly   = true;
    dlgOpt.Icon         = 'puffin_warning';
    header       = sprintf('Models are not available in the virtual stacking mode!\nPlease switch to the memory-resident mode first.');
    dlgOpt.WindowHeight = 170;
    dlgOpt.HeaderLines  = 2;
    dlgOpt.mibPath      = obj.mibPath;
    utils.dlgs.inputUniversalDlg(obj.mibGUI, header, {}, {}, 'Not implemented', dlgOpt);
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
    utils.dlgs.inputUniversalDlg(obj.mibGUI, header, {bodyText}, {bodyText}, 'Segmentation disabled', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

%% Prepare common delegate options
dsOpts = struct();
dsOpts.batchModeSwitch = batchModeSwitch;
dsOpts.showWaitbar     = BatchOpt.showWaitbar;
dsOpts.preferences     = obj.preferences;
dsOpts.mibPath         = obj.mibPath;
dsOpts.ParentFigure    = obj.mibGUI;

%% IMPORT PATH — model array or struct provided
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
        eventdata = core.ToggleEventData(BatchOpt);
        notify(obj, 'SyncBatch', eventdata);
    end
    return;
end

%% FILE PATH — resolve directory and filenames

% Expand DirectoryName
if strcmp(BatchOpt.DirectoryName{1}, 'Inherit from dataset filename')
    BatchOpt.DirectoryName{1} = defaultDir;
end
if strcmp(BatchOpt.DirectoryName{1}, 'Inherit from Directory/File loop')
    % do nothing — already a real path when running in loop
end

if batchModeSwitch
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
        filenames = arrayfun(@(x) fullfile(BatchOpt.DirectoryName{1}, x.name), d, ...
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
    eventdata = core.ToggleEventData(BatchOpt);
    notify(obj, 'SyncBatch', eventdata);
end
end
