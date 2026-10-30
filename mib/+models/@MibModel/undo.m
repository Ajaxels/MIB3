function undo(obj, newIndex)
% UNDO - Undo/redo the recent changes (Ctrl+Z shortcut).
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.undo(newIndex)
%
% Restores a previously stored dataset state from the Backup history.
% Works with all layer types: image, selection, mask, model, everything,
% modelLayers, annotations, lines3d, measurements, and mibDataset.
%
% Entries holding a pixel snapshot of a segmentation layer carry the model type
% they were captured at (``storeOptions.modelType``). When the live labels layer
% has since changed type, it is converted back before the snapshot is applied
% and the current layers are kept for redo as a ``'modelLayers'`` entry - see
% :func:`core.MibDataset.copyModelLayers`.
%
% Input Arguments:
%   - **newIndex** - *(optional)* index of the dataset to restore. When omitted
%     (or NaN), restores the last stored dataset (Ctrl+Z behavior). When
%     provided, navigates the undo history to the specified index (toolbar
%     arrow button behavior).
%
% Output Arguments:
%
% Usage:
%   **Example 1** - undo last action (Ctrl+Z shortcut handler in mibController)
%
%   .. code-block:: matlab
%
%      if obj.mibModel.Backup.enableSwitch == 0; return; end
%      if obj.mibModel.Backup.prevUndoIndex == 0; return; end
%      obj.mibModel.undo();
%      obj.showImage();
%
%   **Example 2** - navigate to a specific index in the undo history (toolbar arrow button)
%
%   .. code-block:: matlab
%
%      obj.mibModel.undo(3);
%      obj.showImage();
%
%   **Example 3** - typical backup + undo workflow from a controller
%
%   .. code-block:: matlab
%
%      obj.mibModel.backup('selection', 0);
%      obj.mibModel.I{obj.mibModel.id}.setData2D(newSelection, 'selection', sliceNo, [], NaN);
%      obj.mibModel.undo();
%
%   **Example 4** - undo with 3D data - backup and undo work symmetrically
%
%   .. code-block:: matlab
%
%      obj.mibModel.backup('mask', 1);
%      obj.mibModel.undo();
%
%   **Example 5** - undo for image type - also restores metadata (dimensions, pixSize, viewPort)
%
%   .. code-block:: matlab
%
%      obj.mibModel.backup('image', 0);
%      obj.mibModel.undo();
%

% Updates
%

if nargin < 2; newIndex = NaN; end
if isnan(newIndex)  % result of Ctrl+Z combination
    newIndex = obj.Backup.prevUndoIndex;
    newDataIndex = obj.Backup.undoIndex;
else                % when using arrow button in the toolbar
    if newIndex < obj.Backup.undoIndex   % shift left - do undo
        newDataIndex = newIndex + 1;
    else                                  % shift right - do redo
        newDataIndex = newIndex - 1;
    end
end

% the undo history as it is now, to put back if the user cancels a BigData restore
historyBefore = struct('undoList', obj.Backup.undoList, 'undoIndex', obj.Backup.undoIndex, ...
    'prevUndoIndex', obj.Backup.prevUndoIndex, 'index3d', obj.Backup.index3d);

% get the stored dataset
[type, data, meta, storeOptions] = obj.Backup.undo(newIndex);
if ~isfield(storeOptions, 'id'); storeOptions.id = obj.id; end
id = storeOptions.id;

% A 3D entry of a disk-backed model is written back in slabs of slices, with a
% cancelable progress dialog (restoreBigDataInSlabs); the first slow step is the
% redo copy of the current state, so the dialog opens here.
wb = [];
slabRestore = isfield(storeOptions, 'switch3d') && storeOptions.switch3d && ...
    ismember(type, {'model', 'labels', 'selection', 'mask', 'everything'}) && ...
    isa(obj.I{id}.labels, 'core.MibBigDataLabels');
