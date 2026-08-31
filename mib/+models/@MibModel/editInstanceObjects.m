function applied = editInstanceObjects(obj, BatchOptIn)
% EDITINSTANCEOBJECTS - Split, merge, connect and delete objects of an instance model.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.editInstanceObjects()
%       obj.editInstanceObjects(BatchOpt)
%       applied = obj.editInstanceObjects(BatchOpt)
%       obj.editInstanceObjects(NaN)     % return the available options
%
% The editing operations behind ``controllers.InstanceEditor``. Automatic 2D to
% 3D stitching (``utils.instances.stitch2Dto3D``) leaves errors that no threshold
% can remove - objects fused across many slices, one object carrying two indices
% - and this is how they are repaired by hand.
%
% Every per-object action is confined to the bounding boxes held in
% ``MibDataset.instanceIndex``: the volume is read, backed up and written only
% inside them, so the cost of an edit is the size of the object rather than the
% size of the dataset. The index is refreshed over the same region afterwards.
%
% Input Arguments:
%   - **BatchOptIn** - *(optional)* structure with the fields below; ``NaN``
%     triggers the ``SyncBatch`` event with the defaults instead of running:
%
%     - ``.Action`` - cell, the operation:
%
%       - ``'Merge'`` - the selected objects become one, taking the **smallest**
%         of their indices; the others are freed
%       - ``'SplitComponents'`` - each object is broken into its connected
%         components; the largest keeps the index, the rest get new ones
%       - ``'SplitBySelection'`` - the voxels of the Selection layer are cleared
%         from the object first, then it is split into connected components. One
%         undo step for the brush workflow: draw the break, interpolate it, split
%       - ``'CutAtSlice'`` - voxels at or beyond the shown slice take a new index
%       - ``'Connect'`` - bridge the Z gap between two objects and merge them
%       - ``'Delete'`` - remove the objects
%       - ``'Cleanup'`` - apply the noise filters to the whole model
%       - ``'Compact'`` - renumber every object to a contiguous 1..N
%
%     - ``.ObjectIndices`` - char, comma-separated object indices to act on, e.g.
%       ``'7, 12'``. Ignored by ``Cleanup`` and ``Compact``
%     - ``.Mode3D`` - logical, operate on the whole volume (default) or only on
%       the shown slice
%     - ``.Connectivity`` - cell, ``'26'``/``'6'`` in 3D, ``'8'``/``'4'`` in 2D. A
%       value belonging to the other mode is translated rather than rejected
%     - ``.ConnectMode`` - cell, how ``Connect`` fills the gap:
%
%       - ``'interpolate'`` - shape-interpolate between the two facing
%         cross-sections (``utils.interpolateShapes``)
%       - ``'selection'`` - use the current Selection layer as the bridge
%
%     - ``.MinObjectVoxels`` / ``.MinObjectSlices`` / ``.AbsorbFragmentVoxels`` -
%       thresholds for ``Cleanup``; see ``utils.instances.cleanup``
%     - ``.showWaitbar`` - logical, show a progress dialog for the two whole-volume
%       actions. The per-object actions are sub-second by design and never show one
%     - ``.id`` - *(optional)* dataset index 1-9; default = active dataset
%
% Output Arguments:
%   - **applied** - logical, true when the model was actually changed. Every
%     rejection path (wrong model type, nothing selected, an index that is not in
%     the model, a cut outside the object, a cancelled cleanup) reports to the
%     user and returns false, so a caller can tell "done" from "declined" instead
%     of assuming the edit went through and updating its own state to match.
%
% .. note::
%    Only 65535 and 4294967295 model types on ``Standard`` datasets are handled.
%    A model with 63 or 255 materials has no per-object identity to edit, and
%    ``BigData`` labels are bit-packed at 63 materials so they cannot hold an
%    instance model at all.
%
% Usage:
%   **Example 1** - merge objects 12 and 7; the result is object 7
%
%   .. code-block:: matlab
%
%      BatchOpt.Action = {'Merge'};
%      BatchOpt.ObjectIndices = '7, 12';
%      obj.mibModel.editInstanceObjects(BatchOpt);
%
%   **Example 2** - the brush workflow: break drawn into the Selection layer
%
%   .. code-block:: matlab
%
%      BatchOpt.Action = {'SplitBySelection'};
%      BatchOpt.ObjectIndices = '537';
%      obj.mibModel.editInstanceObjects(BatchOpt);
%
% See also: utils.instances.objectIndex, utils.instances.cleanup,
% core.MibDataset.buildInstanceIndex, models.MibModel.stitchModelInstances

