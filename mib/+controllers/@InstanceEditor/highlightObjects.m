function highlightObjects(obj)
% HIGHLIGHTOBJECTS - Show the picked objects in the Selection layer.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.highlightObjects()
%
% Proofreading needs to see which object is which before deciding whether to
% split or merge it, and the model itself is drawn in one colour per index that
% is hard to tell apart. Writing the picked objects into the Selection layer is
% the same approach ``controllers.Quantification.highlightSelection`` takes.
%
% In 3D mode reads and writes are confined to the union bounding box of the
% picked objects, so highlighting an object costs what the object costs rather
% than what the dataset costs. In 2D mode only the shown slice is highlighted,
% matching what the operations act on there.
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)

% Updates
%

if ~obj.modelIsEditable(); return; end

id = obj.mibModel.getActiveId();
dataset = obj.mibModel.I{id};
timePoint = dataset.getCurrentTimePoint();
use3D = logical(obj.view.handles.Mode3D.Value);

% Any previous highlight has to go, or the selection accumulates every object
% that has ever been picked.
obj.mibModel.clearSelection('4D, Dataset', struct('showWaitbar', false, 'id', id));

objectIds = obj.selectedObjects;
objectIds = objectIds(objectIds > 0);

if use3D
    % The bounding boxes come from the index, so without a usable one there is
    % nothing to read.
    if ~obj.indexIsUsable(); return; end
    index = dataset.instanceIndex;
    objectIds = objectIds(objectIds <= index.maxIndex);
    if ~isempty(objectIds); objectIds = objectIds(index.exists(objectIds)); end
    if isempty(objectIds)
        notify(obj.mibModel, 'ShowImage');
        return;
    end
    boxes = double(index.bbox(objectIds, :));
    box = [min(boxes(:, 1)), max(boxes(:, 2)), ...
           min(boxes(:, 3)), max(boxes(:, 4)), ...
           min(boxes(:, 5)), max(boxes(:, 6))];
else
    % The operations act on the shown slice only, so the highlight has to show
    % the same thing: the whole Z range of the index would light up every object
    % carrying the same number on another slice, which in a model coming from a
    % 2D predictor is one per slice. One slice is also small enough to highlight
    % without any bounding box at all, which keeps 2D mode working while the
    % index is stale.
    if isempty(objectIds)
        notify(obj.mibModel, 'ShowImage');
        return;
    end
    sliceNumber = dataset.getCurrentSliceNumber();
    [height, width] = dataset.getDatasetDimensions('image', [], struct('blockModeSwitch', 0));
    box = [1, height, 1, width, sliceNumber, sliceNumber];
end

readOptions = struct('blockModeSwitch', 0, 'id', id, ...
    'y', box(1:2), 'x', box(3:4), 'z', box(5:6));

labelsInBox = cell2mat(obj.mibModel.getData3D('labels', timePoint, 3, NaN, readOptions));
selection = uint8(ismember(labelsInBox, cast(objectIds, 'like', labelsInBox)));

% internalEdit keeps the SetData listener from treating this as an outside edit;
% it writes the selection layer, which does not move any object, but the guard
% costs nothing and keeps the rule in one place.
obj.internalEdit = true;
restoreFlag = onCleanup(@() obj.clearInternalEditFlag());
obj.mibModel.setData3D(selection, 'selection', timePoint, 3, [], readOptions);
clear restoreFlag;

notify(obj.mibModel, 'ShowImage');
end
