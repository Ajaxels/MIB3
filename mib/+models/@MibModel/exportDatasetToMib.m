function exportDatasetToMib(obj, layerType, BatchOptIn)
% EXPORTDATASETTOMIB - Copy the mask or model layer to another MIB container (buffer).
%
% Syntax:
%   function exportDatasetToMib(obj, layerType, BatchOptIn)
%
% Input Arguments:
%   - **layerType** — a string specifying which layer to copy:
%
%     - ``'mask'`` — copy the mask layer
%     - ``'model'`` — copy the model (labels) layer, including material metadata
%
%   - **BatchOptIn** — *(optional)* a structure for batch processing mode; when ``NaN``
%     returns a structure with default options via "SyncBatch" event:
%
%     - ``.LayerType`` — cell string, ``{'mask'|'model'}`` layer to copy
%     - ``.Destination`` — cell string, destination container, e.g. ``{'Container 2'}``
%     - ``.showWaitbar`` — logical, show or not the waitbar
%     - ``.id`` — *(optional)* index of the source dataset
%
% Usage:
%   **Example 1** — copy mask interactively
%
%   .. code-block:: matlab
%
%      obj.mibModel.exportDatasetToMib('mask');
%
%   **Example 2** — copy model interactively
%
%   .. code-block:: matlab
%
%      obj.mibModel.exportDatasetToMib('model');
%
%   **Example 3** — batch mode
%
%   .. code-block:: matlab
%
%      BatchOpt.Destination = {'Container 2'};
%      BatchOpt.showWaitbar = false;
%      obj.mibModel.exportDatasetToMib('mask', BatchOpt);
%

% Updates
%

if nargin < 3; BatchOptIn = struct(); end
if nargin < 2; layerType = 'mask'; end

activeId = obj.getActiveId();