% Updates
%

if nargin < 2; BatchOptIn = struct(); end
applied = false;   % stays false on every rejection path below

%% Declaration of the BatchOpt structure
BatchOpt = struct();
BatchOpt.Action = {'Merge'};
BatchOpt.Action{2} = {'Merge', 'SplitComponents', 'SplitBySelection', 'CutAtSlice', ...
    'Connect', 'Delete', 'Cleanup', 'Compact'};
BatchOpt.ObjectIndices = '';
BatchOpt.Mode3D = true;
BatchOpt.Connectivity = {'26'};
BatchOpt.Connectivity{2} = {'26', '6', '8', '4'};
BatchOpt.ConnectMode = {'interpolate'};
BatchOpt.ConnectMode{2} = {'interpolate', 'selection'};
BatchOpt.MinObjectVoxels = {0, [0, 1e9], 'on'};
BatchOpt.MinObjectSlices = {0, [0, 1e6], 'on'};
BatchOpt.AbsorbFragmentVoxels = {5, [0, 1e6], 'on'};
BatchOpt.showWaitbar = true;
BatchOpt.id = obj.getActiveId();

BatchOpt.mibBatchSectionName = 'Ribbon -> Model';
BatchOpt.mibBatchActionName  = 'Instance editor';

BatchOpt.mibBatchTooltip.Action = 'Operation to apply. Merge: the selected objects become one and take the smallest of their indices. Split into components: each object is broken into its connected pieces, the largest keeping the index. Split by selection: clear the Selection layer out of the object first, then split - use after brushing a break. Cut at slice: everything from the shown slice onwards becomes a new object. Connect: fill the Z gap between two objects and join them. Delete: remove the objects. Cleanup: apply the noise filters to the whole model. Compact: renumber every object to 1..N';
BatchOpt.mibBatchTooltip.ObjectIndices = 'Comma-separated indices of the objects to act on, for example "7, 12". Not used by Cleanup and Compact';
BatchOpt.mibBatchTooltip.Mode3D = 'Act on the whole 3D object. When off, only the shown slice is affected - splitting then gives every slice of the object its own index';
BatchOpt.mibBatchTooltip.Connectivity = 'Voxel connectivity used when splitting into components: 26 or 6 in 3D, 8 or 4 in 2D. The lower value keeps pieces apart that touch only at a corner or an edge';
BatchOpt.mibBatchTooltip.ConnectMode = 'How Connect fills the gap between two objects. "interpolate": morph between the two facing cross-sections. "selection": use whatever is currently in the Selection layer as the bridge, for a gap whose shape cannot be guessed. Either way only background voxels are written, so a third object in the way is never overwritten';
BatchOpt.mibBatchTooltip.MinObjectVoxels = 'Cleanup: delete objects smaller than this many voxels. 0 = keep all';
BatchOpt.mibBatchTooltip.MinObjectSlices = 'Cleanup: delete objects occupying this many Z-slices or fewer. 0 = keep all, 1 = drop single-slice objects. Catches large in-plane false detections that a voxel threshold cannot reach';
BatchOpt.mibBatchTooltip.AbsorbFragmentVoxels = 'Cleanup: hand any object of this size or smaller to the object surrounding it in-plane. 0 = off. This moves voxels rather than deleting them, so it fills the holes that stray predictor pixels punch into otherwise solid objects';
BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during Cleanup and Compact';

