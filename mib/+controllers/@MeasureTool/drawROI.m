function [pixelX, pixelY, wasCancelled] = drawROI(obj, roiType, finetuneCheck, maxVertices)
% DRAWROI - Interactively draw a ROI on the image axes and return pixel coords.
%
% Syntax:
%   .. code-block:: matlab
%
%       [pixelX, pixelY, wasCancelled] = obj.drawROI(roiType)
%       [pixelX, pixelY, wasCancelled] = obj.drawROI(roiType, finetuneCheck)
%       [pixelX, pixelY, wasCancelled] = obj.drawROI(roiType, finetuneCheck, maxVertices)
%
% Creates an ``images.roi.*`` object on the current image axes using the
% MATLAB R2022b+ drawing functions, waits for the user to finalise the
% placement (double-click), then converts the result from axes space to
% data pixel coordinates.  Pressing Escape cancels and returns empty
% arrays with ``wasCancelled = true``.
%
% Input Arguments:
%   - **roiType** — [char] one of:
%
%     - ``'line'``     — two-endpoint line (``drawline``)
%     - ``'polyline'`` — open N-point polygon (``drawpolygon``)
%     - ``'ellipse'``  — ellipse; returns boundary vertices (``drawellipse``)
%     - ``'point'``    — single point (``drawpoint``)
%     - ``'freehand'`` — open freehand path (``drawfreehand``)
%
%   - **finetuneCheck** — *(optional)* [logical] when ``false`` the ROI is
%     auto-accepted as soon as drawing finishes (no double-click required).
%     Default: ``true``.
%   - **maxVertices** — *(optional)* [double] maximum number of vertices for
%     ``'polyline'`` drawings; drawing ends automatically when this count is
%     reached.  Default: ``Inf`` (unlimited).
%
% Output Arguments:
%   - **pixelX** — [double column] X coordinates in data pixel space.
%   - **pixelY** — [double column] Y coordinates in data pixel space.
%   - **wasCancelled** — [logical] true when the user pressed Escape.
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     [X, Y, cancelled] = obj.drawROI('line');
%     if cancelled; return; end
%

if nargin < 3; finetuneCheck = true; end
if nargin < 4; maxVertices = Inf; end

pixelX      = [];
pixelY      = [];
wasCancelled = true;

cImageDoc = obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet};
axesHandle = cImageDoc.handles.imViewAxes;

% hide brush cursor and set cross cursor during draw
if ~isempty(cImageDoc.brushCursor)
    cImageDoc.brushCursor.Visible = false;
end
cImageDoc.UIFigure.Pointer = 'cross';

try
    switch roiType
        case 'line'
            roiObject = drawline(axesHandle);
        case 'polyline'
            if isfinite(maxVertices)
                roiObject = drawpolygon(axesHandle, 'MaxVertices', maxVertices);
            else
                roiObject = drawpolyline(axesHandle);
            end
        case 'ellipse'
            roiObject = drawellipse(axesHandle, 'FixedAspectRatio', true, 'AspectRatio', 1);
        case 'point'
            roiObject = drawpoint(axesHandle);
        case 'freehand'
            roiObject = drawfreehand(axesHandle, 'Closed', false);
        otherwise
            cImageDoc.UIFigure.Pointer = 'cross';
            cImageDoc.updateBrushCursor();
            return;
    end
catch err
    cImageDoc.UIFigure.Pointer = 'cross';
    cImageDoc.updateBrushCursor();
    return;
end

% user pressed Escape before placing any points
if ~isvalid(roiObject)
    cImageDoc.UIFigure.Pointer = 'cross';
    cImageDoc.updateBrushCursor();
    return;
end

% --- Register in cRoi.drawingROI for zoom/pan repositioning during wait ---
% Reuses the existing MibRoi.drawingROI infrastructure: repositionDrawingROI()
% (called from showImage after every redraw) and the pan-start reposition in
% gui_WindowButtonDownFcn keep the ROI anchored to the data pixels it was
% drawn on while the user pans/zooms before double-clicking to confirm.
typeMap = struct('line','Polyline', 'polyline','Polyline', ...
                 'freehand','Lasso', 'point','Polyline', 'ellipse','Ellipse');
mappedType = typeMap.(roiType);

cRoi = obj.mibController.cRoi;
cRoi.drawingROI.roi           = roiObject;
cRoi.drawingROI.type          = mappedType;
cRoi.drawingROI.dataPos       = [];
cRoi.drawingROI.repositioning = false;
cRoi.drawingROI.active        = true;

% --- Optional live intensity-profile preview ---
% When previewIntensityCheck is on AND the measurement type produces a profile
% (line / polyline / freehand), cache the current 2-D image and refresh
% obj.view.handles.profileAxes on every MovingROI event using the live
% data-pixel vertices in cRoi.drawingROI.dataPos.
profilePreviewEnabled = false;
cachedImage           = [];
if any(strcmp(roiType, {'line', 'polyline', 'freehand'})) && ...
        obj.view.handles.previewIntensityCheck.Value
    try
        previewColCh    = obj.view.handles.imageColChDropdown.ValueIndex - 1;
        previewDatasetId = obj.mibModel.getActiveId();
        imgCell = obj.mibModel.getData2D('image', [], [], previewColCh, ...
            struct('id', previewDatasetId));
        cachedImage = imgCell{1};
        profilePreviewEnabled = true;
    catch
    end