progressParent = obj.getProgressBarParent();
if slabRestore && ~isempty(progressParent) && isvalid(progressParent)
    wb = uiprogressdlg(progressParent, 'Title', 'Undo', 'Cancelable', 'on', ...
        'Indeterminate', 'on', 'Message', 'Copying the current state for redo...');
    drawnow;
end
obj.Backup.prevUndoIndex = newDataIndex;

% get stored info about the new place (for selection clear logic)
[type2, ~, ~, ~] = obj.Backup.undo(newDataIndex);

% prepare options
storeOptions.blockModeSwitch = 0;
getDataOptions = storeOptions;

% update LinkedData / LinkedVariable with the current situation
linkedDataRestored = false;
if isfield(storeOptions, 'LinkedData') && ~isempty(fieldnames(storeOptions.LinkedData))
    linkedDataRestored = true;
    linkedFields = fieldnames(storeOptions.LinkedData);
    for fieldId = 1:numel(linkedFields)
        % get the current state of the LinkedData
        comStr = sprintf('currentLinkedData = %s;', storeOptions.LinkedVariable.(linkedFields{fieldId}));
        eval(comStr);        % restore LinkedData from the previous state
        comStr = sprintf('%s = storeOptions.LinkedData.%s;', storeOptions.LinkedVariable.(linkedFields{fieldId}), linkedFields{fieldId});
        eval(comStr);        % update storeOptions to store the currentState
        comStr = sprintf('storeOptions.LinkedData.%s = currentLinkedData;', linkedFields{fieldId});
        eval(comStr);
    end
end

obj.Backup.replaceItem(newIndex, NaN, {NaN}, NaN, storeOptions);

% --- model-type guard ---------------------------------------------------
% A pixel snapshot of a segmentation layer is only valid for the model type it
% was taken at: a type-63 layer keeps mask and selection in bits 7-8 of
% obj.labels, the larger types keep them as standalone layers. Operations that
% replace the labels layer with a different type (convertModel,
% stitchModelInstances) therefore leave older entries incompatible with the
% live layer, and writing them back would reinterpret packed bits as material
% indices. Bring the layer back to the stored type first, and snapshot the
% current layers wholesale so the redo direction stays exact as well.
redoEntryStored = false;
if isfield(storeOptions, 'modelType') && storeOptions.modelType ~= obj.I{id}.labels.maxMaterials && ...
        ismember(type, {'model', 'labels', 'selection', 'mask', 'everything'})
    redoOptions = storeOptions;
    redoOptions.switch3d  = 1;
    redoOptions.orient    = NaN;
    redoOptions.modelType = obj.I{id}.labels.maxMaterials;
    % restoreModelLayers sets these flags itself; stale copies would override it
    redoOptions = rmfield(redoOptions, intersect(fieldnames(redoOptions), {'maskExist', 'modelExist'}));
    obj.Backup.replaceItem(newDataIndex, 'modelLayers', {obj.I{id}.copyModelLayers()}, NaN, redoOptions);
    redoEntryStored = true;

    % note: converting down to type 63 clips material indices above 63 in the
    % parts of the volume the entry does not cover (a 2D entry covers one
    % slice). Operations that change the type take a 'modelLayers' backup of
    % their own, which restores the layer objects and avoids this path.
    obj.I{id}.convertModel(storeOptions.modelType);
end

% store the current situation before applying undo data
dataStore = {};     % the redo copy of a pixel layer, kept to roll back a cancelled restore
if redoEntryStored
    % already written by the model-type guard above