%% Batch mode check actions
batchModeSwitch = 0;
if isstruct(BatchOptIn) == 0
    if isscalar(BatchOptIn) && isnan(BatchOptIn)
        BatchOpt = rmfield(BatchOpt, 'id');
        notify(obj, 'SyncBatch', core.ToggleEventData(BatchOpt));
    else
        ErrorDlgOpt.winTitle = 'BatchOpt Error';
        ErrorDlgOpt.optionalPrefix = 'Error in MibModel.editInstanceObjects';
        ErrorDlgOpt.err = 'A structure as the 2nd parameter is required!';
        ErrorDlgOpt.WindowHeight = 150;
        notify(obj, 'ShowErrorDialog', core.ToggleEventData(ErrorDlgOpt));
    end
    return;
else
    BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    if isfield(BatchOptIn, 'mibBatchTooltip'); batchModeSwitch = 1; end
end

id = BatchOpt.id;
dataset = obj.I{id};
action = BatchOpt.Action{1};

%% Guards
if ~iGuard(obj, dataset)
    return;
end

%% Object index cache
% Every per-object action reads a bounding box out of it, so a missing or stale
% index has to be rebuilt first - acting on a stale box edits the wrong voxels.
timePoint = dataset.getCurrentTimePoint();
index = dataset.instanceIndex;
if isempty(index) || ~isfield(index, 'stale') || index.stale || ...
        ~isequal(index.timePoint, timePoint)
    wbIndex = [];
    if BatchOpt.showWaitbar
        wbIndex = uiprogressdlg(obj.getProgressBarParent(), 'Indeterminate', 'on', ...
            'Message', 'Indexing the objects of the model, please wait...', ...
            'Title', 'Instance editor', 'Cancelable', 'on');
    end
    [index, cancelled] = dataset.buildInstanceIndex(struct('timePoint', timePoint), wbIndex);
    if ~isempty(wbIndex); delete(wbIndex); end
    if cancelled || isempty(index); notify(obj, 'StopProtocol'); return; end
end

%% Objects to act on
wholeModelAction = ismember(action, {'Cleanup', 'Compact'});
objectIds = [];
if ~wholeModelAction
    objectIds = iParseIndices(BatchOpt.ObjectIndices);
    [objectIds, problem] = iValidateIndices(objectIds, index, action);
    if ~isempty(problem)
        iComplain(obj, problem, 'Instance editor');
        notify(obj, 'StopProtocol');
        return;
    end
end

%% Dispatch
switch action
    case {'Cleanup', 'Compact'}
        done = iWholeModelAction(obj, id, action, BatchOpt, batchModeSwitch);
    otherwise
        done = iObjectAction(obj, id, action, objectIds, index, timePoint, ...
            BatchOpt, batchModeSwitch);
end
if ~done; notify(obj, 'StopProtocol'); return; end
applied = true;

%% Refresh the widgets
notify(obj, 'UpdateGuiWidgets', core.ToggleEventData({'checkboxes'}));
notify(obj, 'ShowImage');
notify(obj, 'SyncBatch', core.ToggleEventData(rmfield(BatchOpt, 'id')));
end

% =====================================================================
function ok = iGuard(obj, dataset)
% Reject the dataset and model types this editor cannot work on, each with a
% message saying what to do instead. A silent return would report success for
% work that never happened.
ok = false;

if strcmp(dataset.datasetType, 'Virtual')
    iComplain(obj, 'Not available in virtual stacking mode!', 'Virtual mode', ...
        {'Instance editing requires memory-resident mode. Please switch to standard mode and try again.'});
    notify(obj, 'StopProtocol');
    return;
end
if dataset.datasetType(1) == 'B'
    iComplain(obj, 'Not available for BigData datasets!', 'BigData mode', ...
        {'BigData models are bit-packed at 63 materials and cannot hold an instance model.'});
    notify(obj, 'StopProtocol');
    return;
end
if dataset.enableSelection == 0
    iComplain(obj, 'The models are switched off!', 'Models are disabled', ...
        {'Please enable the "Enable selection" option in Preferences (Ribbon -> Home -> Preferences) and try again.'});
    notify(obj, 'StopProtocol');
    return;
