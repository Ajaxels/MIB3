function highlightSelection(obj, object_list, mode, sliceNumbers)
% function highlightSelection(obj, object_list, mode, sliceNumbers)
% Highlight selected quantification objects in the selection layer.
%
% Writes to the MIB selection layer for the objects given in object_list.
% For 2D slice mode or a single object, the selection is written slice-by-
% slice.  For 3D datasets the entire PixelIdxList is written at once.
%
% Parameters:
% object_list: numeric vector of object indices into obj.STATS
% mode: [@em optional] string — highlight action
% @li 'Add'      - add objects to existing selection
% @li 'Remove'   - remove objects from existing selection
% @li 'Replace'  - replace selection with these objects
% @li 'obj2model' - assign each object as a separate model material
%   (replaces the current model; shows a confirmation dialog first)
%   Default is read from obj.view.handles.selectionModePanel.SelectedObject.Text
% sliceNumbers: [@em optional] numeric vector, one slice index per object;
%   used to restrict data reading to the relevant slice in 3D datasets
%
%|
% @b Examples:
% @code obj.highlightSelection([3, 7], 'Add');                     // add objects 3 and 7 @endcode
% @code obj.highlightSelection(object_list, 'Replace', sliceNums); // replace selection @endcode

% Updates
%

if nargin < 4; sliceNumbers = []; end
if nargin < 3; mode = obj.view.handles.selectionModePanel.SelectedObject.Text; end

id = obj.mibModel.getActiveId();
mode2Options.blockModeSwitch = 0;
[img_height, img_width, ~, img_depth] = obj.mibModel.I{id}.getDatasetDimensions('image', [], mode2Options);
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
    numberOfObjects = max(cell2mat(arrayfun(@(x) x, struct2cell(obj.mibModel.I{id}.labels.materialColors), 'UniformOutput', false)), [], 'all');
    obj.mibModel.I{id}.labels.materialNames = strtrim(cellstr(num2str((1:numel(object_list)).')));
    noColors = size(obj.mibModel.I{id}.labels.materialColors, 1);
    if noColors < numel(object_list)
        obj.mibModel.I{id}.labels.materialColors(noColors+1:numel(object_list),:) = rand(numel(object_list)-noColors, 3);
    end
    notify(obj.mibModel, 'UpdateGuiWidgets');
end
notify(obj.mibModel, 'ShowImage');
end