elseif obj.preferences.Undo.Max3dUndoHistory <= 1 && storeOptions.switch3d
    % tweak for storing a single 3D dataset
    switch type
        case 'annotations'
            % non-pixel types have no getData3D; snapshot the full state
            [labels.labelText, labels.labelValue, labels.labelPosition] = obj.I{id}.annotations.getLabels();
            obj.Backup.replaceItem(newDataIndex, type, {labels}, NaN, storeOptions);
        case 'measurements'
            obj.Backup.replaceItem(newDataIndex, type, {obj.I{id}.measure.Data}, NaN, storeOptions);
        case 'lines3d'
            obj.Backup.replaceItem(newDataIndex, type, {copy(obj.I{id}.lines3D)}, NaN, storeOptions);
        case 'mibDataset'
            datasetCopy = obj.deepCopyDataset(id, [], struct('showWaitbar', false));
            obj.Backup.replaceItem(newDataIndex, type, datasetCopy, NaN, storeOptions);
        case 'modelLayers'
            obj.Backup.replaceItem(newDataIndex, type, {obj.I{id}.copyModelLayers()}, NaN, storeOptions);
        otherwise
            dataStore = cell([size(storeOptions.x, 1), 1]);
            for roiId = 1:size(storeOptions.x, 1)
                getDataOptions.x = storeOptions.x(roiId, :);
                getDataOptions.y = storeOptions.y(roiId, :);
                if strcmp(type, 'image')
                    dataStore(roiId) = obj.I{id}.getData3D(type, getDataOptions.t(1), getDataOptions.orient, 0, getDataOptions);
                else
                    dataStore(roiId) = obj.I{id}.getData3D(type, getDataOptions.t(1), getDataOptions.orient, NaN, getDataOptions);
                end
            end
            if strcmp(type, 'image')
                storeOptions.viewPort = obj.I{id}.image.viewPort;
                obj.Backup.replaceItem(newDataIndex, type, dataStore, obj.I{id}.image.getMeta(), storeOptions);
            else
                obj.Backup.replaceItem(newDataIndex, type, dataStore, NaN, storeOptions);
            end
    end
else
    % store the current situation
    if storeOptions.switch3d    % 3D case
        switch type
            case 'image'
                dataStore = obj.I{id}.getData3D(type, getDataOptions.t(1), getDataOptions.orient, 0, getDataOptions);
                storeOptions.viewPort = obj.I{id}.image.viewPort;
                obj.Backup.replaceItem(newDataIndex, type, dataStore, obj.I{id}.image.getMeta(), storeOptions);
            case 'annotations'
                [labels.labelText, labels.labelValue, labels.labelPosition] = obj.I{id}.annotations.getLabels();
                obj.Backup.replaceItem(newDataIndex, type, {labels}, NaN, storeOptions);
            case 'measurements'
                obj.Backup.replaceItem(newDataIndex, type, {obj.I{id}.measure.Data}, NaN, storeOptions);
            case 'mibDataset'
                datasetCopy = obj.deepCopyDataset(id, [], struct('showWaitbar', false));
                obj.Backup.replaceItem(newDataIndex, type, datasetCopy, NaN, storeOptions);
            case 'modelLayers'
                obj.Backup.replaceItem(newDataIndex, type, {obj.I{id}.copyModelLayers()}, NaN, storeOptions);
            otherwise
                dataStore = cell([size(storeOptions.x, 1), 1]);
                for roiId = 1:size(storeOptions.x, 1)
                    getDataOptions.x = storeOptions.x(roiId, :);
                    getDataOptions.y = storeOptions.y(roiId, :);
                    dataStore(roiId) = obj.I{id}.getData3D(type, storeOptions.t(1), getDataOptions.orient, NaN, getDataOptions);
                end
                obj.Backup.replaceItem(newDataIndex, type, dataStore, NaN, storeOptions);
        end
    else        % 2D case
        switch type
            case 'image'
                dataStore = obj.I{id}.getData2D(type, storeOptions.z(1), storeOptions.orient, 0, getDataOptions);
                storeOptions.viewPort = obj.I{id}.image.viewPort;
                obj.Backup.replaceItem(newDataIndex, type, dataStore, obj.I{id}.image.getMeta(), storeOptions);
            case 'annotations'
                [labels.labelText, labels.labelValue, labels.labelPosition] = obj.I{id}.annotations.getLabels();
                obj.Backup.replaceItem(newDataIndex, type, {labels}, NaN, storeOptions);
            case 'lines3d'
                obj.Backup.replaceItem(newDataIndex, type, {copy(obj.I{id}.lines3D)}, NaN, storeOptions);
            case 'measurements'
                obj.Backup.replaceItem(newDataIndex, type, {obj.I{id}.measure.Data}, NaN, storeOptions);
            otherwise
                dataStore = cell([size(storeOptions.x, 1), 1]);
                for roiId = 1:size(storeOptions.x, 1)
                    getDataOptions.x = storeOptions.x(roiId, :);
                    getDataOptions.y = storeOptions.y(roiId, :);
                    dataStore(roiId) = obj.I{id}.getData2D(type, storeOptions.z(1), storeOptions.orient, NaN, getDataOptions);
                end
                obj.Backup.replaceItem(newDataIndex, type, dataStore, NaN, storeOptions);
        end
    end
