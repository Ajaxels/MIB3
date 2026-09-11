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
%         of their indices; the others are freed. With ``ObjectIndices`` empty
%         the objects are taken from the Selection layer - draw one shape across
%         them all, and the background under that shape joins the survivor too,
%         so the stroke closes the gap it was drawn across. In ``Mode3D`` a
%         shape covering nothing reaches one slice beyond either end of itself,
%         which is how a gap along Z is closed: see ``localObjectsToJoin``. A drawing
%         that reaches fewer than two objects is not a failed merge but the same
%         gesture over a smaller region, so it falls through to the two below:
%         over nothing it becomes an object, over one object it joins that
%         object. The rule is one rule - *the drawing belongs to the surviving
%         object* - whatever it happens to reach
%       - ``'AddObject'`` - the voxels of the Selection layer take the next free
%         index, so the drawing becomes a new object. ``ObjectIndices`` is not
%         used
%       - ``'AddToObject'`` - the voxels of the Selection layer are given to the
%         one object in ``ObjectIndices``, which grows by the drawing
%       - ``'SplitComponents'`` - each object is broken into its connected
%         components; the largest keeps the index, the rest get new ones
%       - ``'SplitBySelection'`` - the voxels of the Selection layer are cleared
%         from the object first, then it is split into connected components. One
%         undo step for the brush workflow: draw the break, interpolate it, split.
%         With ``ObjectIndices`` empty the objects are taken from the drawing
%         itself - everything it covers is split
%       - ``'CutAtSlice'`` - voxels at or beyond the shown slice take a new index
%       - ``'Connect'`` - bridge between two objects and merge them. Needs
%         ``Mode3D``; the merge is the same one ``Merge`` performs. With
%         ``ObjectIndices`` empty it *is* a drawing-driven ``Merge``, down to the
%         same code - ``ConnectMode`` is not consulted, the drawing being the
%         bridge already. The two buttons differ only when objects are named
%       - ``'Delete'`` - remove the objects
%       - ``'Cleanup'`` - apply the noise filters to the whole model
%       - ``'Compact'`` - renumber every object to a contiguous 1..N
%
%     - ``.ObjectIndices`` - char, comma-separated object indices to act on, e.g.
%       ``'7, 12'``. Ignored by ``Cleanup``, ``Compact`` and ``AddObject``, and
%       exactly one index for ``AddToObject``. Empty is an error everywhere except
%       ``Merge``, ``SplitBySelection`` and ``Connect``, where it means "whatever
%       the Selection layer covers" - and for ``Connect``, what it lies between;
%       the drawing is cleared afterwards, having been used
%     - ``.Mode3D`` - logical, operate on the whole volume (default) or only on
%       the shown slice
%     - ``.Connectivity`` - cell, ``'26'``/``'6'`` in 3D, ``'8'``/``'4'`` in 2D. A
%       value belonging to the other mode is translated rather than rejected
%     - ``.ConnectMode`` - cell, how ``Connect`` builds the bridge:
%
%       - ``'interpolate'`` - shape-interpolate between the two facing
%         cross-sections (``utils.interpolateShapes``). Needs a gap in Z, having
%         to have two faces to morph between
%       - ``'selection'`` - use the current Selection layer as the bridge. Takes
%         the same path as a drawing-driven ``Merge`` and needs no gap, so it
%         also joins two objects that share a Z range but never touch
%
%     - ``.cleanupMinObjectVoxels`` / ``.cleanupMinObjectSlices`` /
%       ``.cleanupAbsorbFragmentVoxels`` - thresholds for ``Cleanup``, which is
%       the only action that reads them; see ``utils.instances.cleanup``. The
%       prefix keeps them apart from the identically-purposed
%       ``MinObjectVoxels`` of ``models.MibModel.stitchModelInstances``, which
%       are that method's own and are set in its own dialog
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
%   **Example 1** - merge objects 12 and 7; the result is object 7. Without
%   ``ObjectIndices`` everything the Selection layer covers is merged instead
%
%   .. code-block:: matlab
%
%      BatchOpt.Action = {'Merge'};
%      BatchOpt.ObjectIndices = '7, 12';
%      obj.mibModel.editInstanceObjects(BatchOpt);
%
%   **Example 2** - the brush workflow: break drawn into the Selection layer.
%   Without ``ObjectIndices`` the drawing says what to cut; naming an object
%   restricts the cut to it, for a line that clips a neighbour
%
%   .. code-block:: matlab
%
%      BatchOpt.Action = {'SplitBySelection'};
%      obj.mibModel.editInstanceObjects(BatchOpt);
%
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
BatchOpt.Action{2} = {'Merge', 'AddObject', 'AddToObject', 'SplitComponents', 'SplitBySelection', ...
    'CutAtSlice', 'Connect', 'Delete', 'Cleanup', 'Compact'};
BatchOpt.ObjectIndices = '';
BatchOpt.Mode3D = true;
BatchOpt.Connectivity = {'26'};
BatchOpt.Connectivity{2} = {'26', '6', '8', '4'};
BatchOpt.ConnectMode = {'interpolate'};
BatchOpt.ConnectMode{2} = {'interpolate', 'selection'};
BatchOpt.cleanupMinObjectVoxels = {0, [0, 1e9], 'on'};
BatchOpt.cleanupMinObjectSlices = {0, [0, 1e6], 'on'};
BatchOpt.cleanupAbsorbFragmentVoxels = {5, [0, 1e6], 'on'};
BatchOpt.showWaitbar = true;
BatchOpt.id = obj.getActiveId();

BatchOpt.mibBatchSectionName = 'Ribbon -> Model';
BatchOpt.mibBatchActionName  = 'Instance editor';

