function segmentationLasso(obj, modifier)
% SEGMENTATIONLASSO - Do segmentation using the lasso tool.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.segmentationLasso()
%      obj.segmentationLasso(modifier)
%
% Draws an interactive shape (Lasso, Rectangle, Ellipse, or Polyline) on
% the image axes and converts the enclosed area into a selection mask.
% Uses modern MATLAB ROI drawing functions (``drawfreehand``, ``drawrectangle``,
% ``drawellipse``, ``drawpolygon``).
%
% Input Arguments:
%   - **modifier** *(optional)* - [char] specify action on generated selection:
%
%     - ``''`` - make new selection (add to existing)
%     - ``'control'`` - remove selection from existing
%
% Output Arguments:
%   (none)
%
% **Example 1** - draw lasso and add to selection:
%
%   .. code-block:: matlab
%
%      obj.segmentationLasso();
%
% **Example 2** - draw lasso and subtract from selection:
%
%   .. code-block:: matlab
%
%      obj.segmentationLasso('control');
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
obj.mibModel.disableSegmentation = true;
hFig.Pointer = 'cross';

% map lasso type to drawingROI type string used by repositionDrawingROI
drawingROITypeMap = struct('Lasso', 'Freehand', 'Rectangle', 'Rectangle', 'Ellipse', 'Ellipse', 'Polyline', 'Polygon');
if isfield(drawingROITypeMap, type)
    drawingROIType = drawingROITypeMap.(type);
else
    drawingROIType = 'Freehand';
end

cRoi = obj.mibController.cRoi;
if ~isempty(cRoi)
    cRoi.drawingROI.type          = drawingROIType;
    cRoi.drawingROI.dataPos       = [];
    cRoi.drawingROI.repositioning = false;
    cRoi.drawingROI.active        = false;
end

if strcmp(type, 'Polyline')
    %% Custom Stage 1: collect vertices via clicks with right-click pan support
    % drawpolygon exits placement mode on right-click (UIFigure limitation).
    % Collect vertices manually via gui_WindowButtonDownFcn (left-click adds a
    % vertex when placementMode is true) and use uiwait/uiresume for sync.
    % Right-click pan works normally because we never call drawpolygon here.

    cRoi.drawingROI.type              = drawingROIType;  % 'Polygon'
    cRoi.drawingROI.active            = true;
    cRoi.drawingROI.placementMode     = true;
    cRoi.drawingROI.placementVertices = zeros(0, 2);
    cRoi.drawingROI.placementLine     = [];
    cRoi.drawingROI.dataPos           = [];
    cRoi.drawingROI.roi               = [];

    % Capture the initial click position as the first vertex
    pt = axH.CurrentPoint;
    [dataX, dataY] = obj.mibModel.convertMouseToDataCoordinates(pt(1,1), pt(1,2), 'shown');
    cRoi.drawingROI.placementVertices = [dataX, dataY];
    cRoi.drawingROI.dataPos           = cRoi.drawingROI.placementVertices;
    cRoi.updatePlacementLine(axH);

    % Block until double-click, Enter, or Escape calls uiresume
    uiwait(hFig);

    % Retrieve collected vertices and clean up placement state
    placementVertices = cRoi.drawingROI.placementVertices;
    if ~isempty(cRoi.drawingROI.placementLine) && isvalid(cRoi.drawingROI.placementLine)
        delete(cRoi.drawingROI.placementLine);
    end
    if ~isempty(cRoi.drawingROI.rubberBandLine) && isvalid(cRoi.drawingROI.rubberBandLine)
        delete(cRoi.drawingROI.rubberBandLine);
    end
    if ~isempty(cRoi.drawingROI.previewPatch) && isvalid(cRoi.drawingROI.previewPatch)
        delete(cRoi.drawingROI.previewPatch);
    end
    cRoi.drawingROI.placementLine     = [];
    cRoi.drawingROI.rubberBandLine    = [];
    cRoi.drawingROI.previewPatch      = [];
    cRoi.drawingROI.placementVertices = [];
    cRoi.drawingROI.placementMode     = false;

    % Check if cancelled or not enough vertices for a polygon
    if isempty(placementVertices) || size(placementVertices, 1) < 2
        cRoi.drawingROI.active = false;
        obj.mibModel.disableSegmentation = false;
        hFig.WindowButtonDownFcn = @(~, ~) obj.gui_WindowButtonDownFcn();
        hFig.Pointer = 'crosshair';
        return;
    end

    %% Stage 2: create adjustable drawpolygon with collected vertices
    [axX, axY] = obj.mibModel.convertDataToMouseCoordinates( ...
        placementVertices(:,1), placementVertices(:,2), 'shown');
    roi = drawpolygon(axH, 'Position', [axX(:), axY(:)]);

    movingLsn = [];
    movedLsn  = [];
    if isvalid(roi)
        captureF  = @() captureSegLassoDataPos(roi, drawingROIType, cRoi, obj.mibModel);
        movingLsn = addlistener(roi, 'MovingROI', @(~,~) captureF());
        movedLsn  = addlistener(roi, 'ROIMoved',  @(~,~) captureF());
        captureF();
        cRoi.drawingROI.roi    = roi;
        cRoi.drawingROI.active = true;
    end

    %% Stage 3: wait for acceptance (double-click) or cancellation (Escape)
    try
        wait(roi);
    catch
    end

    if ~isempty(movingLsn); delete(movingLsn); end
    if ~isempty(movedLsn);  delete(movedLsn);  end
    cRoi.drawingROI.active = false;

