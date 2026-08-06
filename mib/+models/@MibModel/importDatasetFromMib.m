function importDatasetFromMib(obj, layerType, BatchOptIn)
% IMPORTDATASETFROMMIB - Import the mask or model layer from another MIB container into the active dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.importDatasetFromMib(layerType, BatchOptIn)
%
% This is the inverse of exportDatasetToMib: it pulls a layer FROM another
% container INTO the currently active container.
%
% Input Arguments:
%   - **layerType** - a string specifying which layer to import:
%
%     - ``'mask'`` - copy the mask layer from another container
%     - ``'model'`` - copy the model (labels) layer + material metadata from another container
%
%   - **BatchOptIn** - *(optional)* a structure for batch processing mode; when ``NaN``
%     returns a structure with default options via "SyncBatch" event:
%
%     - ``.LayerType`` - cell string, ``{'mask'|'model'}`` layer to import
%     - ``.Source`` - cell string, source container, e.g. ``{'Container 2'}``
%     - ``.showWaitbar`` - logical, show or not the waitbar
%     - ``.id`` - *(optional)* index of the destination dataset
%
% Usage:
%   **Example 1** - import mask interactively
%
%   .. code-block:: matlab
%
%      obj.mibModel.importDatasetFromMib('mask');
%
%   **Example 2** - import model interactively
%
%   .. code-block:: matlab
%
%      obj.mibModel.importDatasetFromMib('model');
%
%   **Example 3** - batch mode
%
%   .. code-block:: matlab
%
%      BatchOpt.Source = {'Container 2'};
%      BatchOpt.showWaitbar = false;
%      obj.mibModel.importDatasetFromMib('mask', BatchOpt);
%

% Updates
%

if nargin < 3; BatchOptIn = struct(); end
if nargin < 2; layerType = 'mask'; end

activeId = obj.getActiveId();

%% Pre-flight checks (before building BatchOpt - fail fast)
if strcmp(obj.I{activeId}.datasetType, 'Virtual')
    toolname = sprintf('Import of %s is', layerType);
    warningBody = sprintf('%s not yet available in the virtual stacking mode.\nPlease switch to the memory-resident mode and try again', toolname);
    dlgOpt = struct();
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_error';
    dlgOpt.HeaderLines = 1;
    dlgOpt.WindowHeight = 190;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), 'Not implemented!', {''}, {warningBody}, ...
        'MibModel.importDatasetFromMib: Ops!!!', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

if obj.I{activeId}.enableSelection == 0
    dlgOpt = struct();
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_warning';
    dlgOpt.HeaderLines = 1;
    dlgOpt.WindowHeight = 180;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), 'The selection layers are switched off!', {''}, ...
        {sprintf('Make sure that the "Enable selection" option in the Preferences dialog:\nRibbon -> Home -> Preferences\nis set to "yes" and try again...')}, ...
        'Selection layers disabled', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
BatchOpt.LayerType    = {layerType};
BatchOpt.LayerType{2} = {'mask', 'model'};
BatchOpt.id           = activeId;
BatchOpt.showWaitbar  = true;

totalContainers = numel(obj.Sets.names) * obj.Sets.datasetsInSet;
% Find nearest loaded container (by circular distance), skipping the destination
defaultSrcGlobalId = mod(activeId - 2, totalContainers) + 1;  % fallback: previous by index
for offset = 1:totalContainers-1
    candidateId = mod(activeId - 1 + offset, totalContainers) + 1;
    if candidateId ~= activeId && ~strcmp(obj.I{candidateId}.image.filename, 'none.tif')
        defaultSrcGlobalId = candidateId;
        break;
    end
end
BatchOpt.Source    = {sprintf('Container %d', defaultSrcGlobalId)};
BatchOpt.Source{2} = arrayfun(@(n) sprintf('Container %d', n), ...
    1:totalContainers, 'UniformOutput', false);

switch layerType
    case 'mask'
        BatchOpt.mibBatchSectionName = 'Ribbon -> Mask';
        BatchOpt.mibBatchActionName  = 'Import mask from MIB container';
        BatchOpt.mibBatchTooltip.LayerType   = 'Layer to import from another MIB container';
        BatchOpt.mibBatchTooltip.Source      = 'Source container, e.g. "Container 2"';
        BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';
    case 'model'
        BatchOpt.mibBatchSectionName = 'Ribbon -> Model';
        BatchOpt.mibBatchActionName  = 'Import model from MIB container';
        BatchOpt.mibBatchTooltip.LayerType   = 'Layer to import from another MIB container';
        BatchOpt.mibBatchTooltip.Source      = 'Source container, e.g. "Container 2"';
        BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';
end

