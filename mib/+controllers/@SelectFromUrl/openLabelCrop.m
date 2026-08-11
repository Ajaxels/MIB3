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
%   1. read every selected label group's pyramid, and refuse instance groups
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
    if strcmp(pyramidInfo.annotationType, 'instance_segmentation')
        % Instance ids are 1..N per object, so blending one into a material
        % index map would collapse every object into a single material without
        % anything looking wrong afterwards.
        obj.stopProgress();
        utils.dlgs.showErrorDialog(parentFigure, sprintf( ...
            ['"%s" is an instance segmentation: its values are object ids, not a class.\n' ...
             'Blending it into a model would merge every object into one material. ' ...
             'Open it with Load as = Image instead.'], pyramidInfo.className), ...
            'Import label crop');
        return;
    end
    labelPyramids{groupIndex} = pyramidInfo;
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

imageGroupPath = io.RemoteStore.relativePath(obj.rootUrl, imageGroupUrl);

% ---- 4. the image region ------------------------------------------------
if ~isempty(progressDialog) && isvalid(progressDialog)
    progressDialog.Message = sprintf('Opening the image region (%d x %d x %d)...', ...
        cropPlan.shapeYXZ(2), cropPlan.shapeYXZ(1), cropPlan.shapeYXZ(3));
    drawnow limitrate;
end

datasetId = obj.mibModel.getActiveId();
obj.BatchOpt.id = datasetId;
% Standard mode: every crop in the reference store fits in memory (the largest
% is 64 MB) and core.MibBigDataLabelsZarr2 is read-only by construction, so a
% BigData crop could be viewed but never proofread - which is the whole point.
%
% The Dataset mode control does not apply to a crop, so say so rather than
% appear to ignore it - a user who picked BigData deliberately is owed the
% reason, not a buffer that quietly comes back Standard.
modeNote = '';
if ~strcmp(obj.BatchOpt.DatasetMode{1}, 'Standard')
    modeNote = sprintf(['Dataset mode %s does not apply to a label crop; it was opened as ' ...
        'Standard. A crop is small enough to hold in memory, and a remote label store is ' ...
        'read-only in BigData mode, so it could be viewed but never corrected.'], ...
        obj.BatchOpt.DatasetMode{1});
end
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
if numel(materialNames) > 63
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

if ~isempty(modeNote)
    compositionReport.lines = [{modeNote}, compositionReport.lines];
end

delete(cleanupProgress);
obj.reportCropResult(imageGroupPath, cropPlan, materialNames, compositionReport);

notify(obj.mibModel, 'UpdateGuiWidgets');
notify(obj.mibModel, 'ShowImage');

obj.returnBatchOpt();
if ~batchModeSwitch; obj.closeWindow(); end
end