end

movingLsn = addlistener(roiObject, 'MovingROI', @(~,~) onRoiUpdate());
movedLsn  = addlistener(roiObject, 'ROIMoved',  @(~,~) onRoiUpdate());
onRoiUpdate();

% when fine-tune is on, wait for the user to double-click to confirm;
% when off, drawline already returned after placing all points so no wait needed.
% when maxVertices is finite, poll until that many vertices are placed instead
% of calling wait() (MATLAB ROI objects have no MaxVertices property).
if finetuneCheck
    try
        if isfinite(maxVertices)
            while isvalid(roiObject) && size(roiObject.Position, 1) < maxVertices
                drawnow;
                pause(0.05);
            end
        else
            wait(roiObject);
        end
    catch
        cleanupDrawingROI();
        if isvalid(roiObject); delete(roiObject); end
        cImageDoc.UIFigure.Pointer = 'cross';
        cImageDoc.updateBrushCursor();
        return;
    end
    if ~isvalid(roiObject)
        cleanupDrawingROI();
        cImageDoc.UIFigure.Pointer = 'cross';
        cImageDoc.updateBrushCursor();
        return;
    end
end

cleanupDrawingROI();
cImageDoc.UIFigure.Pointer = 'cross';
cImageDoc.updateBrushCursor();

% extract axes-space position
switch roiType
    case 'ellipse'
        % roi.Vertices gives the boundary polygon in axes space
        screenPos = roiObject.Vertices;
    otherwise
        screenPos = roiObject.Position;   % Nx2 [x y] axes coords
end

delete(roiObject);

if isempty(screenPos) || size(screenPos, 2) < 2
    return;
end

% convert axes space → data pixel space
[pixelX, pixelY] = obj.mibModel.convertMouseToDataCoordinates( ...
    screenPos(:, 1), screenPos(:, 2), 'shown');

pixelX       = pixelX(:);
pixelY       = pixelY(:);
wasCancelled = false;

    % --- Nested helpers ---
    function onRoiUpdate()
        % Single dispatch fired by MovingROI / ROIMoved listeners and by the
        % initial post-creation call.  Keeps the drawingROI cache in sync and
        % refreshes the live intensity profile when enabled.
        captureDataPos();
        if profilePreviewEnabled; updateIntensityPreview(); end
    end

    function updateIntensityPreview()
        % Replot obj.view.handles.profileAxes from the current data-pixel
        % vertices stored in cRoi.drawingROI.dataPos.
        if ~isvalid(roiObject); return; end
        dp = cRoi.drawingROI.dataPos;
        if isempty(dp) || size(dp, 1) < 2; return; end
        try
            profileData = core.Measurements.computeProfile(cachedImage, dp(:,1), dp(:,2), [], 0);
        catch
            return;
        end
        plotAxes = obj.view.handles.profileAxes;
        cla(plotAxes);
        if isempty(profileData) || ~isnumeric(profileData) || size(profileData, 1) < 2
            return;
        end
        distanceVec = profileData(1, :);
        nChannels   = size(profileData, 1) - 1;
        hold(plotAxes, 'on');
        for channelIdx = 1:nChannels
            plot(plotAxes, distanceVec, profileData(channelIdx + 1, :));
        end
        hold(plotAxes, 'off');
        xlabel(plotAxes, 'Distance (px)');
        ylabel(plotAxes, 'Intensity');
    end

    function captureDataPos()
        % Convert the live ROI's current axes coords to data pixels and
        % cache them in cRoi.drawingROI.dataPos.  Called on every MovingROI
        % and ROIMoved event so repositionDrawingROI() can map back into
        % new axes coords whenever the viewport changes.
        if ~isvalid(roiObject) || cRoi.drawingROI.repositioning; return; end
        try
            switch mappedType
                case 'Ellipse'
                    c  = roiObject.Center;
                    sa = roiObject.SemiAxes;
                    [cx, cy] = obj.mibModel.convertMouseToDataCoordinates(c(1),       c(2),       'shown');
                    [ex, ~]  = obj.mibModel.convertMouseToDataCoordinates(c(1)+sa(1), c(2),       'shown');
                    [~,  ey] = obj.mibModel.convertMouseToDataCoordinates(c(1),       c(2)+sa(2), 'shown');
                    cRoi.drawingROI.dataPos = [cx, cy, ex-cx, ey-cy];
                otherwise   % Polyline / Lasso / Point — Nx2 vertex array
                    verts = roiObject.Position;
                    [X, Y] = obj.mibModel.convertMouseToDataCoordinates(verts(:,1), verts(:,2), 'shown');
                    cRoi.drawingROI.dataPos = [X(:), Y(:)];
            end
        catch
        end
    end

    function cleanupDrawingROI()
        delete(movingLsn);
        delete(movedLsn);
        cRoi.drawingROI.active = false;
        cRoi.drawingROI.roi    = [];
    end
end