end
obj.Backup.undoIndex = newIndex;
eventdata = core.ToggleEventData('');    % make empty event data for the notify function at the end

% cancelled while the redo copy was taken: nothing is written yet (a model-type
% conversion above has already happened, so that path goes on)
if ~isempty(wb) && wb.CancelRequested && ~redoEntryStored
    restoreHistory(obj, historyBefore);
    delete(wb);
    return;
end

% --- Apply the stored undo data ---
setDataOptions = storeOptions;
if storeOptions.switch3d     % 3D case
    if ~strcmp(type, 'mibDataset')
        for cellId = 1:numel(data)
            setDataOptions.x = storeOptions.x(cellId, :);
            setDataOptions.y = storeOptions.y(cellId, :);
            setDataOptions2 = rmfield(setDataOptions, 'roiId');
            if slabRestore && ~redoEntryStored && numel(dataStore) >= cellId
                restoreType = type;
                if strcmp(type, 'model'); restoreType = 'labels'; end
                restored = restoreBigDataInSlabs(obj, id, restoreType, data{cellId}, dataStore{cellId}, ...
                    storeOptions, setDataOptions2, wb);
                if ~restored
                    % cancelled: the entries restored before this one go back too
                    for doneCell = 1:cellId-1
                        doneOptions = setDataOptions2;
                        doneOptions.x = storeOptions.x(doneCell, :);
                        doneOptions.y = storeOptions.y(doneCell, :);
                        obj.I{id}.setData3D(dataStore{doneCell}, restoreType, storeOptions.t(1), storeOptions.orient, NaN, doneOptions);
                    end
                    restoreHistory(obj, historyBefore);
                    if ~isempty(wb); delete(wb); end
                    notify(obj, 'ShowImage');
                    return;
                end
                if strcmp(type, 'mask'); obj.I{id}.maskExist = 1; end
                if ismember(type, {'model', 'labels'}); obj.I{id}.modelExist = 1; end
                continue;
            end
            switch type
                case 'image'
                    obj.I{id}.setData3D(data{cellId}, 'image', storeOptions.t(1), storeOptions.orient, 0, setDataOptions2);
                    obj.I{id}.image.setMeta(meta);
                    if obj.I{id}.image.colors ~= size(data{1}, 4)  % dim 4 = colors for [y,x,z,c,t]
                        obj.I{id}.image.colors = size(data{1}, 4);
                        obj.I{id}.slices{4} = 1:min([size(data{1}, 4) 3]);
                    end
                    if isempty(setDataOptions.viewPort)
                        obj.I{id}.image.viewPort = obj.I{id}.image.getDefaultViewPort();
                    else
                        obj.I{id}.image.viewPort = getDataOptions.viewPort;
                    end
                    notify(obj, 'UpdateGuiWidgets');
                case 'selection'
                    obj.I{id}.setData3D(data{cellId}, type, storeOptions.t(1), storeOptions.orient, NaN, setDataOptions2);
                case 'mask'
                    obj.I{id}.setData3D(data{cellId}, type, storeOptions.t(1), storeOptions.orient, NaN, setDataOptions2);
                    obj.I{id}.maskExist = 1;
                case {'model', 'labels'}
                    obj.I{id}.setData3D(data{cellId}, 'labels', storeOptions.t(1), storeOptions.orient, NaN, setDataOptions2);
                    obj.I{id}.modelExist = 1;
                case 'everything'
                    obj.I{id}.setData3D(data{cellId}, type, storeOptions.t(1), storeOptions.orient, NaN, setDataOptions2);
                case 'modelLayers'
                    % whole-layer restore: brings back the model type, the
                    % material names/colours and the selected material as well
                    obj.I{id}.restoreModelLayers(data{cellId});
                    notify(obj, 'UpdateGuiWidgets', core.ToggleEventData({'ribbonModel', 'checkboxes'}));
                case 'annotations'
                    annotData = data{cellId};
                    obj.I{id}.annotations.replaceLabels(annotData.labelText, annotData.labelPosition, annotData.labelValue);
                case 'measurements'
                    eventdata = core.ToggleEventData('measurements');
                    obj.I{id}.measure.Data = data{cellId};
            end
        end
    else
        obj.I{id} = data;
        notify(obj, 'NewDataset', core.ToggleEventData(struct('index', id, 'keepBackup', true)));
        notify(obj, 'ShowImage');
        return;
    end