end
if ~dataset.modelExist
    iComplain(obj, 'No model exists!', 'No model', ...
        {'Please load or create an instance model first.'});
    notify(obj, 'StopProtocol');
    return;
end
if dataset.labels.maxMaterials < 65535
    iComplain(obj, 'Not an instance model!', 'Wrong model type', ...
        {'The instance editor works on 65535 and 4294967295 model types, where every object has its own index.', ...
         'Convert the model first: Ribbon -> Model -> Convert type.'});
    notify(obj, 'StopProtocol');
    return;
end
ok = true;
end

% =====================================================================
function iComplain(obj, message, title, details)
% Tell the user why nothing happened.
%
% A message box needs a window to sit on. With none - a batch protocol, or a
% test - utils.dlgs.inputUniversalDlg still builds a modal dialog, and nothing
% is there to dismiss it: the session blocks until someone closes it by hand.
% So when there is no parent the message goes to the console instead. It still
% has to go *somewhere*: returning silently would report success for work that
% never happened.
if nargin < 4; details = {}; end

parent = obj.getProgressBarParent();
if isempty(parent) || ~all(isvalid(parent))
    fprintf(2, 'Instance editor: %s\n', message);
    for k = 1:numel(details)
        fprintf(2, '    %s\n', details{k});
    end
    return;
end

if isempty(details); details = {''}; end
dlgOpt.MsgBoxOnly  = true;
dlgOpt.Icon        = 'puffin_warning';
dlgOpt.HeaderLines = 1;
dlgOpt.mibPath     = obj.mibPath;
utils.dlgs.inputUniversalDlg(parent, message, {''}, details, title, dlgOpt);
end

% =====================================================================
function indices = iParseIndices(text)
% '7, 12' -> [7 12]. Accepts commas, semicolons and whitespace.
if isnumeric(text); indices = double(text(:))'; return; end
indices = str2double(strsplit(strtrim(text), {',', ';', ' '}));
indices = indices(~isnan(indices));
end

% =====================================================================
function [objectIds, problem] = iValidateIndices(objectIds, index, action)
% Every action has a minimum number of objects it can act on, and no action can
% act on an index that is not in the model.
problem = '';
objectIds = unique(objectIds(objectIds > 0));
if isempty(objectIds)
    problem = 'Select at least one object first.';
    return;
end
outOfRange = objectIds(objectIds > index.maxIndex);
if ~isempty(outOfRange)
    problem = sprintf('There is no object with index %d in this model.', outOfRange(1));
    return;
end
missing = objectIds(~index.exists(objectIds));
if ~isempty(missing)
    problem = sprintf('Object %d is not present in the model - the index may be out of date.', missing(1));
    return;
end
if ismember(action, {'Merge', 'Connect'}) && numel(objectIds) < 2
    problem = sprintf('%s needs at least two objects.', action);
    return;
end
if strcmp(action, 'Connect') && numel(objectIds) > 2
    problem = 'Connect works on exactly two objects.';
    return;
end
end

% =====================================================================
function connectivity = iConnectivity(BatchOpt)
% One dropdown serves both modes, so a value belonging to the other one is
% translated rather than rejected: 26 <-> 8 (full) and 6 <-> 4 (face only).
value = str2double(BatchOpt.Connectivity{1});
if BatchOpt.Mode3D
    switch value
        case {4, 6};   connectivity = 6;
        otherwise;     connectivity = 26;
    end
else
    switch value
        case {4, 6};   connectivity = 4;
        otherwise;     connectivity = 8;
    end
end
end

% =====================================================================
function box = iUnionBox(index, objectIds)
% Smallest box containing all of the given objects
boxes = double(index.bbox(objectIds, :));
box = [min(boxes(:, 1)), max(boxes(:, 2)), ...
       min(boxes(:, 3)), max(boxes(:, 4)), ...
       min(boxes(:, 5)), max(boxes(:, 6))];
end

