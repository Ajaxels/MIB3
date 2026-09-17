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
%   * ``LoadAs = Labels`` -> ``MibModel.loadModel`` onto the open dataset, or
%     :meth:`openLabelCrop` when the group is a sub-volume needing its own image
%     region. ``loadModel`` picks between an in-place model and a read-only
%     overlay itself, from whether the store's finest level matches the image, so
%     the ``model`` and ``overlay`` routes arrive here the same way;
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

% Opening a second remote group as an Image is the one ambiguous case, so it
% is confirmed rather than assumed - and the answer may switch this run to
% Labels, which is why it happens before the branch below reads LoadAs.
if ~batchModeSwitch && strcmp(obj.BatchOpt.LoadAs{1}, 'Image')
    if ~obj.confirmLoadAs(targetUrl); return; end
end

% ---- labels: load onto the dataset that is already open ------------------
if strcmp(obj.BatchOpt.LoadAs{1}, 'Labels')
    % A sub-volume annotation has no working outcome on the open parent volume,
    % so it takes the crop route instead: open its own image region, then put
    % the labels on that. resolveLabelRoute decided which applies while the user
    % was still choosing; batch mode has not run it, so decide here too.
    if isempty(obj.labelLoadRoute)
        groupSummary = obj.probeGroup(targetUrl);
        [labelsFit, reason] = obj.resolveLabelRoute(targetUrl, groupSummary);
        if ~labelsFit
            % Reachable from the Load as question raised above, which offers
            % Labels for any group; without this the run would fall through to
            % loadModel and fail on the dimension guard four frames down.
            obj.stopProgress();
            if isempty(reason)
                reason = 'This group cannot be loaded as labels onto the open dataset.';
            end
            utils.dlgs.showErrorDialog(obj.guiFigure(), reason, 'Load as Labels');
            return;
        end
    end
    if strcmp(obj.labelLoadRoute, 'crop')
        obj.openLabelCrop(batchModeSwitch);
        return;
    end

    % Keep THIS dialog's progress bar rather than handing over to loadModel's:
    % it is parented to the import window, which is the one the user is looking
    % at, while loadModel parents to the main MIB window (or an undocked image
    % document) and can land behind it. loadModel's own bar is suppressed so
    % there is exactly one - showWaitbar here is not the user's setting but a
    % statement that the caller is already showing progress; obj.progressDialog
    % is the one that honours BatchOpt.showWaitbar, in startProgress.
    if ~isempty(obj.progressDialog) && isvalid(obj.progressDialog)
        obj.progressDialog.Message = 'Opening the label store...';
        drawnow limitrate;
    end
    modelOptions = struct();
    modelOptions.Filenames   = {targetUrl};
    modelOptions.showWaitbar = false;
    modelOptions.id          = datasetId;
    obj.mibModel.loadModel([], modelOptions);
    obj.stopProgress();
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

% ensureDatasetMode wrote the Sets.datasetTypes cache; the repaint has to wait
% until here, because DatasetsPanelUpdate ends up calling ShowImage and between
% the mode switch and this line the buffer holds only the placeholder.
notify(obj.mibModel, 'DatasetsPanelUpdate');

obj.stopProgress();
obj.returnBatchOpt();
if ~batchModeSwitch; obj.closeWindow(); end
end