else
    %% Non-Polyline types: use standard interactive draw + wait
    movingLsn = [];
    movedLsn  = [];
    try
        switch type
            case 'Lasso'
                roi = drawfreehand(axH, 'Closed', true);
            case 'Rectangle'
                roi = drawrectangle(axH);
            case 'Ellipse'
                roi = drawellipse(axH);
            otherwise
                roi = drawfreehand(axH, 'Closed', true);
        end
        if isvalid(roi)
            captureF  = @() captureSegLassoDataPos(roi, drawingROIType, cRoi, obj.mibModel);
            movingLsn = addlistener(roi, 'MovingROI', @(~,~) captureF());
            movedLsn  = addlistener(roi, 'ROIMoved',  @(~,~) captureF());
            captureF();
            if ~isempty(cRoi)
                cRoi.drawingROI.roi    = roi;
                cRoi.drawingROI.active = true;
            end
        end
        wait(roi);
    catch
        if ~isempty(movingLsn); delete(movingLsn); end
        if ~isempty(movedLsn);  delete(movedLsn);  end
        if ~isempty(cRoi); cRoi.drawingROI.active = false; end
        obj.mibModel.disableSegmentation = false;
        hFig.WindowButtonDownFcn = @(~, ~) obj.gui_WindowButtonDownFcn();
        hFig.Pointer = 'crosshair';
        return;
    end

    if ~isempty(movingLsn); delete(movingLsn); end
    if ~isempty(movedLsn);  delete(movedLsn);  end
    if ~isempty(cRoi); cRoi.drawingROI.active = false; end
end

% check if ROI is valid (user may have pressed Escape)
if ~isvalid(roi)
    obj.mibModel.disableSegmentation = false;
    hFig.WindowButtonDownFcn = @(~, ~) obj.gui_WindowButtonDownFcn();
    hFig.Pointer = 'crosshair';
    return;
end

% convert ROI vertices to data coordinates and create mask via poly2mask;
% this avoids createMask(roi, imageHandle) which clips to the current CData
% extent and produces wrong results when the ROI extends beyond the view
try
    switch type
        case 'Rectangle'
            p = roi.Position;
            verticesX = [p(1); p(1)+p(3); p(1)+p(3); p(1)];
            verticesY = [p(2); p(2); p(2)+p(4); p(2)+p(4)];
        case 'Ellipse'
            % Use the ROI's own polygon vertices rather than reconstructing the
            % ellipse from Center/SemiAxes/RotationAngle. images.roi.Ellipse uses a
            % CLOCKWISE RotationAngle; the previous manual cos/sin formula used a
            % counter-clockwise rotation matrix, so a rotated ellipse came out
            % mirrored/rotated the wrong way. roi.Vertices is exactly the drawn shape.
            verts = roi.Vertices;
            verticesX = verts(:,1);
            verticesY = verts(:,2);
        otherwise  % Freehand, Polygon
            verts = roi.Position;
            verticesX = verts(:,1);
            verticesY = verts(:,2);
    end
    [dataX, dataY] = obj.mibModel.convertMouseToDataCoordinates(verticesX, verticesY, 'shown');
catch
    delete(roi);
    obj.mibModel.disableSegmentation = false;
    hFig.WindowButtonDownFcn = @(~, ~) obj.gui_WindowButtonDownFcn();
    hFig.Pointer = 'crosshair';
    return;
end
delete(roi);

% restore callbacks and pointer
hFig.WindowButtonDownFcn = @(~, ~) obj.gui_WindowButtonDownFcn();
hFig.Pointer = 'crosshair';
obj.mibModel.disableSegmentation = false;

% --- rasterise the ROI and bound the operation to its bounding box -------
% WSI-safe convention: in the YX orientation, read / rasterise / write only the
% polygon's bounding box at full resolution, so cost scales with the ROI size and
% not the slide size. Other orientations keep the whole-slice path (with a
% warn-only guard). Pyramidal datasets force magFactor=1 so the bbox window is the
% finest level and matches the full-res coordinates from convertMouseToDataCoordinates.
getDataOptions.blockModeSwitch = 0;
getDataOptions.id = id;
if any(obj.mibModel.I{id}.datasetType(1) == ['V' 'B']); getDataOptions.magFactor = 1; end