else        % 2D case
    for cellId = 1:numel(data)
        setDataOptions.x = storeOptions.x(cellId, :);
        setDataOptions.y = storeOptions.y(cellId, :);
        switch type
            case 'image'
                setDataOptions2 = rmfield(setDataOptions, 'roiId');
                obj.I{id}.setData2D(data{cellId}, 'image', storeOptions.z(1), storeOptions.orient, 0, setDataOptions2);
                obj.I{id}.image.setMeta(meta);
                if isempty(setDataOptions.viewPort)
                    obj.I{id}.image.viewPort = obj.I{id}.image.getDefaultViewPort();
                else
                    obj.I{id}.image.viewPort = getDataOptions.viewPort;
                end
            case 'selection'
                setDataOptions2 = rmfield(setDataOptions, 'roiId');
                obj.I{id}.setData2D(data{cellId}, type, storeOptions.z(1), storeOptions.orient, NaN, setDataOptions2);
            case 'mask'
                setDataOptions2 = rmfield(setDataOptions, 'roiId');
                obj.I{id}.setData2D(data{cellId}, type, storeOptions.z(1), storeOptions.orient, NaN, setDataOptions2);
                obj.I{id}.maskExist = 1;
            case {'model', 'labels'}
                setDataOptions2 = rmfield(setDataOptions, 'roiId');
                obj.I{id}.setData2D(data{cellId}, 'labels', storeOptions.z(1), storeOptions.orient, NaN, setDataOptions2);
                obj.I{id}.modelExist = 1;
            case 'everything'
                setDataOptions2 = rmfield(setDataOptions, 'roiId');
                obj.I{id}.setData2D(data{cellId}, type, storeOptions.z(1), storeOptions.orient, NaN, setDataOptions2);
            case 'annotations'
                annotData = data{cellId};
                obj.I{id}.annotations.replaceLabels(annotData.labelText, annotData.labelPosition, annotData.labelValue);
            case 'lines3d'
                eventdata = core.ToggleEventData('lines3d');
                obj.I{id}.lines3D = copy(data{cellId});
            case 'measurements'
                eventdata = core.ToggleEventData('measurements');
                obj.I{id}.measure.Data = data{cellId};
        end
    end
end

if isfield(storeOptions, 'maskExist')
    obj.I{id}.maskExist = storeOptions.maskExist;
end
if isfield(storeOptions, 'modelExist')
    obj.I{id}.modelExist = storeOptions.modelExist;
end

% clear selection layer when undoing a non-selection action that was preceded by a selection backup
if ~strcmp(type, 'selection') && strcmp(type2, 'selection') && newIndex > newDataIndex
    if ~isnan(storeOptions.orient)
        slices = obj.I{id}.slices;
        obj.I{id}.clearLayer('selection', ...
            [slices{1}(1), slices{1}(2)], ...
            [slices{2}(1), slices{2}(2)], ...
            [slices{4}(1), slices{4}(2)], ...
            [slices{5}(1), slices{5}(2)]);
    else
        obj.I{id}.clearLayer('selection');
    end