BatchOpt.mibBatchTooltip.Action = 'Operation to apply. Merge: the selected objects become one and take the smallest of their indices; with nothing selected the drawing decides, and the background under it joins the survivor - over one object it grows that object, over none it becomes a new one. Add object: the drawing in the Selection layer takes the next free index. Add to object: the drawing is given to the single object in Object indices. Split into components: each object is broken into its connected pieces, the largest keeping the index. Split by selection: clear the Selection layer out of the object first, then split - use after brushing a break. Cut at slice: everything from the shown slice onwards becomes a new object. Connect: fill the Z gap between two objects and join them. Delete: remove the objects. Cleanup: apply the noise filters to the whole model. Compact: renumber every object to 1..N';
BatchOpt.mibBatchTooltip.ObjectIndices = 'Comma-separated indices of the objects to act on, for example "7, 12". Not used by Cleanup and Compact. Leave it empty with "Merge" or "Split by selection" to act on whatever the Selection layer covers';
BatchOpt.mibBatchTooltip.Mode3D = 'Act on the whole 3D object. When off, only the shown slice is affected - splitting then gives every slice of the object its own index';
BatchOpt.mibBatchTooltip.Connectivity = 'Voxel connectivity used when splitting into components: 26 or 6 in 3D, 8 or 4 in 2D. The lower value keeps pieces apart that touch only at a corner or an edge';
BatchOpt.mibBatchTooltip.ConnectMode = 'How Connect bridges two objects. "interpolate": morph between the two facing cross-sections, which needs a gap in Z to have two faces to work from. "selection": use whatever is currently in the Selection layer as the bridge, for a gap whose shape cannot be guessed, or for two objects that share a Z range but never touch. Either way only background voxels are written, so a third object in the way is never overwritten';
BatchOpt.mibBatchTooltip.cleanupMinObjectVoxels = 'Cleanup: delete objects smaller than this many voxels. 0 = keep all';
BatchOpt.mibBatchTooltip.cleanupMinObjectSlices = 'Cleanup: delete objects occupying this many Z-slices or fewer. 0 = keep all, 1 = drop single-slice objects. Catches large in-plane false detections that a voxel threshold cannot reach';
BatchOpt.mibBatchTooltip.cleanupAbsorbFragmentVoxels = 'Cleanup: hand any object of this size or smaller to the object surrounding it in-plane. 0 = off. This moves voxels rather than deleting them, so it fills the holes that stray predictor pixels punch into otherwise solid objects';
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
if ~localGuard(obj, dataset)
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
derivedFromDrawing = false;
if ~wholeModelAction && ~strcmp(action, 'AddObject')
    objectIds = localParseIndices(BatchOpt.ObjectIndices);
    % All three of these are gestures over a region, and the region already says
    % which objects it means: the drawing is the cut for Split by selection, the
    % choice of objects for Merge, and the bridge for Connect. So with nothing
    % named, the drawing decides. Naming objects anyway restricts the action to
    % them, which is what a line clipping a neighbour needs. Add an action here
    % to give it the same form; every one of them is validated the same way below.
    if isempty(objectIds) && ismember(action, {'Merge', 'SplitBySelection', 'Connect'})
        if strcmp(action, 'SplitBySelection')
            % A cut is what the drawing *covers*, and nothing else: voxels it
            % merely lies against are not being removed from anything.
            [objectIds, problem, details] = localObjectsUnderSelection(obj, id, dataset, timePoint, BatchOpt.Mode3D);
        elseif strcmp(action, 'Connect') && ~BatchOpt.Mode3D
            problem = 'Connect needs 3D mode - a gap along Z cannot be bridged inside a single slice.';
            details = {};
        else
            % Joining is what the drawing *reaches*, which in 3D includes the
            % slice beyond either end of it - see localObjectsToJoin.
            [objectIds, problem, details] = localObjectsToJoin(obj, id, dataset, timePoint, BatchOpt.Mode3D);

            % With the objects in hand there is nothing of Connect's own left to
            % do: joining them and giving them the background drawn between them
            % is a drawing-driven Merge exactly - the same two writes in the
            % other order - so it takes that path rather than localPlanConnect, and
            % the ConnectMode dropdown is left alone instead of being switched
            % to 'selection' behind the user. The BatchOpt that goes out on
            % SyncBatch still says Connect, so replaying the protocol lands here
            % again and produces the same thing.
            action = 'Merge';
        end

        % Something was drawn, but on nothing. What that means depends on the
        % action: there is nothing to cut, but "make this one object" still
        % reads perfectly well when the region is empty - and that is what MIB's
        % own 'a' does to a material, so the key keeps its meaning here.
        if isempty(problem) && isempty(objectIds)
            if strcmp(action, 'Merge')
                action = 'AddObject';
            else
                problem = 'The Selection layer does not cover any object.';
                details = {'Draw across the object to be split, not beside it.'};
            end
        end
        if isempty(problem) && strcmp(action, 'Merge') && isscalar(objectIds)
            % One object under the drawing is not a merge that came up short: it
            % is the same gesture again, "this region belongs to that object",
            % so the drawn voxels join it.
            action = 'AddToObject';
        end
        if ~isempty(problem)
            localComplain(obj, problem, 'Instance editor', details);
            notify(obj, 'StopProtocol');
            return;
        end
        derivedFromDrawing = true;
    end
    if ~strcmp(action, 'AddObject')
        [objectIds, problem] = localValidateIndices(objectIds, index, action);
        if ~isempty(problem)
            localComplain(obj, problem, 'Instance editor');
            notify(obj, 'StopProtocol');
            return;
        end
    end
end

% Objects named and nothing drawn anywhere: the pick *is* the selection. The
% editor paints the picked objects into the Selection layer to highlight them, so
% what is on screen is the same picture as a drawing covering the whole of an
% object - which subtracts the whole of it. Leaving this case to fall through to
% a split that finds nothing to cut was the one reading that matched neither the
% screen nor the meaning 's' carries, and it already contradicted the refusal
% message for the empty case, which offers picking as the alternative to drawing.
% The highlight is released before any operation runs, so the layer really is
% empty here rather than holding the objects being asked about.
if strcmp(action, 'SplitBySelection') && ~derivedFromDrawing && ...
        isempty(localDrawingExtent(obj, id, dataset, timePoint, BatchOpt.Mode3D))
    action = 'Delete';
end

%% Dispatch
% The drawing is used up whenever the operation used it: as the cut, as the
% bridge, to say which objects were meant, or as the new object itself.
consumesSelection = derivedFromDrawing || ...
    ismember(action, {'SplitBySelection', 'AddObject', 'AddToObject'}) || ...
    (strcmp(action, 'Connect') && strcmp(BatchOpt.ConnectMode{1}, 'selection'));

switch action
    case {'Cleanup', 'Compact'}
        done = localWholeModelAction(obj, id, action, BatchOpt, batchModeSwitch);
    case {'AddObject', 'AddToObject'}
        % An empty target means "a new index"; the two differ in nothing else.
        target = [];
        if strcmp(action, 'AddToObject'); target = objectIds; end
        done = localDrawingToObject(obj, id, dataset, index, timePoint, BatchOpt, ...
            batchModeSwitch, consumesSelection, target);
    otherwise
        done = localObjectAction(obj, id, action, objectIds, index, timePoint, ...
            BatchOpt, batchModeSwitch, consumesSelection);
