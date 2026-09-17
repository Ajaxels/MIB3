function openLabelCrop(obj, batchModeSwitch)
% OPENLABELCROP - Open a ground-truth crop: the image region plus the selected labels.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.openLabelCrop(batchModeSwitch)
%
% **Fetching the image region is mandatory here, not a convenience.** Loading a
% group as Labels needs an open dataset whose dimensions match, and when a crop
% is selected the open dataset is the whole parent volume - a 200^3 island
% inside a 25-gigavoxel EM stack. The combination a user could otherwise pick
% has no working outcome at all, so the image sub-volume is opened first and the
% labels go onto that.
%
% Sequence:
%
%   1. read every selected label group's pyramid, confirming any instance group
%   2. resolve the image pyramid the crop came from (or take the override)
%   3. plan the pairing - which level of each, and assert the shapes agree
%   4. open the image region through ``MibModel.loadImages`` with ``Region``
%   5. blend the label groups into one index map and attach it as the model
%
% Input Arguments:
%   - **batchModeSwitch** - [logical] true when running headless

if nargin < 2; batchModeSwitch = false; end

parentFigure = obj.guiFigure();
labelGroupUrls = obj.selectedLabelGroupUrls();
if isempty(labelGroupUrls)
    utils.dlgs.showErrorDialog(parentFigure, 'No label group was selected.', 'Import from URL');
    return;
end

% Takes over the bar openBtn_Callback already raised rather than opening a
% second one; it stays Indeterminate until composeLabelModel knows how many
% groups it will read, which is the first point anything here can be counted.
if isempty(obj.progressDialog); obj.startProgress('Reading crop metadata...'); end
progressDialog = obj.progressDialog;
if ~isempty(progressDialog) && isvalid(progressDialog)
    progressDialog.Message = 'Reading crop metadata...';
    drawnow limitrate;
end
% Every failure below returns early, and each one leaves a modal progress bar
% in front of its own error dialog without this.
cleanupProgress = onCleanup(@() obj.stopProgress());

% ---- 1. the label groups ------------------------------------------------
labelPyramids = cell(1, numel(labelGroupUrls));
for groupIndex = 1:numel(labelGroupUrls)
    pyramidInfo = obj.readGroupPyramid(labelGroupUrls{groupIndex});
    if ~pyramidInfo.ok
        obj.stopProgress();
        utils.dlgs.showErrorDialog(parentFigure, sprintf( ...
            'The group "%s" has no image pyramid and cannot be loaded as labels.', ...
            io.RemoteStore.relativePath(obj.rootUrl, labelGroupUrls{groupIndex})), ...
            'Import label crop');
        return;
    end
    labelPyramids{groupIndex} = pyramidInfo;
end

% An instance group's objects are kept by default - this builds an ordinary
% in-memory model, so there is room for them - and merging them into one mask is
% offered as the alternative. Skipped when a protocol already stated the choice.
isInstance = cellfun(@(info) strcmp(info.annotationType, 'instance_segmentation'), labelPyramids);
if any(isInstance) && ~obj.BatchOpt.MergeInstanceObjects
    instanceNames = cellfun(@(url, info) obj.labelGroupName(url, info), ...
        labelGroupUrls(isInstance), labelPyramids(isInstance), 'UniformOutput', false);
    if ~obj.chooseInstanceHandling(instanceNames); return; end
end

% ---- 2. the image it was cut from --------------------------------------
if ~isempty(obj.BatchOpt.ImageGroupPath)
    imageGroupUrl = io.RemoteStore.join(obj.rootUrl, obj.BatchOpt.ImageGroupPath);
    imagePyramid  = obj.readGroupPyramid(imageGroupUrl);
else
    [imageGroupUrl, imagePyramid] = obj.resolveSiblingImageGroup( ...
        labelGroupUrls{1}, labelPyramids{1});
end

% ---- 3. the pairing -----------------------------------------------------
cropPlan = obj.planLabelCrop(labelPyramids{1}, imagePyramid);
if ~cropPlan.ok
    obj.stopProgress();
    utils.dlgs.showErrorDialog(parentFigure, cropPlan.reason, 'Import label crop');
    return;
end

% This route reads the image region and the model into memory, so it cannot
% honour BigData or Virtual. resolveLabelRoute says so in the info panel and
% disables Open; repeated here because batch mode never runs that, and because
% silently overriding the mode is exactly what this used to do.
if ~strcmp(obj.BatchOpt.DatasetMode{1}, 'Standard')
    obj.stopProgress();
    utils.dlgs.showErrorDialog(parentFigure, sprintf( ...
        ['Cannot add labels to a %s dataset.\n\n' ...
         'Labels are always read into memory together with their image region, so the result ' ...
         'is a Standard dataset.\n\n' ...
         'To continue: set "Dataset mode" to Standard and press Open again.'], ...
        obj.BatchOpt.DatasetMode{1}), 'Import label crop');
    return;
end