end

% LinkedData carries state that is mirrored in the GUI rather than in the pixel
% layers - the SAM "add, +next material" mode stores labels.materialNames there.
% Restoring it silently leaves the materials table showing the pre-undo names,
% and because getSelectedMaterialIndex maps a table row through materialNames,
% the next click would then paint into a different material than the row shows.
if linkedDataRestored
    notify(obj, 'UpdateGuiWidgets', core.ToggleEventData({'checkboxes'}));
end

if ~isempty(wb); delete(wb); end
notify(obj, 'ShowImage');

notify(obj, 'Undo', eventdata);
end

% ------------------------------------------------------------------------
function restored = restoreBigDataInSlabs(obj, id, type, data, redoData, storeOptions, setOptions, wb)
% Write a 3D undo entry of a disk-backed model back in slabs of slices, showing
% progress in wb (a uiprogressdlg, or [] without a window). On cancel the slabs
% already written are written back from redoData (the copy of the current state
% undo took first) and false is returned, so the model is as it was before the
% undo. A slab is about 3e7 voxels (storeOptions.undoSlabVoxels overrides it),
% whole tile planes of the coarsest grid in z. storeOptions.undoCancelFcn, a
% function handle returning true to cancel, stands in for the Cancel button
% when there is no window. An entry whose slices are not along dimension 3
% (orientation other than XY) is written in one call.
restored = true;
if ~isfield(storeOptions, 'z') || numel(storeOptions.z) < 2
    storeOptions.z = [1 size(data, 3)];   % a whole-volume entry
end
depth = storeOptions.z(2) - storeOptions.z(1) + 1;
if size(data, 3) ~= depth || storeOptions.orient ~= 3 || ~isequal(size(redoData), size(data))
    obj.I{id}.setData3D(data, type, storeOptions.t(1), storeOptions.orient, NaN, setOptions);
    return;
end
slabVoxels = 3e7;
if isfield(storeOptions, 'undoSlabVoxels'); slabVoxels = storeOptions.undoSlabVoxels; end
cancelFcn = @() false;
if ~isempty(wb)
    cancelFcn = @() wb.CancelRequested;
    wb.Indeterminate = 'off';
    wb.Message = 'Restoring the model...';
elseif isfield(storeOptions, 'undoCancelFcn')
    cancelFcn = storeOptions.undoCancelFcn;
end
tileDepth = obj.I{id}.labels.modelScaleFactors(end, 3);
slabSlices = max(1, floor(slabVoxels / max(1, size(data, 1) * size(data, 2))));
slabSlices = ceil(slabSlices / tileDepth) * tileDepth;
for z0 = 1:slabSlices:depth
    if z0 > 1 && cancelFcn()
        if ~isempty(wb)
            wb.Indeterminate = 'on';
            wb.Message = 'Cancelling: putting the model back as it was...';
            drawnow;
        end
        rollbackOptions = setOptions;
        rollbackOptions.z = storeOptions.z(1) + [0, z0 - 2];
        obj.I{id}.setData3D(redoData(:, :, 1:z0-1), type, storeOptions.t(1), storeOptions.orient, NaN, rollbackOptions);
        restored = false;
        return;
    end
    z1 = min(depth, z0 + slabSlices - 1);
    slabOptions = setOptions;
    slabOptions.z = storeOptions.z(1) + [z0, z1] - 1;
    obj.I{id}.setData3D(data(:, :, z0:z1), type, storeOptions.t(1), storeOptions.orient, NaN, slabOptions);
    if ~isempty(wb); wb.Value = z1 / depth; end
end
end

function restoreHistory(obj, historyBefore)
% put the undo history back as it was before this undo
obj.Backup.undoList = historyBefore.undoList;
obj.Backup.undoIndex = historyBefore.undoIndex;
obj.Backup.prevUndoIndex = historyBefore.prevUndoIndex;
obj.Backup.index3d = historyBefore.index3d;
end
