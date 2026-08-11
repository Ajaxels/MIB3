function openBtn_Callback(obj, batchModeSwitch)
% OPENBTN_CALLBACK - Perform the import.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.openBtn_Callback()
%      obj.openBtn_Callback(true)     % batch mode, no dialog to close
%
% Routes to one of three destinations, in the order the checks get cheaper to
% recover from:
%
%   * not a zarr store  -> the original ``imread`` import;
%   * ``LoadAs = Labels`` -> ``MibModel.loadModel`` onto the open dataset;
%   * otherwise         -> switch the buffer to the requested dataset mode and
%     call ``MibModel.loadImages``.
%
% Input Arguments:
%   - **batchModeSwitch** - *(optional)* [logical] true when running headless;
%     suppresses closing the (nonexistent) window. Default: false

if nargin < 2; batchModeSwitch = false; end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.SelectFromUrl.openBtn_Callback: triggered\n');
end

if isempty(obj.rootUrl)
    obj.rootUrl = io.RemoteStore.normalise(obj.BatchOpt.Url);
end
if isempty(obj.rootUrl)
    utils.dlgs.showErrorDialog(obj.guiFigure(), 'No URL was given.', 'Import from URL');
    return;
end

% Everything past this point reaches the network, so the window has to say it is
% busy. Indeterminate: none of the work below can report a percentage - see
% startProgress. Cleared by stopProgress on every exit, success or not.
obj.startProgress('Opening the dataset...');
cleanupProgress = onCleanup(@() obj.stopProgress());

% ---- plain image URL: the behaviour this menu item always had ------------
if isempty(obj.zarrFormat)
    obj.openPlainImageUrl();
    obj.stopProgress();
    if ~batchModeSwitch; obj.closeWindow(); end
    return;
end

% Fail early with an actionable message rather than on the first slice read.
% The native engine fetches both zarr v2 and v3 over HTTP range requests with
% no external dependency, so this only applies to the opt-in python backend.
if io.zarr.Config.isPython()
    try
        io.zarr.PyBackend.ensureRemoteSupport(obj.rootUrl);
    catch ME
        obj.stopProgress();
        utils.dlgs.showErrorDialog(obj.guiFigure(), ME.message, ...
            'Remote Zarr: Python packages missing');
        return;
    end
end

% A batch protocol may name only the label groups to blend, since that is the
% whole selection for a crop. The first of them is then also the group whose
% geometry describes the crop, which is what GroupPath means everywhere else.
if isempty(obj.BatchOpt.GroupPath) && ~isempty(obj.BatchOpt.LabelGroups)
    firstLabelGroup = strtrim(extractBefore([obj.BatchOpt.LabelGroups ';'], ';'));
    obj.BatchOpt.GroupPath = char(firstLabelGroup);
end

targetUrl = io.RemoteStore.join(obj.rootUrl, obj.BatchOpt.GroupPath);
datasetId = obj.mibModel.getActiveId();
obj.BatchOpt.id = datasetId;

% ---- labels: load onto the dataset that is already open ------------------
if strcmp(obj.BatchOpt.LoadAs{1}, 'Labels')
    % A sub-volume annotation has no working outcome on the open parent volume,
    % so it takes the crop route instead: open its own image region, then put
    % the labels on that. resolveLabelRoute decided which applies while the user
    % was still choosing; batch mode has not run it, so decide here too.
    if isempty(obj.labelLoadRoute)
        groupSummary = obj.probeGroup(targetUrl);
        obj.resolveLabelRoute(targetUrl, groupSummary);
    end
    if strcmp(obj.labelLoadRoute, 'crop')
        obj.openLabelCrop(batchModeSwitch);
        return;
    end

    % loadModel raises its own progress bar, so hand the screen over to it.
    obj.stopProgress();
    modelOptions = struct();
    modelOptions.Filenames   = {targetUrl};
    modelOptions.showWaitbar = obj.BatchOpt.showWaitbar;
    modelOptions.id          = datasetId;
    obj.mibModel.loadModel([], modelOptions);
    obj.returnBatchOpt();
    if ~batchModeSwitch; obj.closeWindow(); end
    return;
end

% ---- image: put the buffer in the requested mode, then load --------------
% Through ensureDatasetMode rather than inline, because the placeholder that
% switchDatasetMode needs differs per target mode and the cell form used here
% before crashed whenever the target was Standard.
if ~obj.ensureDatasetMode(datasetId, obj.BatchOpt.DatasetMode{1}); return; end

loadOptions = obj.buildLoadImagesBatchOpt();
obj.mibModel.loadImages('Combine datasets', loadOptions);

% Keep the Datasets panel honest about the mode this buffer is now in. Two
% separate things are needed, and neither happens on its own:
%
%   * the panel's type dropdown reads the Sets.datasetTypes cache rather than
%     I{id}.datasetType, so switchDatasetMode above leaves the cache stale;
%   * NewDataset repaints that dropdown only when the active *set* changes
%     (MibController.listener_newDataset), and opening into the current buffer
%     never does - hence the explicit DatasetsPanelUpdate.
%
% Same pattern as Stitching.stitchBtn_Callback and CropDataset. The cache is
% indexed [set, buffer-within-set], NOT by the global dataset id.
datasetsInSet = obj.mibModel.Sets.datasetsInSet;
targetSet     = floor((datasetId - 1) / datasetsInSet) + 1;
targetLocalId = mod(datasetId - 1, datasetsInSet) + 1;
obj.mibModel.Sets.datasetTypes{targetSet, targetLocalId} = ...
    obj.mibModel.I{datasetId}.datasetType;
notify(obj.mibModel, 'DatasetsPanelUpdate');

obj.stopProgress();
obj.returnBatchOpt();
if ~batchModeSwitch; obj.closeWindow(); end
end