% Which pair of levels, now that more than one may line up. Silent for a single
% candidate and for a protocol that named ZarrLevel.
[cropPlan, levelChosen] = obj.chooseCropLevel(cropPlan);
if ~levelChosen; return; end
obj.cropPlan = cropPlan;

imageGroupPath = io.RemoteStore.relativePath(obj.rootUrl, imageGroupUrl);

% ---- 4. the image region ------------------------------------------------
if ~isempty(progressDialog) && isvalid(progressDialog)
    progressDialog.Message = sprintf('Opening the image region (%d x %d x %d)...', ...
        cropPlan.shapeYXZ(2), cropPlan.shapeYXZ(1), cropPlan.shapeYXZ(3));
    drawnow limitrate;
end

datasetId = obj.mibModel.getActiveId();
obj.BatchOpt.id = datasetId;
% The mode was checked above, so this only has to put the buffer there - which
% also brings the Datasets panel cache along (see ensureDatasetMode).
if ~obj.ensureDatasetMode(datasetId, 'Standard'); return; end

loadOptions               = obj.buildLoadImagesBatchOpt();
loadOptions.ZarrGroupPath = imageGroupPath;
loadOptions.Region        = cropPlan.cropOuterBoxUm;
% The level is settled by the pairing, so the Standard-mode level picker must
% not appear: any other choice would break the match just asserted.
loadOptions.ZarrLevel     = cropPlan.imageLevel;
obj.mibModel.loadImages('Combine datasets', loadOptions);

imageSize = [obj.mibModel.I{datasetId}.image.height, ...
             obj.mibModel.I{datasetId}.image.width, ...
             obj.mibModel.I{datasetId}.image.depth];
if ~isequal(imageSize, cropPlan.shapeYXZ)
    % The plan asserted these agree from metadata alone; if the opened dataset
    % disagrees, something between the two is wrong and attaching the labels
    % anyway would misplace them.
    obj.stopProgress();
    utils.dlgs.showErrorDialog(parentFigure, sprintf( ...
        ['The image region opened as %d x %d x %d but the labels are %d x %d x %d ' ...
         '(Y x X x Z), so the model was not attached.'], ...
        imageSize(1), imageSize(2), imageSize(3), ...
        cropPlan.shapeYXZ(1), cropPlan.shapeYXZ(2), cropPlan.shapeYXZ(3)), ...
        'Import label crop');
    return;
end

% ---- 5. the model -------------------------------------------------------
[modelData, materialNames, compositionReport] = obj.composeLabelModel( ...
    labelGroupUrls, labelPyramids, cropPlan, progressDialog);

% Derived, not asked: 63 materials always suffice for COSEM (the most classes
% any of the 26 reference crops declares is 63), and labels63 gives up mask and
% selection as separate layers, so the larger scheme is used only when needed.
% An instance segmentation kept whole is what reaches past 255 - jrc_mus-kidney's
% nuc holds 864 objects - and composeLabelModel refuses past 65535 rather than
% overflow, naming the merge as the way out.
if numel(materialNames) > 255
    modelType = 65535;
elseif numel(materialNames) > 63
    modelType = 255;
else
    modelType = 63;
end
obj.mibModel.I{datasetId}.createModel(modelType, materialNames);
obj.mibModel.setData3D(modelData, 'labels', 1, 3, NaN, struct('id', datasetId));

labelsLayer = obj.mibModel.I{datasetId}.labels;
if isempty(labelsLayer.materialColors)
    palette = obj.mibModel.preferences.Colors.ModelMaterialColors;
    if isempty(palette)
        labelsLayer.materialColors = rand(numel(materialNames), 3);
    else
        labelsLayer.materialColors = palette(mod(0:numel(materialNames)-1, size(palette, 1)) + 1, :);
    end
end
obj.mibModel.showModel = true;   % createModel already set modelExist

% The buffer is Standard by construction here and the user chose that, so there
% is no override left to explain - only the consequence they cannot see: the
% image's finer levels are not in this buffer.
if cropPlan.imageLevel > 1
    compositionReport.lines = [{sprintf(['Read at %s (%g nm). The image''s finer levels are ' ...
        'not in this buffer; reopen the image group on its own for those.'], ...
        cropPlan.imageLevelName, cropPlan.voxelSizeUm(1) * 1000)}, compositionReport.lines];
end

delete(cleanupProgress);
obj.reportCropResult(imageGroupPath, cropPlan, materialNames, compositionReport);

% ensureDatasetMode wrote the Sets.datasetTypes cache; the repaint waits until
% here, because DatasetsPanelUpdate ends up calling ShowImage and the buffer is
% only paintable once the region and its model are in place.
notify(obj.mibModel, 'DatasetsPanelUpdate');
notify(obj.mibModel, 'UpdateGuiWidgets');
notify(obj.mibModel, 'ShowImage');

obj.returnBatchOpt();
if ~batchModeSwitch; obj.closeWindow(); end
end
