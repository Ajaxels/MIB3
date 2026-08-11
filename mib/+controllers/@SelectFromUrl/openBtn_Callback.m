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

% ---- plain image URL: the behaviour this menu item always had ------------
if isempty(obj.zarrFormat)
    obj.openPlainImageUrl();
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
        utils.dlgs.showErrorDialog(obj.guiFigure(), ME.message, ...
            'Remote Zarr: Python packages missing');
        return;
    end
end

targetUrl = io.RemoteStore.join(obj.rootUrl, obj.BatchOpt.GroupPath);
datasetId = obj.mibModel.getActiveId();
obj.BatchOpt.id = datasetId;

% ---- labels: load onto the dataset that is already open ------------------
if strcmp(obj.BatchOpt.LoadAs{1}, 'Labels')
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
targetMode = obj.BatchOpt.DatasetMode{1};
if ~strcmp(obj.mibModel.I{datasetId}.datasetType, targetMode)
    modeIndex = find(strcmp({'Standard', 'Virtual', 'BigData'}, targetMode), 1);
    placeholderFile = {fullfile(obj.mibModel.mibPath, 'assets', 'images', 'default.h5')};
    achievedMode = obj.mibModel.I{datasetId}.switchDatasetMode(modeIndex, ...
        obj.mibModel.preferences.System.EnableSelection, placeholderFile);
    if achievedMode ~= modeIndex
        utils.dlgs.showErrorDialog(obj.guiFigure(), ...
            sprintf('Could not switch the dataset buffer to %s mode.', targetMode), ...
            'Import from URL');
        return;
    end
end

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

obj.returnBatchOpt();
if ~batchModeSwitch; obj.closeWindow(); end
end