%% Pre-flight checks (before building BatchOpt — fail fast)
if strcmp(obj.I{activeId}.datasetType, 'Virtual')
    toolname = sprintf('Export of %s is', layerType);
    warningBody = sprintf('%s not yet available in the virtual stacking mode.\nPlease switch to the memory-resident mode and try again', toolname);
    dlgOpt = struct();
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_error';
    dlgOpt.HeaderLines = 1;
    dlgOpt.WindowHeight = 190;
    utils.dlgs.inputUniversalDlg(obj.mibGUI, 'Not implemented!', {''}, {warningBody}, ...
        'MibModel.exportDatasetToMib: Ops!!!', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

if strcmp(layerType, 'model')
    if obj.I{activeId}.enableSelection == 0
        dlgOpt = struct();
        dlgOpt.MsgBoxOnly = true;
        dlgOpt.Icon = 'puffin_warning';
        dlgOpt.HeaderLines = 1;
        dlgOpt.WindowHeight = 180;
        utils.dlgs.inputUniversalDlg(obj.mibGUI, 'The models are switched off!', {''}, ...
            {sprintf('Make sure that the "Enable selection" option in the Preferences dialog:\nRibbon -> Home -> Preferences\nis set to "yes" and try again...')}, ...
            'Models are disabled', dlgOpt);
        notify(obj, 'StopProtocol');
        return;
    end
    if ~obj.I{activeId}.modelExist
        dlgOpt = struct();
        dlgOpt.MsgBoxOnly = true;
        dlgOpt.Icon = 'puffin_warning';
        dlgOpt.HeaderLines = 1;
        utils.dlgs.inputUniversalDlg(obj.mibGUI, 'The model is not yet created!', {''}, ...
            {sprintf('Create or load a model first!')}, ...
            'The model is missing!', dlgOpt);
        notify(obj, 'StopProtocol');
        return;
    end
end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
BatchOpt.LayerType    = {layerType};
BatchOpt.LayerType{2} = {'mask', 'model'};
BatchOpt.id           = activeId;

totalContainers = numel(obj.Sets.names) * obj.Sets.datasetsInSet;
defaultDestGlobalId = mod(activeId, totalContainers) + 1;   % next container, wrapping
BatchOpt.Destination    = {sprintf('Container %d', defaultDestGlobalId)};
BatchOpt.Destination{2} = arrayfun(@(n) sprintf('Container %d', n), ...
    1:totalContainers, 'UniformOutput', false);
BatchOpt.showWaitbar = true;

switch layerType
    case 'mask'
        BatchOpt.mibBatchSectionName = 'Ribbon -> Mask';
        BatchOpt.mibBatchActionName  = 'Export mask to MIB container';
        BatchOpt.mibBatchTooltip.LayerType   = 'Layer to copy to another MIB container';
        BatchOpt.mibBatchTooltip.Destination = 'Destination container, e.g. "Container 2"';
        BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';
    case 'model'
        BatchOpt.mibBatchSectionName = 'Ribbon -> Model';
        BatchOpt.mibBatchActionName  = 'Export model to MIB container';
        BatchOpt.mibBatchTooltip.LayerType   = 'Layer to copy to another MIB container';
        BatchOpt.mibBatchTooltip.Destination = 'Destination container, e.g. "Container 2"';
        BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';
end

%% Interactive dialog (nargin < 3)
if nargin < 3
    destGlobalId = str2double(BatchOpt.Destination{1}(10:end));
    destSetIdx   = ceil(destGlobalId / obj.Sets.datasetsInSet);
    destLocalId  = min([mod(destGlobalId-1, obj.Sets.datasetsInSet)+1, obj.Sets.datasetsInSet]);

    prompts  = {'Destination set:', sprintf('Destination buffer (1-%d):', obj.Sets.datasetsInSet)};
    setItems = obj.Sets.names(:)';
    defAns   = {[setItems, {destSetIdx}], ...
                 struct('Spinner', true, 'Value', destLocalId, ...
                        'Limits', [1 obj.Sets.datasetsInSet], 'Step', 1, 'Round', true)};
    dlgOptions.mibPath       = obj.mibPath;
    dlgOptions.LabelPosition = 'left';
    dlgOptions.Focus         = 2;
    [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.mibGUI, '', prompts, defAns, ...
        'Export to MIB container', dlgOptions);
    if isempty(answer); return; end

    destSetIdx   = selIndex(1);
    destLocalId  = answer{2};
    destGlobalId = destLocalId + (destSetIdx-1)*obj.Sets.datasetsInSet;
    BatchOpt.Destination(1) = {sprintf('Container %d', destGlobalId)};
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
            ErrorDlgOpt.optionalPrefix = 'Error in MibModel.exportDatasetToMib';
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

%% Resolve destination
destGlobalId = str2double(BatchOpt.Destination{1}(10:end));
sourceId     = BatchOpt.id;

%% Dimension check
if obj.I{sourceId}.image.height ~= obj.I{destGlobalId}.image.height || ...
   obj.I{sourceId}.image.width  ~= obj.I{destGlobalId}.image.width  || ...
   obj.I{sourceId}.image.depth  ~= obj.I{destGlobalId}.image.depth  || ...
   obj.I{sourceId}.image.time   ~= obj.I{destGlobalId}.image.time
    errorMsg = sprintf(['Dimensions mismatch [H x W x D x T]\n' ...
        'Source:      %d x %d x %d x %d\n' ...
        'Destination: %d x %d x %d x %d'], ...
        obj.I{sourceId}.image.height, obj.I{sourceId}.image.width, ...
        obj.I{sourceId}.image.depth,  obj.I{sourceId}.image.time, ...
        obj.I{destGlobalId}.image.height, obj.I{destGlobalId}.image.width, ...
        obj.I{destGlobalId}.image.depth,  obj.I{destGlobalId}.image.time);
    utils.dlgs.showErrorDialog(obj.mibGUI, errorMsg, 'Wrong dimensions');
    notify(obj, 'StopProtocol');
    return;
end

%% Copy data
if BatchOpt.showWaitbar
    progressBar = uiprogressdlg(obj.mibGUI, 'Value', 0, ...
        'Message', sprintf('Copying the %s...', BatchOpt.LayerType{1}), ...
        'Title', 'Export to MIB container');
end

getDataOptions.blockModeSwitch = 0;
getDataOptions.id = sourceId;
setDataOptions.blockModeSwitch = 0;
setDataOptions.id = destGlobalId;

switch BatchOpt.LayerType{1}
    case 'mask'
        layerData = obj.getData4D('mask', 3, NaN, getDataOptions);
        if BatchOpt.showWaitbar; progressBar.Value = 0.5; end
        obj.setData4D(layerData, 'mask', 3, NaN, setDataOptions);

    case 'model'
        layerData = obj.getData4D('labels', 3, NaN, getDataOptions);
        if BatchOpt.showWaitbar; progressBar.Value = 0.5; end
        obj.setData4D(layerData, 'labels', 3, NaN, setDataOptions);
        obj.I{destGlobalId}.labels.materialNames  = obj.I{sourceId}.labels.materialNames;
        obj.I{destGlobalId}.labels.materialColors = obj.I{sourceId}.labels.materialColors;
end

fprintf('MIB: the %s layer was exported from container %d to container %d\n', ...
    BatchOpt.LayerType{1}, sourceId, destGlobalId);
if BatchOpt.showWaitbar; progressBar.Value = 1; delete(progressBar); end

%% Notify batch
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);
end
