function segmentationLasso(obj, modifier)
% SEGMENTATIONLASSO - Do segmentation using the lasso tool.
%
% Syntax:
%   function segmentationLasso(obj, modifier)
%
% Draws an interactive shape (Lasso, Rectangle, Ellipse, or Polyline) on
% the image axes and converts the enclosed area into a selection mask.
% Uses modern MATLAB ROI drawing functions (drawfreehand, drawrectangle,
% drawellipse, drawpolygon).
%
% Input Arguments:
%   - **modifier** — *(optional)* char, to specify what to do with the generated selection
%     - *empty* - makes new selection (adds to existing)
%     - *'control'* - removes selection from the existing one
%
% Output Arguments:
%   (none)
%
% Usage:
%   Example 1::
%
%     obj.segmentationLasso();             // draw lasso and add to selection
%
%   Example 2::
%
%     obj.segmentationLasso('control');    // draw lasso and subtract from selection
%

% Updates
%

if nargin < 2; modifier = ''; end

% check for switch that disables segmentation tools
if obj.mibModel.disableSegmentation; return; end

switch3d = obj.mibModel.applySegmentationIn3D;
id = obj.mibModel.getActiveId();
selcontour = obj.mibModel.I{id}.getSelectedMaterialIndex();
type = obj.mibController.cSegmentation.handles.lassoType.Value;

hFig = obj.UIFigure;
axH = obj.handles.imViewAxes;

% disable segmentation and change pointer for drawing
obj.mibModel.disableSegmentation = 1;
hFig.WindowButtonDownFcn = [];
hFig.Pointer = 'cross';

% draw the ROI interactively
try
    switch type
        case 'Lasso'
            roi = drawfreehand(axH, 'Closed', true);
        case 'Rectangle'
            roi = drawrectangle(axH);
        case 'Ellipse'
            roi = drawellipse(axH);
        case 'Polyline'
            roi = drawpolygon(axH);
        otherwise
            roi = drawfreehand(axH, 'Closed', true);
    end
    wait(roi);
catch
    % user cancelled or error during drawing
    obj.mibModel.disableSegmentation = 0;
    hFig.WindowButtonDownFcn = @(~, ~) obj.gui_WindowButtonDownFcn();
    hFig.Pointer = 'crosshair';
    return;
end

% check if ROI is valid (user may have pressed Escape)
if ~isvalid(roi)
    obj.mibModel.disableSegmentation = 0;
    hFig.WindowButtonDownFcn = @(~, ~) obj.gui_WindowButtonDownFcn();
    hFig.Pointer = 'crosshair';
    return;
end

% create mask from the ROI (same size as the displayed image)
try
    selected_mask = uint8(createMask(roi, obj.imageHandle));
catch
    delete(roi);
    obj.mibModel.disableSegmentation = 0;
    hFig.WindowButtonDownFcn = @(~, ~) obj.gui_WindowButtonDownFcn();
    hFig.Pointer = 'crosshair';
    return;
end
delete(roi);

% restore callbacks and pointer
hFig.WindowButtonDownFcn = @(~, ~) obj.gui_WindowButtonDownFcn();
hFig.Pointer = 'crosshair';
obj.mibModel.disableSegmentation = 0;

% resize the mask to match the actual data dimensions
getDataOptions.blockModeSwitch = 1;
currSelection = cell2mat(obj.mibModel.getData2D('selection', [], [], [], getDataOptions));
selected_mask = imresize(selected_mask, [size(currSelection, 1) size(currSelection, 2)], 'method', 'nearest');

% calculating bounding box for the backup
CC = regionprops(selected_mask, 'BoundingBox');
if isempty(CC); return; end
bb = CC.BoundingBox;
[axesX, axesY] = obj.mibModel.getAxesLimits();
bb(1) = bb(1) + max([1 ceil(axesX(1))]) - 1;
bb(2) = bb(2) + max([1 ceil(axesY(1))]) - 1;

