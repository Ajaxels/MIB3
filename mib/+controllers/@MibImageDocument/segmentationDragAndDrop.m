function segmentationDragAndDrop(obj, y, x, modifier)
% function segmentationDragAndDrop(obj, y, x, modifier)
% Initiate drag-and-drop of materials, selection, or mask layer
%
% Captures the initial selection under the mouse, sets up motion and
% button-up callbacks for interactive dragging.
%
% Parameters:
% y: double, y-coordinate of the mouse cursor at the starting point
% x: double, x-coordinate of the mouse cursor at the starting point
% modifier: char, modifier key held during click
% @li 'shift' - drag all objects on the slice
% @li 'control' - drag only the single object under the cursor
%
% Return values:
%   (none)
%
%|
% @b Examples:
% @code obj.segmentationDragAndDrop(50, 75, 'control');  // drag the object at [y,x]=[50,75] @endcode

% Updates
%

if isempty(modifier)
    obj.brushSelection = [];
    return;
end

% check for switch that disables segmentation tools
if obj.mibModel.disableSegmentation; return; end

obj.brushPrevXY = [x, y];
layer = obj.mibController.cSegmentation.handles.dragLayer.Value;
if strcmp(layer, 'model'); layer = 'labels'; end

% get full dataset dimensions (blockModeSwitch off)
options.blockModeSwitch = 0;
id = obj.mibModel.getActiveId();
[blockHeight, blockWidth] = obj.mibModel.I{id}.getDatasetDimensions('image', [], options);

obj.brushSelection = {};

% get the current layer in block mode (shown area only)
getDataOptions.blockModeSwitch = 1;
selarea = cell2mat(obj.mibModel.getData2D(layer, [], [], [], getDataOptions));
selarea = imresize(selarea, [size(obj.mibModel.Ishown, 1) size(obj.mibModel.Ishown, 2)], 'nearest');

if strcmp(modifier, 'shift')
    if ~obj.mibModel.applySegmentationIn3D
        mode = '2D, Slice';
        obj.mibModel.backup('selection', 0);
    else
        mode = '3D, Stack';
        obj.mibModel.backup('selection', 1);
    end
    obj.brushSelection = selarea;
    obj.brushSelection(selarea > 0) = 1;
elseif strcmp(modifier, 'control')
    if ~obj.mibModel.applySegmentationIn3D
        mode = 'Object2D';
        obj.mibModel.backup('selection', 0);
    else
        mode = 'Object3D';
        obj.mibModel.backup('selection', 1);
    end
    if strcmp(layer, 'labels')
        materialId = selarea(y, x);
        selarea(selarea ~= materialId) = 0;
    end
    selarea = bwselect(selarea, x, y);
    obj.brushSelection = selarea;
end

% count user's points
obj.mibModel.preferences.Users.Tiers.numberOfDragDropMaterials = obj.mibModel.preferences.Users.Tiers.numberOfDragDropMaterials + 1;
notify(obj.mibModel, 'UpdateUserScore');

% set up mouse callbacks for dragging
hFig = obj.UIFigure;
hFig.WindowButtonDownFcn = [];
hFig.Pointer = 'custom';
hFig.PointerShapeCData = nan(16);
hFig.WindowButtonMotionFcn = @(~, ~) obj.gui_WindowDragAndDropMotionFcn(obj.brushSelection);
hFig.WindowButtonUpFcn = @(~, ~) obj.gui_WindowButtonUpDragAndDropFcn(mode);

end
