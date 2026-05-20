function loadMask(obj, mask, BatchOptIn)
% LOADMASK - Load a binary mask from file or import from a workspace array.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.loadMask(mask, BatchOptIn)
%
% This is the top-level BatchOpt-compatible wrapper for mask loading.
% It handles:
%
% FILE PATH  — mask is empty; a file browser (GUI) or FilenameFilter
%   template (batch) is used to locate the file(s); loading is
%   delegated to MibDataset.loadMask.
%
% IMPORT PATH — mask is a numeric or logical array; the array is
%   imported directly via MibDataset.loadMask.
%
% Input Arguments:
%   - **mask** — *(optional)* raw mask array [H W D] or [H W D 1 T]
%   - **BatchOptIn** — *(optional)* structure for batch processing mode; when NaN,
%     returns default options via the "SyncBatch" event
%
%     - ``.DirectoryName`` — [cell, ``{'Inherit from dataset filename'}``] target dir
%     - ``.FilenameFilter`` — [char, ``'Mask_[F].mask'``] filename or filter;
%       ``[F]`` is expanded to the base name of the currently open image
%     - ``.showWaitbar`` — [logical, ``true``] show progress dialog
%     - ``.id`` — [numeric] dataset index 1..9, default = currently active
%
% Output Arguments:
%   none
%
% Usage:
%   **Example 1** — interactive file browser
%
%   .. code-block:: matlab
%
%      obj.mibModel.loadMask();
%
%   **Example 2** — batch: load by name template
%
%   .. code-block:: matlab
%
%      BatchOpt.DirectoryName  = {'C:\data'};
%      BatchOpt.FilenameFilter = 'Mask_[F].mask';
%      obj.mibModel.loadMask([], BatchOpt);
%
%   **Example 3** — import from workspace array
%
%   .. code-block:: matlab
%
%      rawMask = uint8(someLogicalVolume);
%      obj.mibModel.loadMask(rawMask);
%

% Updates

if nargin < 2; mask = []; end
if nargin < 3; BatchOptIn = struct; end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
id = obj.getActiveId();

imageFilename = obj.I{id}.image.filename;
if ~isempty(imageFilename) && ~strcmp(imageFilename, 'none.tif')
    defaultDir = fileparts(imageFilename);
else
    defaultDir = obj.currentDirectory;
end

BatchOpt.DirectoryName    = {'Inherit from dataset filename'};
BatchOpt.DirectoryName{2} = {'Inherit from dataset filename', obj.currentDirectory, 'Inherit from Directory/File loop'};
BatchOpt.FilenameFilter   = 'Mask_[F].mask';
BatchOpt.showWaitbar      = true;
BatchOpt.id               = id;

BatchOpt.mibBatchSectionName = 'Ribbon -> Mask';
BatchOpt.mibBatchActionName  = 'Load mask';
BatchOpt.mibBatchTooltip.DirectoryName  = sprintf('Directory where the mask file is located; "Inherit from dataset filename" uses the directory of the open image');
BatchOpt.mibBatchTooltip.FilenameFilter = sprintf('Filename or filter for the mask file; [F] is replaced with the base name of the open image');
BatchOpt.mibBatchTooltip.showWaitbar    = sprintf('Show or not the progress bar during loading');

batchModeSwitch = 0;