% =====================================================================
function box = iClipToSlice(box, sliceNumber, use3D)
% In 2-D mode every read, write, backup and rescan is confined to one slice
if ~use3D
    box(5:6) = [sliceNumber, sliceNumber];
end
end

% =====================================================================
function options = iBoxOptions(box, id)
options = struct('blockModeSwitch', 0, 'id', id, ...
    'y', box(1:2), 'x', box(3:4), 'z', box(5:6));
end

% =====================================================================
function sub = iReadBox(obj, id, layer, timePoint, box)
sub = cell2mat(obj.getData3D(layer, timePoint, 3, NaN, iBoxOptions(box, id)));
end

% =====================================================================
function pixelIdxList = iCropToFull(obj, id, box, cropIndices, timePoint)
% Crop-local linear indices to indices into MibImage.data.
%
% convertPixelIdxListCrop2Full maps into the [height width depth] volume of one
% time point; obj.data is [height width depth 1 time], so anything past the
% first time point needs the frame offset added here. Without it a write on
% time point 2 would silently land on time point 1.
if isempty(cropIndices); pixelIdxList = []; return; end
pixelIdxList = obj.I{id}.convertPixelIdxListCrop2Full(cropIndices, ...
    struct('y', box(1:2), 'x', box(3:4), 'z', box(5:6)));
frameStride = obj.I{id}.image.height * obj.I{id}.image.width * obj.I{id}.image.depth;
pixelIdxList = pixelIdxList + (timePoint - 1) * frameStride;
end

% =====================================================================
function iWriteLabels(obj, id, pixelIdxList, value)
% Write one label value at a list of full-volume linear indices
if isempty(pixelIdxList); return; end
labelValues = zeros(numel(pixelIdxList), 1, obj.I{id}.labels.dataClass) + value;
obj.I{id}.setPixelIdxList('labels', labelValues, pixelIdxList);
end

% =====================================================================
function [newIds, problem] = iAllocateIndices(obj, id, index, count)
% Hand out unused label values, reusing gaps before extending the range.
%
% Deliberately not core.MibDataset.addMaterial: its large-model branch calls
% countMaterials(), which rescans every time point for its maximum. Splitting
% fifty objects would mean fifty full-volume scans.
newIds = [];
problem = '';
if count == 0; return; end

free = find(~index.exists);
free = free(:)';
if numel(free) >= count
    newIds = free(1:count);
else
    newIds = [free, index.maxIndex + (1:(count - numel(free)))];
end

capacity = obj.I{id}.labels.maxMaterials;
if any(newIds > capacity)
    newIds = [];
    problem = sprintf(['This model type holds at most %d objects and there is no free index left.\n' ...
        'Use "Compact" to renumber the objects and try again.'], capacity);
    return;
end

% The renderer looks the colour up by index, so a new index without a colour row
% would error on the next redraw.
colors = obj.I{id}.labels.materialColors;
highest = max(newIds);
if size(colors, 1) < highest
    colors(size(colors, 1)+1:highest, :) = rand(highest - size(colors, 1), 3);
    obj.I{id}.labels.materialColors = colors;
end
obj.I{id}.labels.materialsCount = max(obj.I{id}.labels.materialsCount, highest);
end

% =====================================================================
function done = iObjectAction(obj, id, action, objectIds, index, timePoint, BatchOpt, batchModeSwitch)
% The per-object operations. All of them read, back up, write and rescan inside
% one bounding box, which is what keeps them interactive on a large model.
done = false;
dataset = obj.I{id};
use3D = BatchOpt.Mode3D;
sliceNumber = dataset.getCurrentSliceNumber();

% Objects whose extent may change, and the region in which voxels change. Both
% start from the selection and are widened by the individual actions.
touchedIds = objectIds;
box = iClipToSlice(iUnionBox(index, objectIds), sliceNumber, use3D);

if use3D == false && (sliceNumber < min(index.bbox(objectIds, 5)) || ...
        sliceNumber > max(index.bbox(objectIds, 6)))
    iComplain(obj, 'None of the selected objects is present on the shown slice.', 'Instance editor');
    return;