end
if ~done; notify(obj, 'StopProtocol'); return; end
applied = true;

%% Refresh the widgets
notify(obj, 'UpdateGuiWidgets', core.ToggleEventData({'checkboxes'}));
notify(obj, 'ShowImage');
notify(obj, 'SyncBatch', core.ToggleEventData(rmfield(BatchOpt, 'id')));
end

% =====================================================================
function ok = localGuard(obj, dataset)
% Reject the dataset and model types this editor cannot work on, each with a
% message saying what to do instead. A silent return would report success for
% work that never happened.
ok = false;

if strcmp(dataset.datasetType, 'Virtual')
    localComplain(obj, 'Not available in virtual stacking mode!', 'Virtual mode', ...
        {'Instance editing requires memory-resident mode. Please switch to standard mode and try again.'});
    notify(obj, 'StopProtocol');
    return;
end
if dataset.datasetType(1) == 'B'
    localComplain(obj, 'Not available for BigData datasets!', 'BigData mode', ...
        {'BigData models are bit-packed at 63 materials and cannot hold an instance model.'});
    notify(obj, 'StopProtocol');
    return;
end
if dataset.enableSelection == 0
    localComplain(obj, 'The models are switched off!', 'Models are disabled', ...
        {'Please enable the "Enable selection" option in Preferences (Ribbon -> Home -> Preferences) and try again.'});
    notify(obj, 'StopProtocol');
    return;
end
if ~dataset.modelExist
    localComplain(obj, 'No model exists!', 'No model', ...
        {'Please load or create an instance model first.'});
    notify(obj, 'StopProtocol');
    return;
end
if dataset.labels.maxMaterials < 65535
    localComplain(obj, 'Not an instance model!', 'Wrong model type', ...
        {'The instance editor works on 65535 and 4294967295 model types, where every object has its own index.', ...
         'Convert the model first: Ribbon -> Model -> Convert type.'});
    notify(obj, 'StopProtocol');
    return;
end
ok = true;
end

% =====================================================================
function localComplain(obj, message, title, details)
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
dlgOpt.HeaderLines = 2;
dlgOpt.mibPath     = obj.mibPath;
utils.dlgs.inputUniversalDlg(parent, message, {''}, details, title, dlgOpt);
end

% =====================================================================
function localReport(obj, message, title, details, allowDialog)
% Tell the user what an operation did.
%
% The counterpart of localComplain for a result rather than a refusal. Compact is
% the reason it exists: it rewrites every number the user has been navigating by
% and changes nothing they can see, so a line in the command window behind the
% application window is not where that belongs.
%
% It carries the same parent guard, for the same reason - with no window, a
% batch protocol or the test suite would get a modal dialog and nothing to
% dismiss it - and two differences from localComplain:
%
% - the fallback goes to **stdout**, not stderr: work done is not an error, and
%   the tests read the figures from there
% - a caller running under a batch protocol passes ``allowDialog`` false, so a
%   protocol looping over datasets is not stopped by a box per iteration
%
% Input Arguments:
%   - **allowDialog** - logical, false forces the console even when a parent
%     window exists
if nargin < 5; allowDialog = true; end
if nargin < 4; details = {}; end

parent = obj.getProgressBarParent();
if ~allowDialog || isempty(parent) || ~all(isvalid(parent))
    fprintf('Instance editor: %s\n', message);
    for k = 1:numel(details)
        fprintf('    %s\n', details{k});
    end
    return;
end

if isempty(details); details = {''}; end
dlgOpt.MsgBoxOnly  = true;
dlgOpt.Icon        = 'puffin_info';
dlgOpt.HeaderLines = 1;
dlgOpt.mibPath     = obj.mibPath;
utils.dlgs.inputUniversalDlg(parent, message, {''}, details, title, dlgOpt);
end

% =====================================================================
function indices = localParseIndices(text)
% '7, 12' -> [7 12]. Accepts commas, semicolons and whitespace.
if isnumeric(text); indices = double(text(:))'; return; end
indices = str2double(strsplit(strtrim(text), {',', ';', ' '}));
indices = indices(~isnan(indices));
end

% =====================================================================
function [box, drawn] = localDrawingExtent(obj, id, dataset, timePoint, use3D)
% Where the drawing is, and what it is.
%
% The single definition of "the region the user drew", shared by everything that
% takes the Selection layer as input: which objects it covers
% (``localObjectsUnderSelection``), the object it becomes (``localDrawingToObject``) and
% the background it hands to a merge or a bridge (``localAbsorbDrawing``). Each of
% those had its own copy, and they had already drifted - one narrowed to the
% slices carrying the drawing, the other to its full box.
%
% The only read in this file that is not confined to a bounding box, and it is
% affordable because the extent is found by reduction rather than by find(): on
% a 1078x1380x101 stack the any() passes cost 3 ms against 83 ms for a find()
% across the whole volume, and everything downstream is then proportional to the
% box. The Z range is left off the read so it keeps the copy-on-write fast path
% of getData3D instead of duplicating the layer.
%
% Input Arguments:
%   - **use3D** - logical, whole volume or the shown slice only
%
% Output Arguments:
%   - **box** - ``[y1 y2 x1 x2 z1 z2]`` of the drawn voxels, or ``[]`` when
%     nothing is drawn
%   - **drawn** - logical array, the drawing cropped to ``box``
box = [];
drawn = [];

readOptions = struct('blockModeSwitch', 0, 'id', id);
zOffset = 0;
if ~use3D
    sliceNumber = dataset.getCurrentSliceNumber();
    readOptions.z = [sliceNumber, sliceNumber];
    zOffset = sliceNumber - 1;
end
selectionVolume = cell2mat(obj.getData3D('selection', timePoint, 3, NaN, readOptions));

rowsUsed = find(any(any(selectionVolume, 2), 3));
if isempty(rowsUsed); return; end
colsUsed   = find(any(any(selectionVolume, 1), 3));
planesUsed = find(any(any(selectionVolume, 1), 2));

box = [rowsUsed(1), rowsUsed(end), colsUsed(1), colsUsed(end), ...
       zOffset + planesUsed(1), zOffset + planesUsed(end)];
drawn = selectionVolume(rowsUsed(1):rowsUsed(end), colsUsed(1):colsUsed(end), ...
    planesUsed(1):planesUsed(end)) > 0;
end

