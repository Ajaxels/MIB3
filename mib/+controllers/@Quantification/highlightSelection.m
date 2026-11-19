function highlightSelection(obj, object_list, mode, sliceNumbers)
% HIGHLIGHTSELECTION - Highlight selected quantification objects in the selection layer.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.highlightSelection(object_list, mode, sliceNumbers)
%
% Writes to the MIB selection layer for the objects given in object_list.
% For 2D slice mode or a single object, the selection is written slice-by-
% slice.  For 3D datasets the entire PixelIdxList is written at once.
% After a BigData run (``obj.runPyramidLevel`` set) the selection is written at
% the measured pyramid level instead, see the local ``highlightBigData``;
% ``obj2model`` is refused there.
%
% Input Arguments:
%   - **object_list** - [numeric] vector of object indices into obj.STATS
%   - **mode** *(optional)* - [char] highlight action (default: read from obj.view.handles.selectionModePanel.SelectedObject.Text):
%
%     - ``'Add'`` - add objects to existing selection
%     - ``'Remove'`` - remove objects from existing selection
%     - ``'Replace'`` - replace selection with these objects
%     - ``'obj2model'`` - assign each object as a separate model material (replaces the current model; shows a confirmation dialog first)
%
%   - **sliceNumbers** *(optional)* - [numeric] vector of slice indices, one per object; used to restrict data reading to the relevant slice in 3D datasets
%
% **Example 1** - add objects to selection:
%
%   .. code-block:: matlab
%
%      obj.highlightSelection([3, 7], 'Add');
%
% **Example 2** - replace selection:
%
%   .. code-block:: matlab
%
%      obj.highlightSelection(object_list, 'Replace', sliceNums);

if nargin < 4; sliceNumbers = []; end
if nargin < 3 || isempty(mode); mode = obj.view.handles.selectionModePanel.SelectedObject.Text; end

id = obj.mibModel.getActiveId();
if ~isempty(obj.runPyramidLevel)
    % the results of a BigData run: PixelIdxList is in the voxels of the measured level
    highlightBigData(obj, id, object_list, mode);
    return;
end
getDataOptions.blockModeSwitch = 0;
[img_height, img_width, img_depth] = obj.mibModel.I{id}.getDatasetDimensions('image', [], getDataOptions);
shape2D = strcmp(obj.BatchOpt.DatasetType{1}, '2D, Slice') && strcmp(obj.view.handles.ObjectShape.SelectedObject.Tag, 'Shape2D');
single2D = strcmp(obj.view.handles.ObjectShape.SelectedObject.Tag, 'Shape2D') && numel(object_list) == 1;