orientation = obj.mibModel.I{id}.orientation;
if orientation == 3      % XY
    backupOptions.y = [ceil(bb(2)) ceil(bb(2))+floor(bb(4))-1];
    backupOptions.x = [ceil(bb(1)) ceil(bb(1))+floor(bb(3))-1];
elseif orientation == 1  % ZX
    backupOptions.x = [ceil(bb(2)) ceil(bb(2))+floor(bb(4))-1];
    backupOptions.z = [ceil(bb(1)) ceil(bb(1))+floor(bb(3))-1];
elseif orientation == 2  % ZY
    backupOptions.y = [ceil(bb(2)) ceil(bb(2))+floor(bb(4))-1];
    backupOptions.z = [ceil(bb(1)) ceil(bb(1))+floor(bb(3))-1];
end

if switch3d     % 3D case
    wb = uiprogressdlg(obj.view.gui, 'Value', 0, 'Message', 'Please wait', 'Title', 'Lasso segmentation');
    obj.mibModel.backup('selection', 1, backupOptions);
    currSelection = cell2mat(obj.mibModel.getData3D('selection', [], [], [], getDataOptions));
    selarea = zeros(size(currSelection), 'uint8');
    for layer_id = 1:size(selarea, 3)
        selarea(:,:,layer_id) = selected_mask;
    end
    wb.Value = 0.3;

    % limit to the selected material of the model
    if obj.mibModel.I{id}.restrictSelectionToMaterial == 1
        currModel = cell2mat(obj.mibModel.getData3D('labels', [], [], selcontour, getDataOptions));
        selarea = bitand(selarea, currModel);
    end
    wb.Value = 0.6;

    % limit selection to the masked area
    if obj.mibModel.I{id}.restrictSelectionToMask && obj.mibModel.I{id}.maskExist
        currModel = cell2mat(obj.mibModel.getData3D('mask', [], 3, [], getDataOptions));
        selarea = bitand(selarea, currModel);
    end
    wb.Value = 0.9;

    if isempty(modifier) || strcmp(modifier, 'shift')    % combines selections
        obj.mibModel.setData3D({bitor(selarea, currSelection)}, 'selection', [], [], [], getDataOptions);
    elseif strcmp(modifier, 'control')  % subtracts selections
        currSelection(selarea==1) = 0;
        obj.mibModel.setData3D({currSelection}, 'selection', [], [], [], getDataOptions);
    end
    wb.Value = 1;
    close(wb);
else    % 2D case
    obj.mibModel.backup('selection', 0);
    selarea = selected_mask;

    % limit to the selected material of the model
    if obj.mibModel.I{id}.restrictSelectionToMaterial == 1
        currModel = cell2mat(obj.mibModel.getData2D('labels', [], [], selcontour, getDataOptions));
        selarea = bitand(selarea, currModel);
    end

    % limit selection to the masked area
    if obj.mibModel.I{id}.restrictSelectionToMask && obj.mibModel.I{id}.maskExist
        currModel = cell2mat(obj.mibModel.getData2D('mask', [], [], selcontour, getDataOptions));
        selarea = bitand(selarea, currModel);
    end

    if isempty(modifier) || strcmp(modifier, 'shift')    % combines selections
        obj.mibModel.setData2D({bitor(currSelection, selarea)}, 'selection', [], [], selcontour, getDataOptions);
    elseif strcmp(modifier, 'control')  % subtracts selections
        currSelection(selarea==1) = 0;
        obj.mibModel.setData2D({currSelection}, 'selection', [], [], selcontour, getDataOptions);
    end
end

% count user's points
obj.mibModel.preferences.Users.Tiers.numberOfLassos = obj.mibModel.preferences.Users.Tiers.numberOfLassos + 1;
notify(obj.mibModel, 'UpdateUserScore');

notify(obj.mibModel, 'ShowImage');

end