% =====================================================================
function [writes, box] = localAbsorbDrawing(obj, id, dataset, timePoint, use3D, value)
% Give the drawn background voxels to an object.
%
% The shared half of two gestures that used to be written out twice: a Merge
% whose objects came from the drawing closes the gap it was drawn across, and
% Connect in ``selection`` mode bridges with a shape drawn by hand. Both are
% "this background belongs to that object", and they now differ only in how the
% object was chosen.
%
% **Background only.** A voxel already carrying a label is left alone, so
% neither gesture can carve through an object lying under the stroke. For Merge
% that costs nothing - everything labelled under the drawing is being merged
% anyway - and for Connect it is the guard that makes it safe in a crowded
% volume.
%
% Output Arguments:
%   - **writes** - one entry, or none when there is no background to give
%   - **box** - extent of the drawing, ``[]`` when nothing is drawn. Returned
%     whether or not anything is written, so the caller can tell "nothing was
%     drawn" from "everything drawn is already an object"
writes = struct('pixelIdxList', {}, 'value', {});
[box, drawn] = localDrawingExtent(obj, id, dataset, timePoint, use3D);
if isempty(box); return; end

free = drawn & (localReadBox(obj, id, 'labels', timePoint, box) == 0);
if ~any(free, 'all'); return; end

writes(end+1) = struct(...
    'pixelIdxList', localCropToFull(obj, id, box, find(free), timePoint), ...
    'value', value);
end

% =====================================================================
function [objectIds, problem, details] = localObjectsUnderSelection(obj, id, dataset, timePoint, use3D)
% Which objects the current drawing sits on.
%
% Input Arguments:
%   - **use3D** - logical, whole volume or the shown slice only
%
% Output Arguments:
%   - **objectIds** - indices of the objects the drawing covers. Empty with no
%     ``problem`` means something was drawn but it lies entirely on background,
%     which is a finding rather than a fault: what to do about it belongs to the
%     action, and Merge turns it into a new object
%   - **problem** - char, why nothing can be done; empty when there is no problem
%   - **details** - cell array of extra lines for the message box, in the shape
%     ``localComplain`` takes them
objectIds = [];
problem = '';
details = {};

[box, drawn] = localDrawingExtent(obj, id, dataset, timePoint, use3D);
if isempty(box)
    problem = 'The Selection layer is empty.';
    details = {'Draw the break into it first, or pick the objects from the list.'};
    return;
end

labelsBlock = localReadBox(obj, id, 'labels', timePoint, box);
objectIds = double(unique(labelsBlock(drawn)))';
objectIds = objectIds(objectIds > 0);
end

% =====================================================================
function [objectIds, problem, details] = localObjectsToJoin(obj, id, dataset, timePoint, use3D)
% Which objects the current drawing joins.
%
% The counterpart of ``localObjectsUnderSelection``, and the difference between them
% is the whole of this function. A **cut** is what the drawing covers: voxels it
% merely lies against are not being taken out of anything. A **join** is what the
% drawing reaches, and in a volume a stroke reaches further than the voxels it
% sits on - the object it was drawn to connect to is on the next slice, where
% there is nothing painted at all.
%
% So: what it covers, and failing that, what lies one slice beyond either end of
% it. In 2D the second half is skipped and this is ``localObjectsUnderSelection``
% exactly, which is right - there is no next slice in a single-slice mode.
%
% **What you can see, you get all of; what you cannot see, you get one of.**
% Contact on a slice the user drew on is deliberate and visible on screen, so
% every object there counts, as it always has. The slice beyond the stroke is
% not drawn and not on screen: a stroke clipping the corner of a neighbour there
% is the ordinary case, and silently swallowing that neighbour is the one
% outcome this must not produce. Each end therefore contributes at most one
% object, the one with the largest footprint under the stroke - not the largest
% object, which would let something big elsewhere in the box beat the one
% actually being pointed at.
%
% Exactly one slice beyond, never two. The drawing has to abut what it joins,
% which keeps the choice something the user can see before pressing the button
% rather than a search reaching for the nearest candidate.
%
% Output Arguments:
%   - **objectIds** - the objects to join, or empty when the drawing reaches
%     none. Empty without a ``problem`` is a finding rather than a fault, as in
%     ``localObjectsUnderSelection`` - the caller turns it into a new object
objectIds = [];
problem = '';
details = {};

[box, drawn] = localDrawingExtent(obj, id, dataset, timePoint, use3D);
if isempty(box)
    problem = 'The Selection layer is empty.';
    details = {'Draw over the objects to join, or between them, first.'};
    return;
end

labelsBlock = localReadBox(obj, id, 'labels', timePoint, box);
objectIds = double(unique(labelsBlock(drawn)))';
objectIds = objectIds(objectIds > 0);
if ~isempty(objectIds) || ~use3D; return; end

% Nothing under it, so look past either end: two single-slice reads over the
% drawing's own in-plane box. What they are tested against is the drawn mask on
% the outermost plane, not that box - a box would reach objects a diagonal
% stroke never came near.
depth = dataset.image.depth;
below = localDominantNeighbour(obj, id, timePoint, box, drawn(:, :, 1),   box(5) - 1, depth);
above = localDominantNeighbour(obj, id, timePoint, box, drawn(:, :, end), box(6) + 1, depth);
objectIds = unique([below, above]);
end

% =====================================================================
function objectId = localDominantNeighbour(obj, id, timePoint, box, footprint, sliceNumber, depth)
% The object with the most voxels under ``footprint`` on slice ``sliceNumber``.
%
% Empty when that slice is outside the stack or carries nothing under the
% stroke. Ties go to the lowest index, so the answer cannot depend on the order
% the values happened to come back in.
objectId = [];
if sliceNumber < 1 || sliceNumber > depth; return; end

slice = localReadBox(obj, id, 'labels', timePoint, [box(1:4), sliceNumber, sliceNumber]);
values = double(slice(footprint));
values = values(values > 0);
if isempty(values); return; end

[counts, candidates] = groupcounts(values);
[~, winner] = max(counts);      % groupcounts sorts its groups, so a tie takes the lowest
objectId = candidates(winner);
end