if shape2D || single2D
    currentSlice = obj.STATS(object_list(1)).Centroid(3);
    currentTime = obj.STATS(object_list(1)).TimePnt;
    getDataOptions.t = [currentTime, currentTime];

    selection_mask = zeros(img_height, img_width, 'uint8');
    coef = img_height * img_width * (currentSlice - 1);
    for i = 1:numel(object_list)
        selection_mask(obj.STATS(object_list(i)).PixelIdxList - coef) = 1;
    end

    if strcmp(mode, 'Add') || strcmp(mode, 'Remove')
        bb = ceil(reshape([obj.STATS(object_list).BoundingBox], [6 numel(object_list)])');
        getDataOptions.x = [min(bb(:,1)), max(bb(:,1)+bb(:,4)-1)];
        getDataOptions.y = [min(bb(:,2)), max(bb(:,2)+bb(:,5)-1)];
        xMin = getDataOptions.x(1); xMax = getDataOptions.x(2);
        yMin = getDataOptions.y(1); yMax = getDataOptions.y(2);
    end

    switch mode
        case 'Add'
            sel = cell2mat(obj.mibModel.getData2D('selection', currentSlice, [], [], getDataOptions));
            sel = bitor(selection_mask(yMin:yMax, xMin:xMax), sel);
            obj.mibModel.setData2D({sel}, 'selection', currentSlice, [], [], getDataOptions);
        case 'Remove'
            sel = cell2mat(obj.mibModel.getData2D('selection', currentSlice, [], [], getDataOptions));
            sel(selection_mask(yMin:yMax, xMin:xMax) == 1) = 0;
            obj.mibModel.setData2D({sel}, 'selection', currentSlice, [], [], getDataOptions);
        case 'Replace'
            if single2D
                BatchOptClearSelection.showWaitbar = false;
                obj.mibModel.clearSelection('4D, Dataset', BatchOptClearSelection);
            end
            obj.mibModel.setData2D({selection_mask}, 'selection', currentSlice, [], [], getDataOptions);
    end
else
    if numel(object_list) > 1 || strcmp(mode, 'Replace') || ...
            (~isempty(object_list) && numel(obj.STATS(object_list(1)).PixelIdxList) > 1000000)
        wb = uiprogressdlg(obj.view.gui, 'Title', 'Highlighting', 'Message', 'Highlighting selected objects...', 'Indeterminate', 'on');
    end

    timePoints = [obj.STATS(object_list).TimePnt];
    [timePointsUnique, ~, ic] = unique(timePoints);
    tIdx = 1;

    if strcmp(mode, 'Replace'); obj.mibModel.clearSelection('4D, Dataset'); end

    if strcmp(mode, 'obj2model')
        if strcmp(obj.view.handles.ObjectShape.SelectedObject.Tag, 'Shape2D')
            numberOfObjects = max(histcounts(sliceNumbers, max(sliceNumbers)));
        else
            numberOfObjects = numel(object_list);
        end
        if numberOfObjects < 64
            modelType = 63;  maskClass = 'uint8';
        elseif numberOfObjects < 256
            modelType = 255; maskClass = 'uint8';
        elseif numberOfObjects < 65536
            modelType = 65535; maskClass = 'uint16';
        else
            utils.dlgs.showErrorDialog(obj.view.gui, 'Number of materials exceeds the maximum!', 'Too many objects');
            notify(obj.mibModel, 'StopProtocol');
            return;
        end
        obj.mibModel.I{id}.createModel(modelType);
    else
        maskClass = 'uint8';
    end

    for t = timePointsUnique
        objects = object_list(ic == tIdx);
        if ~strcmp(mode, 'obj2model')
            getDataOptions.PixelIdxList = vertcat(obj.STATS(objects).PixelIdxList);
            dataset = zeros(size(getDataOptions.PixelIdxList), maskClass);
            if strcmp(mode, 'Add') || strcmp(mode, 'Replace')
                dataset(:) = 1;
            end
            obj.mibModel.setData3D(dataset, 'selection', t, [], 0, getDataOptions);
        else
            selection_mask = zeros([img_height, img_width, img_depth], maskClass);
            if strcmp(obj.view.handles.ObjectShape.SelectedObject.Tag, 'Shape2D')
                objIndex = zeros([max(sliceNumbers), 1]);
            else
                objIndex = 0;
            end

            if strcmp(obj.view.handles.ObjectShape.SelectedObject.Tag, 'Shape2D')
                for i = 1:numel(objects)
                    [~, ~, subIdZ] = ind2sub([img_height, img_width, img_depth], obj.STATS(objects(i)).PixelIdxList(1));
                    objIndex(subIdZ) = objIndex(subIdZ) + 1;
                    selection_mask(obj.STATS(objects(i)).PixelIdxList) = objIndex(subIdZ);
                end
            else
                for i = 1:numel(objects)
                    objIndex = objIndex + 1;
                    selection_mask(obj.STATS(objects(i)).PixelIdxList) = objIndex;
                end
            end
            obj.mibModel.setData3D({selection_mask}, 'labels', t, [], [], getDataOptions);
        end
        tIdx = tIdx + 1;
    end
    if exist('wb', 'var'); delete(wb); end
end

fprintf('Quantification: selected %d objects\n', numel(object_list));

if strcmp(mode, 'obj2model')
    obj.mibModel.I{id}.labels.materialNames = strtrim(cellstr(num2str((1:numberOfObjects).')));
    noColors = size(obj.mibModel.I{id}.labels.materialColors, 1);
    if noColors < numberOfObjects
        obj.mibModel.I{id}.labels.materialColors(noColors+1:numberOfObjects,:) = rand(numberOfObjects-noColors, 3);
    end
    notify(obj.mibModel, 'UpdateGuiWidgets');
end
notify(obj.mibModel, 'ShowImage');
end

% -------------------------------------------------------------------------
function highlightBigData(obj, id, objectList, mode)
% HIGHLIGHTBIGDATA - local helper: write the objects of a BigData run into the selection at the measured level.
%
% Syntax:
%   function highlightBigData(obj, id, objectList, mode)
%
% ``obj.STATS(i).PixelIdxList`` holds linear indices into the level volume
% ``obj.runPyramidLevel.size``. The selection is read over the union box of
% the objects at that level, the object voxels are set (``Add``, ``Replace``)
% or cleared (``Remove``), and the box is written back at the same level.
% ``setData63`` copies the change to the coarser levels and marks the level
% map, so finer levels are upsampled from it on read, as after an edit drawn
% at that zoom. The level box rows ``a..b`` are requested as full-resolution
% ``floor((a-1)*s)+1 .. floor(b*s)``, which getData maps back to ``a..b``
% (``ceil(y / s)``) for any scale ``s >= 1``.
%
% Refused with an error dialog: ``obj2model`` (it would create a new BigData
% model store from the table), results of another dataset than the active
% one, and a model whose selection cannot be written (no packed store, or a
% read-only one such as a Zarr v2 overlay). ``Replace`` clears the selection of
% the dataset first (``MibModel.clearSelection``, tile-wise on BigData). The
% union box of objects spread over the level can be as large as the level,
% i.e. as large as the read of a Shape3D run.

dataset = obj.mibModel.I{id};
levelInfo = obj.runPyramidLevel;
parentFig = [];
if ~isempty(obj.view) && isvalid(obj.view.gui); parentFig = obj.view.gui; end

if strcmp(mode, 'obj2model')
    utils.dlgs.showErrorDialog(parentFig, ...
        'Objects to a new model is not available for BigData datasets.', 'Quantification of BigData');
    notify(obj.mibModel, 'StopProtocol');
    return;
end
if isempty(obj.runId) || obj.runId(1) ~= id || ~strcmp(dataset.datasetType, 'BigData')
    utils.dlgs.showErrorDialog(parentFig, ...
        sprintf('The results belong to another dataset.\nPress Quantify to measure the shown dataset.'), ...
        'Quantification of BigData');
    return;
end
if ~isa(dataset.labels, 'core.MibBigDataLabels') || ~dataset.labels.exists || ...
        strcmp(dataset.getLockedState('labels'), 'readOnly')
    utils.dlgs.showErrorDialog(parentFig, ...
        'The selection of this model cannot be written: the model is read-only.', 'Quantification of BigData');
    return;
end
if isempty(objectList); return; end

wb = [];
if ~isempty(parentFig)
    wb = uiprogressdlg(parentFig, 'Title', 'Highlighting', 'Message', 'Highlighting selected objects...', ...
        'Indeterminate', 'on');
end

if strcmp(mode, 'Replace')
    BatchOptClearSelection.showWaitbar = false;
    obj.mibModel.clearSelection('4D, Dataset', BatchOptClearSelection);
end

pixelIds = vertcat(obj.STATS(objectList).PixelIdxList);
[rows, columns, slices] = ind2sub(levelInfo.size, pixelIds);
box = [min(rows), max(rows), min(columns), max(columns), min(slices), max(slices)];
boxSize = [box(2) - box(1) + 1, box(4) - box(3) + 1, box(6) - box(5) + 1];
scale = levelInfo.scale;    % [y x z]

readOptions = struct('blockModeSwitch', 0, 'pyramidLevel', levelInfo.level, ...
    'y', [floor((box(1) - 1) * scale(1)) + 1, floor(box(2) * scale(1))], ...
    'x', [floor((box(3) - 1) * scale(2)) + 1, floor(box(4) * scale(2))], ...
    'z', [floor((box(5) - 1) * scale(3)) + 1, floor(box(6) * scale(3))]);
timePoint = obj.STATS(objectList(1)).TimePnt;

selection = cell2mat(obj.mibModel.getData3D('selection', timePoint, 3, NaN, readOptions));
if ~isequal([size(selection, 1), size(selection, 2), size(selection, 3)], boxSize)
    if ~isempty(wb); delete(wb); end
    utils.dlgs.showErrorDialog(parentFig, ...
        sprintf(['The selection read at level s%d has another size than the objects box ' ...
        '(%d x %d x %d instead of %d x %d x %d); nothing was highlighted.'], levelInfo.level - 1, ...
        size(selection, 2), size(selection, 1), size(selection, 3), boxSize(2), boxSize(1), boxSize(3)), ...
        'Quantification of BigData');
    return;
end
boxIds = sub2ind(boxSize, rows - box(1) + 1, columns - box(3) + 1, slices - box(5) + 1);
selection(boxIds) = uint8(~strcmp(mode, 'Remove'));
obj.mibModel.setData3D(selection, 'selection', timePoint, 3, [], readOptions);

if ~isempty(wb); delete(wb); end
fprintf('Quantification: selected %d objects at BigData level s%d\n', numel(objectList), levelInfo.level - 1);
notify(obj.mibModel, 'ShowImage');
end