end

% Work out everything that will be written before touching the dataset, so a
% problem is reported without half an edit having been applied.
writes = struct('pixelIdxList', {}, 'value', {});

switch action
    case 'Merge'
        % The smallest index wins, by definition of the operation.
        survivor = min(objectIds);
        for objectId = setdiff(objectIds, survivor)
            pixels = iObjectPixels(obj, id, index, objectId, timePoint, sliceNumber, use3D);
            writes(end+1) = struct('pixelIdxList', pixels, 'value', survivor); %#ok<AGROW>
        end

    case {'SplitComponents', 'SplitBySelection', 'CutAtSlice'}
        [writes, touchedIds, problem] = iPlanSplit(obj, id, action, objectIds, index, ...
            timePoint, sliceNumber, use3D, BatchOpt);
        if ~isempty(problem); iComplain(obj, problem, 'Instance editor'); return; end

    case 'Connect'
        [writes, box, problem] = iPlanConnect(obj, id, objectIds, index, timePoint, BatchOpt);
        if ~isempty(problem); iComplain(obj, problem, 'Instance editor'); return; end

    case 'Delete'
        for objectId = objectIds
            pixels = iObjectPixels(obj, id, index, objectId, timePoint, sliceNumber, use3D);
            writes(end+1) = struct('pixelIdxList', pixels, 'value', 0); %#ok<AGROW>
        end
end

if isempty(writes)
    iComplain(obj, 'There is nothing to change for this selection.', 'Instance editor');
    return;
end

%% Apply
% Undo covers only the affected box. A whole-volume snapshot would exhaust
% MibBackup's 3D step budget within a few clicks and stall each of them.
if ~batchModeSwitch
    obj.backup('labels', 1, iBoxOptions(box, id));
end
for w = 1:numel(writes)
    iWriteLabels(obj, id, writes(w).pixelIdxList, writes(w).value);
end

%% Repair the index over the same region
refresh = struct('timePoint', timePoint, 'objectIds', unique(touchedIds), 'bbox', box);
dataset.buildInstanceIndex(refresh);
done = true;
end

% =====================================================================
function pixels = iObjectPixels(obj, id, index, objectId, timePoint, sliceNumber, use3D)
% Full-volume linear indices of one object, found inside its own bounding box
box = iClipToSlice(double(index.bbox(objectId, :)), sliceNumber, use3D);
sub = iReadBox(obj, id, 'labels', timePoint, box);
pixels = iCropToFull(obj, id, box, find(sub == objectId), timePoint);
end

% =====================================================================
function [writes, touchedIds, problem] = iPlanSplit(obj, id, action, objectIds, index, timePoint, sliceNumber, use3D, BatchOpt)
% Plan the three splitting actions. They differ only in how the object is cut;
% the allocation of new indices is common.
writes = struct('pixelIdxList', {}, 'value', {});
touchedIds = objectIds;
problem = '';
connectivity = iConnectivity(BatchOpt);

% A split cannot reuse an index it is about to free, so allocation walks a
% working copy of the index that is updated as pieces are handed out.
workingIndex = index;