% =====================================================================
function done = localDrawingToObject(obj, id, dataset, index, timePoint, BatchOpt, batchModeSwitch, consumesSelection, targetId)
% Write the drawing into the model as an object, new or existing.
%
% What MIB's own ``a`` does to a material, done to an instance model. Reached
% from Merge whenever the drawing does not name two objects to join: over
% background it becomes a new object, over one object it joins that object. Both
% are the same gesture - "this region is that object" - and both are available to
% batch protocols by name, as ``AddObject`` and ``AddToObject``.
%
% Nothing else can be overwritten on either path, because they are only taken
% when the drawing covers no other object. Asked for by name, the drawing is
% written over whatever lies under it, which is the caller's choice to make.
%
% Input Arguments:
%   - **consumesSelection** - logical, clear the Selection layer afterwards
%   - **targetId** - index of the object to grow, or ``[]`` to take the next
%     free index
%
% Output Arguments:
%   - **done** - logical, true when the drawing was written
done = false;
use3D = BatchOpt.Mode3D;

[box, drawn] = localDrawingExtent(obj, id, dataset, timePoint, use3D);
if isempty(box)
    localComplain(obj, 'The Selection layer is empty.', 'Instance editor', ...
        {'Draw the new object into it first.'});
    return;
end

% The rescan has to cover the object as it will then be, which for an existing
% one is more than the drawing: its stats are recomputed from the box it is
% given, so a box holding only the new part would report only the new part.
refreshBox = box;
if isempty(targetId)
    [targetId, problem] = localAllocateIndices(obj, id, index, 1);
    if ~isempty(problem); localComplain(obj, problem, 'Instance editor'); return; end
else
    refreshBox = localCoverBox(localUnionBox(index, targetId), box);
end

% Only the drawn voxels change, so the undo step covers the drawing alone. The
% rescan box is the one that travels with it, for the reason above: it is what
% the object's statistics have to be recomputed from, in either direction.
refresh = struct('timePoint', timePoint, 'objectIds', targetId, 'bbox', refreshBox);
if ~batchModeSwitch
    obj.backup('labels', 1, localUndoRepairOptions(box, id, refresh));
end

localWriteLabels(obj, id, localCropToFull(obj, id, box, find(drawn), timePoint), targetId);

dataset.buildInstanceIndex(refresh);

if consumesSelection
    if use3D; dataset.clearLayer('selection', '3D'); else; dataset.clearLayer('selection', '2D'); end
end
done = true;
end

% =====================================================================
function [objectIds, problem] = localValidateIndices(objectIds, index, action)
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
if strcmp(action, 'AddToObject') && numel(objectIds) > 1
    problem = 'The drawing can be given to one object at a time.';
    return;
end
if strcmp(action, 'Connect') && numel(objectIds) > 2
    problem = 'Connect works on exactly two objects.';
    return;
end
end

% =====================================================================
function connectivity = localConnectivity(BatchOpt)
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
function box = localUnionBox(index, objectIds)
% Smallest box containing all of the given objects
boxes = double(index.bbox(objectIds, :));
box = [min(boxes(:, 1)), max(boxes(:, 2)), ...
       min(boxes(:, 3)), max(boxes(:, 4)), ...
       min(boxes(:, 5)), max(boxes(:, 6))];
end

% =====================================================================
function box = localCoverBox(box, other)
% Smallest box containing both
box([1 3 5]) = min(box([1 3 5]), other([1 3 5]));
box([2 4 6]) = max(box([2 4 6]), other([2 4 6]));
end

% =====================================================================
function tf = localBoxesCanTouch(boxA, boxB)
% Could two objects with these boxes be in contact at all?
%
% One-way: ``false`` means they are certainly apart, ``true`` only that the
% boxes are near enough that they might meet. Enough to tell the user when a
% Connect has produced one index in two pieces, and it costs nothing - the boxes
% are already in hand.
tf = boxA(1) <= boxB(2) + 1 && boxB(1) <= boxA(2) + 1 && ...
     boxA(3) <= boxB(4) + 1 && boxB(3) <= boxA(4) + 1 && ...
     boxA(5) <= boxB(6) + 1 && boxB(5) <= boxA(6) + 1;
end

% =====================================================================
function box = localClipToSlice(box, sliceNumber, use3D)
% In 2-D mode every read, write, backup and rescan is confined to one slice
if ~use3D
    box(5:6) = [sliceNumber, sliceNumber];
end
end

% =====================================================================
function options = localBoxOptions(box, id)
options = struct('blockModeSwitch', 0, 'id', id, ...
    'y', box(1:2), 'x', box(3:4), 'z', box(5:6));
end

% =====================================================================
function options = localUndoRepairOptions(box, id, refresh)
% Backup options carrying the note that lets an Undo repair the object index
% instead of invalidating it.
%
% Undoing an edit rewinds voxels without telling ``MibDataset.instanceIndex``,
% so the index has to be treated as stale - and rebuilding it is a pass over the
% whole volume, which is the one cost in this tool that grows with the dataset
% rather than with the edit. But an edit here backs up **one bounding box**, and
% ``MibModel.undo`` restores exactly that box, so the undo is as local as the
% operation was and the index could be repaired over the same region for the
% same cost as the forward edit.
%
% What was missing was the region at undo time. It travels here: ``MibBackup``
% keeps the options struct alongside the stored data, so the note follows its
% entry through the shifts of the ring buffer, and ``MibModel.undo`` hands the
% *same* options to ``replaceItem`` when it fills the redo slot. Two consequences
% worth having:
%
% - no parallel stack in the controller to drift out of step with an undo
%   history it does not own - which would fail by repairing the wrong box, the
%   one failure this whole design exists to prevent
% - re-measuring a region is direction-agnostic, so undo and redo both work
%   from one note. Restoring a saved copy of the index rows instead would have
%   had to know which way it went
%
% ``controllers.InstanceEditor.repairIndexAfterUndo`` reads it back and falls
% through to a full rebuild whenever it is absent or does not describe the
% dataset in front of the user.
%
% Input Arguments:
%   - **box** - ``[y1 y2 x1 x2 z1 z2]`` region to back up
%   - **id** - dataset index
%   - **refresh** - the ``buildInstanceIndex`` options of the forward edit,
%     ``.timePoint`` / ``.objectIds`` / ``.bbox``. Its bbox is the region the
%     statistics must be recomputed from, which is not always the backed-up box:
%     growing an object writes only the drawing but has to be measured over the
%     whole of it.
options = localBoxOptions(box, id);
options.instanceIndexRepair = refresh;
end

% =====================================================================
function sub = localReadBox(obj, id, layer, timePoint, box)
sub = cell2mat(obj.getData3D(layer, timePoint, 3, NaN, localBoxOptions(box, id)));
end