ErrorDlgOpt = struct('optionalPrefix', 'Error in MibModel.loadMask', 'WindowHeight', 160);

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
    header       = sprintf('Masks are not available in the virtual stacking mode!\nPlease switch to the memory-resident mode first.');
    dlgOpt.WindowHeight = 170;
    dlgOpt.HeaderLines  = 2;
    dlgOpt.mibPath      = obj.mibPath;
    utils.dlgs.inputUniversalDlg(obj.mibGUI, header, {}, {}, 'Not implemented', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

%% enableSelection guard
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

%% IMPORT PATH — mask array provided
if ~isempty(mask)
    dsOpts.mask = mask;
    result = obj.I{id}.loadMask([], dsOpts);
    if isempty(result); return; end

    obj.showMask = true;
    notify(obj, 'UpdateGuiWidgets');
    notify(obj, 'ShowImage');

    if batchModeSwitch
        eventdata = core.ToggleEventData(BatchOpt);
        notify(obj, 'SyncBatch', eventdata);
    end
    return;
end

%% FILE PATH — resolve directory and filenames

if strcmp(BatchOpt.DirectoryName{1}, 'Inherit from dataset filename')
    BatchOpt.DirectoryName{1} = defaultDir;
end

if batchModeSwitch
    % ---- BATCH MODE: expand [F] template and glob ----
    [~, baseFilename] = fileparts(obj.I{id}.image.filename);
    filterExpanded = strrep(BatchOpt.FilenameFilter, '[F]', baseFilename);

    if isfile(filterExpanded)
        filenames = {filterExpanded};
    else
        d = dir(fullfile(BatchOpt.DirectoryName{1}, filterExpanded));
        d = d(~[d.isdir]);
        if isempty(d)
            ErrorDlgOpt.winTitle = 'File not found';
            ErrorDlgOpt.err = sprintf('No mask file matching "%s" was found in:\n%s', ...
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
        '*.mask',          'MATLAB mask (*.mask)'; ...
        '*.am',            'Amira Mesh (*.am)'; ...
        '*.h5;*.hdf5',     'HDF5 (*.h5, *.hdf5)'; ...
        '*.tif;*.tiff',    'TIFF (*.tif, *.tiff)'; ...
        '*.png',           'PNG (*.png)'; ...
        '*.xml',           'HDF5+XML (*.xml)'; ...
        '*.*',             'All files (*.*)'};

    [file, path] = utils.dlgs.mibUiGetFile(fileFilter, ...
        'Open mask file(s)', BatchOpt.DirectoryName{1}, 'on');

    if isequal(file, 0); return; end

    if ischar(file); file = {file}; end
    filenames = cellfun(@(f) fullfile(path, f), file, 'UniformOutput', false);
end

%% Resolve loader and delegate to MibDataset.loadMask

[~, ~, ext] = fileparts(filenames{1});
ext = lower(ext);

if strcmp(ext, '.mask')
    % .mask files are plain MAT files — handled directly in MibDataset.loadMask
    dsOpts.loaderType = 'matlab_mask';
else
    % Use ExtensionRegistryLoad for all other formats
    allowedExt = obj.extensionRegistryLoad.getAllowedExtensions('Model', 'Default', false);
    allowedExtNoDot = strrep(allowedExt, '.', '');
    extNoDot = strrep(ext, '.', '');
    if ~ismember(extNoDot, allowedExtNoDot)
        ErrorDlgOpt.winTitle = 'Unsupported format';
        ErrorDlgOpt.err = sprintf('The extension "%s" is not supported for mask loading.', ext);
        eventdata = core.ToggleEventData(ErrorDlgOpt);
        notify(obj, 'ShowErrorDialog', eventdata);
        notify(obj, 'StopProtocol');
        return;
    end

    loaderInfo = obj.extensionRegistryLoad.resolveLoader(filenames{1}, 'Model', 'Default');
    if ischar(loaderInfo)
        ErrorDlgOpt.winTitle = 'Loader error';
        ErrorDlgOpt.err = loaderInfo;
        eventdata = core.ToggleEventData(ErrorDlgOpt);
        notify(obj, 'ShowErrorDialog', eventdata);
        notify(obj, 'StopProtocol');
        return;
    end
    dsOpts.loaderInfo = loaderInfo;
end

result = obj.I{id}.loadMask(filenames, dsOpts);
if isempty(result); return; end

obj.showMask = true;
notify(obj, 'UpdateGuiWidgets');
notify(obj, 'ShowImage');

if batchModeSwitch
    eventdata = core.ToggleEventData(BatchOpt);
    notify(obj, 'SyncBatch', eventdata);
end
end