for objectId = objectIds
    box = iClipToSlice(double(index.bbox(objectId, :)), sliceNumber, use3D);
    sub = iReadBox(obj, id, 'labels', timePoint, box);
    objectMask = (sub == objectId);
    if ~any(objectMask, 'all'); continue; end

    switch action
        case 'CutAtSlice'
            if use3D == false
                problem = 'Cut at slice needs 3D mode - there is nothing to cut in a single slice.';
                return;
            end
            if sliceNumber <= box(5) || sliceNumber > box(6)
                problem = sprintf(['Object %d spans slices %d to %d.\n' ...
                    'Move to a slice inside it, past the first one, and try again.'], ...
                    objectId, box(5), box(6));
                return;
            end
            tail = false(size(objectMask));
            tail(:, :, (sliceNumber - box(5) + 1):end) = true;
            componentMasks = {objectMask & tail};

        case 'SplitBySelection'
            selection = iReadBox(obj, id, 'selection', timePoint, box);
            objectMask = objectMask & ~(selection > 0);
            if ~any(objectMask, 'all')
                problem = sprintf('The Selection layer covers the whole of object %d - nothing would be left.', objectId);
                return;
            end
            componentMasks = iComponentMasks(objectMask, connectivity, use3D);
            % the voxels taken out by the Selection go back to background
            removed = (sub == objectId) & ~objectMask;
            writes(end+1) = struct(...
                'pixelIdxList', iCropToFull(obj, id, box, find(removed), timePoint), ...
                'value', 0); %#ok<AGROW>

        otherwise   % SplitComponents
            componentMasks = iComponentMasks(objectMask, connectivity, use3D);
    end

    % iComponentMasks returns every component except the largest, which keeps
    % the original index and needs no write. Empty therefore means the object is
    % already a single piece and there is nothing to split. For SplitBySelection
    % the removal write queued above still stands.
    if isempty(componentMasks); continue; end

    [newIds, problem] = iAllocateIndices(obj, id, workingIndex, numel(componentMasks));
    if ~isempty(problem); return; end

    for k = 1:numel(componentMasks)
        writes(end+1) = struct(...
            'pixelIdxList', iCropToFull(obj, id, box, find(componentMasks{k}), timePoint), ...
            'value', newIds(k)); %#ok<AGROW>
    end
    touchedIds = [touchedIds, newIds]; %#ok<AGROW>

    % Reserve what was just handed out so the next object cannot be given the
    % same values.
    if max(newIds) > workingIndex.maxIndex
        workingIndex.exists(workingIndex.maxIndex+1:max(newIds), 1) = false;
        workingIndex.maxIndex = max(newIds);
    end
    workingIndex.exists(newIds) = true;
end
end

% =====================================================================
function componentMasks = iComponentMasks(objectMask, connectivity, use3D)
% Connected components of an object, minus the largest one - which keeps the
% original index and therefore needs no write at all.
%
% In 2-D mode the components are found slice by slice, so every slice's profile
% becomes its own object; that is also how an over-merged 3D object is exploded
% back into per-slice pieces.
componentMasks = {};
regions = {};
if use3D
    components = bwconncomp(objectMask, connectivity);
    regions = components.PixelIdxList;
    sizeOfMask = size(objectMask);
else
    sizeOfMask = size(objectMask);
    stride = sizeOfMask(1) * sizeOfMask(2);
    for z = 1:size(objectMask, 3)
        planeComponents = bwconncomp(objectMask(:, :, z), connectivity);
        for c = 1:planeComponents.NumObjects
            regions{end+1} = planeComponents.PixelIdxList{c} + (z - 1) * stride; %#ok<AGROW>
        end
    end
end
if numel(regions) < 2; return; end

[~, order] = sort(cellfun(@numel, regions), 'descend');
for k = 2:numel(order)                    % skip the largest
    mask = false(sizeOfMask);
    mask(regions{order(k)}) = true;
    componentMasks{end+1} = mask; %#ok<AGROW>
end
end

% =====================================================================
function [writes, box, problem] = iPlanConnect(obj, id, objectIds, index, timePoint, BatchOpt)
% Bridge the gap between two objects and merge them.
%
% The bridge is written only where the model is currently background, so a third
% object lying between the two is never overwritten. The survivor is the smaller
% index, as for a plain merge.
writes = struct('pixelIdxList', {}, 'value', {});
problem = '';
survivor = min(objectIds);
other = max(objectIds);
box = iUnionBox(index, objectIds);

boxA = double(index.bbox(objectIds(1), :));
boxB = double(index.bbox(objectIds(2), :));
overlapInZ = boxA(5) <= boxB(6) && boxB(5) <= boxA(6);