% =====================================================================
function pixelIdxList = localCropToFull(obj, id, box, cropIndices, timePoint)
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
function localWriteLabels(obj, id, pixelIdxList, value)
% Write one label value at a list of full-volume linear indices
if isempty(pixelIdxList); return; end
labelValues = zeros(numel(pixelIdxList), 1, obj.I{id}.labels.dataClass) + value;
obj.I{id}.setPixelIdxList('labels', labelValues, pixelIdxList);
end

% =====================================================================
function [newIds, problem] = localAllocateIndices(obj, id, index, count)
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
function done = localObjectAction(obj, id, action, objectIds, index, timePoint, BatchOpt, batchModeSwitch, consumesSelection)
% The per-object operations. All of them read, back up, write and rescan inside
% one bounding box, which is what keeps them interactive on a large model.
%
% Input Arguments:
%   - **consumesSelection** - logical, clear the Selection layer afterwards
%     because the operation took its input from it
done = false;
dataset = obj.I{id};
use3D = BatchOpt.Mode3D;
sliceNumber = dataset.getCurrentSliceNumber();

% Objects whose extent may change, and the region in which voxels change. Both
% start from the selection and are widened by the individual actions.
touchedIds = objectIds;
box = localClipToSlice(localUnionBox(index, objectIds), sliceNumber, use3D);

if use3D == false && (sliceNumber < min(index.bbox(objectIds, 5)) || ...
        sliceNumber > max(index.bbox(objectIds, 6)))
    localComplain(obj, 'None of the selected objects is present on the shown slice.', 'Instance editor');
    return;
end

% Work out everything that will be written before touching the dataset, so a
% problem is reported without half an edit having been applied.
writes = struct('pixelIdxList', {}, 'value', {});

bridged = false;

switch action
    case 'Merge'
        [writes, survivor] = localMergeWrites(obj, id, index, objectIds, timePoint, sliceNumber, use3D);

        % The drawing chose these objects, so it is part of the gesture and not
        % merely the thing that pointed at them: the background under it joins
        % the survivor, and the gap the stroke was drawn across closes. This is
        % what a drawing over a **single** object has always done - the object
        % grows by it - so the rule no longer changes with how many objects
        % happen to lie under the stroke.
        if consumesSelection
            [absorbed, drawingBox] = localAbsorbDrawing(obj, id, dataset, timePoint, use3D, survivor);
            if ~isempty(absorbed)
                writes = [writes, absorbed];
                box = localCoverBox(box, drawingBox);
            end
        end

    case {'SplitComponents', 'SplitBySelection', 'CutAtSlice'}
        [writes, touchedIds, problem] = localPlanSplit(obj, id, action, objectIds, index, ...
            timePoint, sliceNumber, use3D, BatchOpt);
        if ~isempty(problem); localComplain(obj, problem, 'Instance editor'); return; end

    case 'Connect'
        % Connect is a bridge followed by a merge, and the merge is the same one
        % Merge does - it used to carry its own copy, with use3D hardcoded true.
        [writes, box, bridged, problem] = localPlanConnect(obj, id, dataset, objectIds, ...
            index, timePoint, BatchOpt);
        if ~isempty(problem); localComplain(obj, problem, 'Instance editor'); return; end
        writes = [writes, localMergeWrites(obj, id, index, objectIds, timePoint, sliceNumber, use3D)];

    case 'Delete'
        for objectId = objectIds
            pixels = localObjectPixels(obj, id, index, objectId, timePoint, sliceNumber, use3D);
            writes(end+1) = struct('pixelIdxList', pixels, 'value', 0); %#ok<AGROW>
        end
end

if isempty(writes)
    localComplain(obj, 'There is nothing to change for this selection.', 'Instance editor');
    return;
end

%% Apply
% Undo covers only the affected box. A whole-volume snapshot would exhaust
% MibBackup's 3D step budget within a few clicks and stall each of them. The
% same region is attached to the undo entry, so that undoing this operation
% repairs the index over it instead of invalidating the whole thing.
refresh = struct('timePoint', timePoint, 'objectIds', unique(touchedIds), 'bbox', box);
if ~batchModeSwitch
    obj.backup('labels', 1, localUndoRepairOptions(box, id, refresh));
end
for w = 1:numel(writes)
    localWriteLabels(obj, id, writes(w).pixelIdxList, writes(w).value);
end

%% Repair the index over the same region
dataset.buildInstanceIndex(refresh);

% The drawing has done its job, so it is used up. Leaving it would let a shape
% drawn for this object be applied to the next one: with no objects named, the
% next drawing-driven action reads the whole layer to find out what it means.
% Deliberately not backed up - the undo step belongs to the change in the model,
% and a second one would mean two Ctrl+Z presses to reverse a single action.
if consumesSelection
    if use3D; dataset.clearLayer('selection', '3D'); else; dataset.clearLayer('selection', '2D'); end
end

% Connect promises one connected object. When the two overlap in Z there is
% nothing for "interpolate" to fill, and if their boxes are too far apart to
% meet, the result is one index in two pieces - the very thing the user opened
% the editor to repair. Doing that in silence was the defect: it looked like a
% Connect and was a Merge.
if strcmp(action, 'Connect') && ~bridged && ...
        ~localBoxesCanTouch(double(index.bbox(objectIds(1), :)), double(index.bbox(objectIds(2), :)))
    localComplain(obj, sprintf('Objects %d and %d were joined, but nothing was bridged.', ...
        objectIds(1), objectIds(2)), 'Connect', ...
        {'They overlap in Z, so "interpolate" had no gap to fill, and they are too far apart to be touching.', ...
         'The result is one index in two separate pieces. To join them properly, draw the bridge and use the "selection" mode.'});
end

done = true;
end

% =====================================================================
function [writes, survivor] = localMergeWrites(obj, id, index, objectIds, timePoint, sliceNumber, use3D)
% Relabel every object but one to the smallest index among them.
%
% The whole of Merge, and the last step of Connect. The smallest index wins by
% definition of the operation, and both callers need that to be the same rule.
writes = struct('pixelIdxList', {}, 'value', {});
survivor = min(objectIds);
for objectId = setdiff(objectIds, survivor)
    writes(end+1) = struct(...
        'pixelIdxList', localObjectPixels(obj, id, index, objectId, timePoint, sliceNumber, use3D), ...
        'value', survivor); %#ok<AGROW>
end
end