orientation = obj.mibModel.I{id}.orientation;
boundToBBox = (orientation == 3);   % bound to the ROI bbox in YX (the WSI case)
backupOptions = struct();
backupOptions.id = id;

if boundToBBox
    imgW = obj.mibModel.I{id}.image.width;
    imgH = obj.mibModel.I{id}.image.height;
    xmin = max(1, floor(min(dataX)));  xmax = min(imgW, ceil(max(dataX)));
    ymin = max(1, floor(min(dataY)));  ymax = min(imgH, ceil(max(dataY)));
    if xmax < xmin || ymax < ymin      % ROI entirely outside the image
        notify(obj.mibModel, 'ShowImage');
        return;
    end
    getDataOptions.x = [xmin, xmax];
    getDataOptions.y = [ymin, ymax];
    backupOptions.x  = [xmin, xmax];
    backupOptions.y  = [ymin, ymax];
    % rasterise onto a bbox-sized canvas with coordinates offset to the bbox origin
    selected_mask = uint8(poly2mask(double(dataX) - xmin + 1, double(dataY) - ymin + 1, ...
        ymax - ymin + 1, xmax - xmin + 1));
else
    % non-YX orientation: whole-slice path (warn for huge pyramidal reads)
    if any(obj.mibModel.I{id}.datasetType(1) == ['V' 'B'])
        utils.warnLargeFullResRead(obj.mibModel.I{id}.image.height, obj.mibModel.I{id}.image.width);
    end
    currSelection = cell2mat(obj.mibModel.getData2D('selection', [], [], [], getDataOptions));
    selected_mask = uint8(poly2mask(double(dataX), double(dataY), size(currSelection, 1), size(currSelection, 2)));
    CC = regionprops(selected_mask, 'BoundingBox');
    if isempty(CC); return; end
    bb = CC.BoundingBox;
    if orientation == 1      % ZX: horizontal X, vertical Z
        backupOptions.x = [ceil(bb(1)) ceil(bb(1))+floor(bb(3))-1];
        backupOptions.z = [ceil(bb(2)) ceil(bb(2))+floor(bb(4))-1];
    elseif orientation == 2  % ZY
        backupOptions.y = [ceil(bb(2)) ceil(bb(2))+floor(bb(4))-1];
        backupOptions.z = [ceil(bb(1)) ceil(bb(1))+floor(bb(3))-1];
    end
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
    if boundToBBox
        obj.mibModel.backup('selection', 0, backupOptions);
    else
        obj.mibModel.backup('selection', 0);
    end
    currSelection = cell2mat(obj.mibModel.getData2D('selection', [], [], [], getDataOptions));
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

% -------------------------------------------------------------------------

function captureSegLassoDataPos(roi, type, cRoi, mibModel)
% CAPTURESEGLASSODATAPOS - Capture current ROI position in data-pixel coords.
%
% Called on MovingROI/ROIMoved events and once after initial draw.
% Stores coords in cRoi.drawingROI.dataPos so repositionDrawingROI can
% restore the ROI's axes position after a zoom/pan redraw.

if isempty(roi) || ~isvalid(roi); return; end
if ~isempty(cRoi) && cRoi.drawingROI.repositioning; return; end
try
    switch type
        case 'Rectangle'
            p = roi.Position;   % [x y w h] in axes coords
            [X, Y] = mibModel.convertMouseToDataCoordinates( ...
                [p(1); p(1)+p(3)], [p(2); p(2)+p(4)], 'shown');
            if ~isempty(cRoi); cRoi.drawingROI.dataPos = [X(:), Y(:)]; end
        case 'Ellipse'
            c  = roi.Center;    % [cx cy] in axes coords
            sa = roi.SemiAxes;  % [rx ry] in axes coords
            [cx, cy] = mibModel.convertMouseToDataCoordinates(c(1),       c(2),       'shown');
            [ex, ~]  = mibModel.convertMouseToDataCoordinates(c(1)+sa(1), c(2),       'shown');
            [~,  ey] = mibModel.convertMouseToDataCoordinates(c(1),       c(2)+sa(2), 'shown');
            if ~isempty(cRoi)
                cRoi.drawingROI.dataPos = [cx, cy, abs(ex-cx), abs(ey-cy)];
            end
        otherwise  % Freehand, Polygon
            verts = roi.Position;  % [N×2] in axes coords
            [X, Y] = mibModel.convertMouseToDataCoordinates(verts(:,1), verts(:,2), 'shown');
            if ~isempty(cRoi); cRoi.drawingROI.dataPos = [X(:), Y(:)]; end
    end
catch
end
end