if ~overlapInZ
    if boxA(6) < boxB(5)
        lower = objectIds(1); upper = objectIds(2);
        zLower = boxA(6);     zUpper = boxB(5);
    else
        lower = objectIds(2); upper = objectIds(1);
        zLower = boxB(6);     zUpper = boxA(5);
    end
    bridgeBox = [box(1:4), zLower, zUpper];
    labelsInBridge = iReadBox(obj, id, 'labels', timePoint, bridgeBox);

    switch BatchOpt.ConnectMode{1}
        case 'selection'
            selection = iReadBox(obj, id, 'selection', timePoint, bridgeBox);
            bridge = selection > 0;
            if ~any(bridge, 'all')
                problem = 'The Selection layer is empty - draw the bridging area first, or use the "interpolate" mode.';
                return;
            end

        otherwise   % interpolate
            bridge = false(size(labelsInBridge));
            bridge(:, :, 1)   = labelsInBridge(:, :, 1) == lower;
            bridge(:, :, end) = labelsInBridge(:, :, end) == upper;
            % utils.interpolateShapes morphs between the two annotated planes and
            % fills everything in between.
            bridge = utils.interpolateShapes(uint8(bridge)) > 0;
    end

    % Background only. This is the guard that makes Connect safe to use in a
    % crowded volume - without it the interpolated tube would carve through
    % whatever happens to lie between the two objects.
    bridge = bridge & (labelsInBridge == 0);
    writes(end+1) = struct(...
        'pixelIdxList', iCropToFull(obj, id, bridgeBox, find(bridge), timePoint), ...
        'value', survivor);
end

% Whether or not a bridge was needed, the two objects become one.
pixels = iObjectPixels(obj, id, index, other, timePoint, 0, true);
writes(end+1) = struct('pixelIdxList', pixels, 'value', survivor);
end

% =====================================================================
function done = iWholeModelAction(obj, id, action, BatchOpt, batchModeSwitch)
% Cleanup and Compact rewrite the whole volume, so unlike the per-object actions
% they get a cancelable progress dialog and a full index rebuild.
done = false;
dataset = obj.I{id};
timePoint = dataset.getCurrentTimePoint();

wb = [];
if BatchOpt.showWaitbar
    wb = uiprogressdlg(obj.getProgressBarParent(), 'Indeterminate', 'on', ...
        'Message', 'Working on the model, please wait...', ...
        'Title', sprintf('Instance editor - %s', action), 'Cancelable', 'on');
end

if ~batchModeSwitch
    obj.backup('labels', 1, struct('id', id));
end

switch action
    case 'Cleanup'
        readOptions = struct('blockModeSwitch', 0, 'id', id);
        volume = cell2mat(obj.getData3D('labels', timePoint, 3, NaN, readOptions));

        cleanupOptions.absorbFragmentVoxels = BatchOpt.AbsorbFragmentVoxels{1};
        cleanupOptions.minObjectVoxels = BatchOpt.MinObjectVoxels{1};
        cleanupOptions.minObjectSlices = BatchOpt.MinObjectSlices{1};
        % compact = false: a user who has been working with object 1299 must
        % still find it under that number afterwards. Renumbering is a separate,
        % explicit action.
        cleanupOptions.compact = false;
        [cleaned, stats, cancelled] = utils.instances.cleanup(volume, cleanupOptions, wb);
        if cancelled
            if ~isempty(wb); delete(wb); end
            fprintf('Instance editor: cleanup cancelled, the model was not changed\n');
            return;
        end
        obj.setData3D(cast(cleaned, 'like', volume), 'labels', timePoint, 3, [], readOptions);
        fprintf('Instance editor: cleanup removed %d objects, absorbed %d fragments (%d voxels); %d objects left\n', ...
            stats.numRemoved, stats.numAbsorbedFragments, stats.numAbsorbedVoxels, stats.numObjects);

    case 'Compact'
        dataset.labels.squeezeMaterialLabels(wb);
end

if ~isempty(wb); delete(wb); end

% The whole label space has moved; nothing of the old index survives.
dataset.instanceIndex = [];
dataset.buildInstanceIndex(struct('timePoint', timePoint));
done = true;
end