%% Interactive dialog (nargin < 3)
if nargin < 3
    srcGlobalId = str2double(BatchOpt.Source{1}(10:end));
    srcSetIdx   = ceil(srcGlobalId / obj.Sets.datasetsInSet);
    srcLocalId  = min([mod(srcGlobalId-1, obj.Sets.datasetsInSet)+1, obj.Sets.datasetsInSet]);

    prompts  = {'Source set:', sprintf('Source buffer (1-%d):', obj.Sets.datasetsInSet)};
    setItems = obj.Sets.names(:)';
    defAns   = {[setItems, {srcSetIdx}], ...
                 struct('Spinner', true, 'Value', srcLocalId, ...
                        'Limits', [1 obj.Sets.datasetsInSet], 'Step', 1, 'Round', true)};
    dlgOptions.mibPath       = obj.mibPath;
    dlgOptions.LabelPosition = 'left';
    dlgOptions.Focus         = 2;
    [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), '', prompts, defAns, ...
        'Import from MIB container', dlgOptions);
    if isempty(answer); return; end

    srcSetIdx   = selIndex(1);
    srcLocalId  = answer{2};
    srcGlobalId = srcLocalId + (srcSetIdx-1)*obj.Sets.datasetsInSet;
    BatchOpt.Source(1) = {sprintf('Container %d', srcGlobalId)};
end

%% Batch mode check (nargin == 3)
if nargin == 3
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)
            BatchOpt = rmfield(BatchOpt, 'id');
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj, 'SyncBatch', eventdata);
        else
            ErrorDlgOpt = struct();
            ErrorDlgOpt.winTitle = 'BatchOpt Error';
            ErrorDlgOpt.optionalPrefix = 'Error in MibModel.importDatasetFromMib';
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

%% Resolve source and destination
sourceId = str2double(BatchOpt.Source{1}(10:end));
destId   = BatchOpt.id;

%% Same-container guard
if sourceId == destId
    utils.dlgs.showErrorDialog(obj.getProgressBarParent(), ...
        'Source and destination containers are the same!', 'Wrong container');
    notify(obj, 'StopProtocol'); return;
end

%% Source layer existence guard
switch BatchOpt.LayerType{1}
    case 'mask'
        if ~obj.I{sourceId}.maskExist
            utils.dlgs.showErrorDialog(obj.getProgressBarParent(), ...
                sprintf('Mask layer not found in container %d!', sourceId), 'Missing mask');
            notify(obj, 'StopProtocol'); return;
        end
    case 'model'
        if ~obj.I{sourceId}.modelExist
            utils.dlgs.showErrorDialog(obj.getProgressBarParent(), ...
                sprintf('Model not found in container %d!', sourceId), 'Missing model');
            notify(obj, 'StopProtocol'); return;
        end
end

%% Dimension check
if obj.I{sourceId}.image.height ~= obj.I{destId}.image.height || ...
   obj.I{sourceId}.image.width  ~= obj.I{destId}.image.width  || ...
   obj.I{sourceId}.image.depth  ~= obj.I{destId}.image.depth  || ...
   obj.I{sourceId}.image.time   ~= obj.I{destId}.image.time
    errorMsg = sprintf(['Dimensions mismatch [H x W x D x T]\n' ...
        'Source:      %d x %d x %d x %d\n' ...
        'Destination: %d x %d x %d x %d'], ...
        obj.I{sourceId}.image.height, obj.I{sourceId}.image.width, ...
        obj.I{sourceId}.image.depth,  obj.I{sourceId}.image.time, ...
        obj.I{destId}.image.height,   obj.I{destId}.image.width, ...
        obj.I{destId}.image.depth,    obj.I{destId}.image.time);
    utils.dlgs.showErrorDialog(obj.getProgressBarParent(), errorMsg, 'Wrong dimensions');
    notify(obj, 'StopProtocol');
    return;
end

%% Backup destination before overwrite
backupOptions.blockModeSwitch = 0;
backupOptions.id = destId;
switch BatchOpt.LayerType{1}
    case 'mask';  obj.backup('mask',   1, backupOptions);
    case 'model'; obj.backup('labels', 1, backupOptions);
end

%% Progress bar
if BatchOpt.showWaitbar
    progressBar = uiprogressdlg(obj.getProgressBarParent(), 'Value', 0, ...
        'Message', sprintf('Importing the %s...', BatchOpt.LayerType{1}), ...
        'Title', 'Import from MIB container');
end

%% Copy data
getDataOptions.blockModeSwitch = 0;
getDataOptions.id = sourceId;
setDataOptions.blockModeSwitch = 0;
setDataOptions.id = destId;

switch BatchOpt.LayerType{1}
    case 'mask'
        layerData = obj.getData4D('mask', 3, NaN, getDataOptions);
        if BatchOpt.showWaitbar; progressBar.Value = 0.5; end
        obj.setData4D(layerData, 'mask', 3, NaN, setDataOptions);
        obj.showMask = true;

    case 'model'
        layerData = obj.getData4D('labels', 3, NaN, getDataOptions);
        if BatchOpt.showWaitbar; progressBar.Value = 0.5; end
        obj.setData4D(layerData, 'labels', 3, NaN, setDataOptions);
        obj.I{destId}.labels.materialNames  = obj.I{sourceId}.labels.materialNames;
        obj.I{destId}.labels.materialColors = obj.I{sourceId}.labels.materialColors;
        obj.showModel = true;
end

fprintf('MIB: the %s layer was imported from container %d to container %d\n', ...
    BatchOpt.LayerType{1}, sourceId, destId);
if BatchOpt.showWaitbar; progressBar.Value = 1; delete(progressBar); end

notify(obj, 'UpdateGuiWidgets');
notify(obj, 'ShowImage');

%% Notify batch
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);
end