% =====================================================================
function pixels = localObjectPixels(obj, id, index, objectId, timePoint, sliceNumber, use3D)
% Full-volume linear indices of one object, found inside its own bounding box
box = localClipToSlice(double(index.bbox(objectId, :)), sliceNumber, use3D);
sub = localReadBox(obj, id, 'labels', timePoint, box);
pixels = localCropToFull(obj, id, box, find(sub == objectId), timePoint);
end

% =====================================================================
function [writes, touchedIds, problem] = localPlanSplit(obj, id, action, objectIds, index, timePoint, sliceNumber, use3D, BatchOpt)
% Plan the three splitting actions. They differ only in how the object is cut;
% the allocation of new indices is common.
writes = struct('pixelIdxList', {}, 'value', {});
touchedIds = objectIds;
problem = '';
connectivity = localConnectivity(BatchOpt);

% A split cannot reuse an index it is about to free, so allocation walks a
% working copy of the index that is updated as pieces are handed out.
workingIndex = index;

for objectId = objectIds
    box = localClipToSlice(double(index.bbox(objectId, :)), sliceNumber, use3D);
    sub = localReadBox(obj, id, 'labels', timePoint, box);
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
            selection = localReadBox(obj, id, 'selection', timePoint, box);
            objectMask = objectMask & ~(selection > 0);
            % Nothing left is an outcome, not a refusal. 's' means "subtract the
            % Selection from the material" here exactly as it does everywhere
            % else in MIB, so a drawing that covers the whole object subtracts
            % the whole object - the same way 'a' grows an object or creates one
            % according to what its drawing covers, rather than insisting the
            % gesture be a merge. It needs no code of its own: localComponentMasks
            % returns {} for an empty mask, so the removal queued just below is
            % then the whole operation, and the index refresh frees the index in
            % 3D. In 2D it searches the object's previous box as well, so an
            % object cleared from the shown slice keeps its index and its voxels
            % on the others.
            componentMasks = localComponentMasks(objectMask, connectivity, use3D);
            % the voxels taken out by the Selection go back to background
            removed = (sub == objectId) & ~objectMask;
            writes(end+1) = struct(...
                'pixelIdxList', localCropToFull(obj, id, box, find(removed), timePoint), ...
                'value', 0); %#ok<AGROW>

        otherwise   % SplitComponents
            componentMasks = localComponentMasks(objectMask, connectivity, use3D);
    end

    % localComponentMasks returns every component except the largest, which keeps
    % the original index and needs no write. Empty therefore means the object is
    % already a single piece and there is nothing to split. For SplitBySelection
    % the removal write queued above still stands.
    if isempty(componentMasks); continue; end

    [newIds, problem] = localAllocateIndices(obj, id, workingIndex, numel(componentMasks));
    if ~isempty(problem); return; end

    for k = 1:numel(componentMasks)
        writes(end+1) = struct(...
            'pixelIdxList', localCropToFull(obj, id, box, find(componentMasks{k}), timePoint), ...
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
function componentMasks = localComponentMasks(objectMask, connectivity, use3D)
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
function [writes, box, bridged, problem] = localPlanConnect(obj, id, dataset, objectIds, index, timePoint, BatchOpt)
% Plan the **bridge** between two objects. The merge that follows is the
% caller's, and is the same ``localMergeWrites`` that Merge uses.
%
% The two modes ask for different things, and only one of them needs a gap:
%
% - ``selection`` - the bridge is whatever was drawn, handled by
%   ``localAbsorbDrawing`` exactly as a drawing-driven Merge is. It makes sense with
%   or without a gap in Z, so this mode asks nothing about how the two lie: two
%   objects that share a Z range but never touch are joined by it just as well.
% - ``interpolate`` - the bridge is morphed between the two facing
%   cross-sections, so it needs a gap to have two faces to morph between.
%
% Output Arguments:
%   - **bridged** - logical, whether anything was actually written between them.
%     ``false`` means the caller is about to perform a plain merge, which the
%     user is told about when the two cannot be touching.
writes = struct('pixelIdxList', {}, 'value', {});
problem = '';
bridged = false;
survivor = min(objectIds);
box = localUnionBox(index, objectIds);

% Same refusal as CutAtSlice, and for the same reason: this is an operation
% along Z. Without it Connect ran anyway and merged the whole of both objects
% through the stack while the mode said one slice.
if ~BatchOpt.Mode3D
    problem = 'Connect needs 3D mode - a gap along Z cannot be bridged inside a single slice.';
    return;
end

if strcmp(BatchOpt.ConnectMode{1}, 'selection')
    [writes, drawingBox] = localAbsorbDrawing(obj, id, dataset, timePoint, true, survivor);
    if isempty(drawingBox)
        problem = 'The Selection layer is empty - draw the bridging area first, or use the "interpolate" mode.';
        return;
    end
    if isempty(writes)
        problem = 'Everything drawn already belongs to an object, so there is no bridge to build.';
        return;
    end
    box = localCoverBox(box, drawingBox);
    bridged = true;
    return;
end

boxA = double(index.bbox(objectIds(1), :));
boxB = double(index.bbox(objectIds(2), :));
if boxA(5) <= boxB(6) && boxB(5) <= boxA(6)
    return;     % they overlap in Z: no two faces, nothing to interpolate between
end

if boxA(6) < boxB(5)
    lower = objectIds(1); upper = objectIds(2);
    zLower = boxA(6);     zUpper = boxB(5);
else
    lower = objectIds(2); upper = objectIds(1);
    zLower = boxB(6);     zUpper = boxA(5);
end
bridgeBox = [box(1:4), zLower, zUpper];
labelsInBridge = localReadBox(obj, id, 'labels', timePoint, bridgeBox);

bridge = false(size(labelsInBridge));
bridge(:, :, 1)   = labelsInBridge(:, :, 1) == lower;
bridge(:, :, end) = labelsInBridge(:, :, end) == upper;
% utils.interpolateShapes morphs between the two annotated planes and fills
% everything in between.
bridge = utils.interpolateShapes(uint8(bridge)) > 0;

% Background only, the same guard localAbsorbDrawing applies to the drawn bridge:
% without it the interpolated tube would carve through whatever happens to lie
% between the two objects.
bridge = bridge & (labelsInBridge == 0);
if ~any(bridge, 'all'); return; end

writes(end+1) = struct(...
    'pixelIdxList', localCropToFull(obj, id, bridgeBox, find(bridge), timePoint), ...
    'value', survivor);
bridged = true;
end

% =====================================================================
function done = localWholeModelAction(obj, id, action, BatchOpt, batchModeSwitch)
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

        cleanupOptions.absorbFragmentVoxels = BatchOpt.cleanupAbsorbFragmentVoxels{1};
        cleanupOptions.minObjectVoxels = BatchOpt.cleanupMinObjectVoxels{1};
        cleanupOptions.minObjectSlices = BatchOpt.cleanupMinObjectSlices{1};
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
        % Reported below rather than here, so the box goes up after the progress
        % dialog has been taken down and not behind it.
        cleanupStats = stats;

    case 'Compact'
        % Captured before the renumbering, because afterwards there is nothing
        % left to compare against: both branches below map the sorted label
        % values onto 1..n, so an object's new number is its rank among the
        % values in use and everything reported follows from the old index. The
        % index is guaranteed fresh here - the caller rebuilds a stale one
        % before dispatching.
        previous = dataset.instanceIndex;
        compactStats = struct('oldIds', find(previous.exists)', ...
            'oldMax', double(previous.maxIndex), ...
            'perSlice', ~BatchOpt.Mode3D, 'slicesChanged', 0, ...
            'slicesWithObjects', 0, 'depth', 0);

        if BatchOpt.Mode3D
            dataset.labels.squeezeMaterialLabels(wb);
        else
            % Per slice, because that is what the numbering means in this mode.
            % An unstitched model numbers from 1 again on every slice, so its
            % gaps are per-slice gaps and a single global squeeze would not
            % close them: a slice holding 1, 3, 5 keeps 3 and 5 as long as some
            % other slice uses those values, which on such a model it always
            % does. Here each slice is tightened on its own - 1, 3, 5 becomes
            % 1, 2, 3 - and the slices are independent, so the same number
            % meaning a different object on each of them is unchanged, that
            % being what the model already is.
            readOptions = struct('blockModeSwitch', 0, 'id', id);
            volume = cell2mat(obj.getData3D('labels', timePoint, 3, NaN, readOptions));
            compactStats.depth = size(volume, 3);
            if ~isempty(wb)
                wb.Indeterminate = 'off';
                wb.Message = 'Renumbering the objects of each slice...';
            end

            for z = 1:compactStats.depth
                if ~isempty(wb)
                    if wb.CancelRequested
                        % Nothing has reached the model yet - the loop writes
                        % into a local copy - so cancelling leaves it untouched.
                        delete(wb);
                        fprintf('Instance editor: compact cancelled, the model was not changed\n');
                        return;
                    end
                    wb.Value = z / compactStats.depth;
                end

                slice = volume(:, :, z);
                [values, ~, ranks] = unique(slice);
                present = values(values > 0);

                % An empty slice is not a slice that was "already in place" -
                % there is nothing on it to number. Counting it as one would
                % make the report read "renumbered 2 of 501" on a stack whose
                % objects sit on forty slices, which says nothing about the
                % work. The denominator is therefore slices carrying objects.
                if isempty(present); continue; end
                compactStats.slicesWithObjects = compactStats.slicesWithObjects + 1;

                if isequal(double(present(:))', 1:numel(present)); continue; end
                if values(1) == 0; ranks = ranks - 1; end    % background stays 0
                volume(:, :, z) = reshape(cast(ranks, 'like', slice), size(slice));
                compactStats.slicesChanged = compactStats.slicesChanged + 1;
            end

            obj.setData3D(volume, 'labels', timePoint, 3, [], readOptions);
            dataset.labels.materialsCount = double(max(volume, [], 'all'));
        end
end

if ~isempty(wb); delete(wb); end

% The whole label space has moved; nothing of the old index survives.
dataset.instanceIndex = [];
dataset.buildInstanceIndex(struct('timePoint', timePoint));

% Both whole-model actions report through localReport, in the application rather than
% the command window behind it: Compact changes every number the user has been
% navigating by while changing nothing they can see, and Cleanup removes objects
% that were on the list a moment ago. The headline carries the figure that
% answers "did it do anything"; the rest goes underneath it.
if strcmp(action, 'Cleanup')
    message = sprintf('%d objects removed, %d fragments absorbed.', ...
        cleanupStats.numRemoved, cleanupStats.numAbsorbedFragments);
    details = {
        sprintf('%d voxels were handed to neighbouring objects.', cleanupStats.numAbsorbedVoxels)
        sprintf('%d objects left in the model.', cleanupStats.numObjects)
        'Object numbers are unchanged - use Compact to renumber.'};
    localReport(obj, message, 'Cleanup', details, ~batchModeSwitch);
end

if strcmp(action, 'Compact')
    newIndex = dataset.instanceIndex;
    scope = '';
    if dataset.labels.time > 1
        % The 3D branch renumbers every time point, each from its own unique()
        % pass; the 2D branch touches the shown one only. Either way the figures
        % below are measured on the shown time point, so it is named.
        scope = sprintf(' (time point %d)', timePoint);
    end

    if compactStats.perSlice
        % Per slice the object count is not a single number - the same index is
        % a different object on each slice - so what is reported is how many
        % slices had gaps, and how far the numbering came down.
        message = sprintf('Renumbered %d of %d slices with objects%s.', ...
            compactStats.slicesChanged, compactStats.slicesWithObjects, scope);
        details = {
            sprintf('%d slices were already numbered 1, 2, 3...', ...
                compactStats.slicesWithObjects - compactStats.slicesChanged)
            sprintf('%d slices in the stack.', compactStats.depth)
            sprintf('Highest index: %d -> %d', compactStats.oldMax, double(newIndex.maxIndex))
            'Each slice is numbered on its own, so one index means a different object on each.'};
    else
        oldIds = compactStats.oldIds;
        kept = nnz(oldIds == 1:numel(oldIds));
        message = sprintf('Renumbered %d of %d objects%s.', ...
            numel(oldIds) - kept, numel(oldIds), scope);
        details = {
            sprintf('%d objects already had their final number.', kept)
            sprintf('Highest index: %d -> %d', compactStats.oldMax, double(newIndex.maxIndex))
            sprintf('%d unused indices reclaimed.', ...
                compactStats.oldMax - double(newIndex.maxIndex))};
        if double(newIndex.numObjects) ~= numel(oldIds)
            % Renumbering must not add or remove objects. Nothing has produced
            % this; it is here because it is the damage hardest to recognise.
            details{end+1} = sprintf(['WARNING: the object count changed from %d to %d, ' ...
                'which renumbering must never do.'], numel(oldIds), double(newIndex.numObjects));
        end
    end
    localReport(obj, message, 'Compact', details, ~batchModeSwitch);
end
done = true;
end
