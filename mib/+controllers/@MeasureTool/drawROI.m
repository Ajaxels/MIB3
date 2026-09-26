function [pixelX, pixelY, wasCancelled] = drawROI(obj, roiType, finetuneCheck, maxVertices, initialDataPos)
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
%   - **roiType** - [char] one of:
%
%     - ``'line'``     - two-endpoint line (``drawline``)
%     - ``'polyline'`` - open N-point polygon (``drawpolygon``)
%     - ``'ellipse'``  - ellipse; returns boundary vertices (``drawellipse``)
%     - ``'point'``    - single point (``drawpoint``)
%     - ``'freehand'`` - open freehand path (``drawfreehand``)
%
%   - **finetuneCheck** - *(optional)* [logical] when ``false`` the ROI is
%     auto-accepted as soon as drawing finishes (no double-click required).
%     Default: ``true``.
%   - **maxVertices** - *(optional)* [double] maximum number of vertices for
%     ``'polyline'`` drawings; drawing ends automatically when this count is
%     reached.  Default: ``Inf`` (unlimited, finish with a double-click).
%     ``drawpolyline`` has no vertex limit, so with a finite count the
%     drawing is ended from a ``WindowMouseRelease`` listener once that many
%     vertices are placed, and an ``images.roi.Polyline`` is rebuilt from
%     them; with ``finetuneCheck = true`` that polyline is then adjustable
%     until a double-click, otherwise it is accepted at once.
%
% Output Arguments:
%   - **pixelX** - [double column] X coordinates in data pixel space.
%   - **pixelY** - [double column] Y coordinates in data pixel space.
%   - **wasCancelled** - [logical] true when the user pressed Escape.
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

if nargin < 3 || isempty(finetuneCheck);  finetuneCheck  = true; end
if nargin < 4 || isempty(maxVertices);   maxVertices    = Inf;  end
if nargin < 5;                           initialDataPos = [];   end

pixelX      = [];
pixelY      = [];
wasCancelled = true;

cImageDoc = obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet};
axesHandle = cImageDoc.handles.imViewAxes;

% hide brush cursor and set cross cursor during draw
if ~isempty(cImageDoc.brushCursor) && isvalid(cImageDoc.brushCursor)
    cImageDoc.brushCursor.Visible = false;
end
cImageDoc.UIFigure.Pointer = 'cross';

try
    if isempty(initialDataPos)
        switch roiType
            case 'line'
                roiObject = drawline(axesHandle);
            case 'polyline'
                if isfinite(maxVertices)
                    roiObject = drawPolylineWithVertexLimit(maxVertices);
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
    else
        if ~finetuneCheck
            % Recalculate mode: return stored pixel coordinates directly - no drawing.
            % The caller recomputes the measurement value with the current pixSize.
            pixelX       = initialDataPos(:, 1);
            pixelY       = initialDataPos(:, 2);
            wasCancelled = false;
            cImageDoc.UIFigure.Pointer = 'cross';
            cImageDoc.updateBrushCursor();
            return;
        end
        % Edit mode - create pre-positioned ROI and wait for user confirmation
        switch roiType
            case {'line', 'polyline', 'freehand', 'point'}
                [screenX, screenY] = obj.mibModel.convertDataToMouseCoordinates( ...
                    initialDataPos(:,1), initialDataPos(:,2), 'shown');
                screenPos = [screenX(:), screenY(:)];
        end
        switch roiType
            case 'line'
                roiObject = images.roi.Line(axesHandle, 'Position', screenPos);
            case 'polyline'
                roiObject = images.roi.Polyline(axesHandle, 'Position', screenPos);
            case 'point'
                roiObject = images.roi.Point(axesHandle, 'Position', screenPos(1,:));
            case 'freehand'
                roiObject = images.roi.Freehand(axesHandle, 'Position', screenPos, 'Closed', false);
            case 'ellipse'
                % initialDataPos = [cx, cy, sax, say] in data pixel space
                [scx, scy] = obj.mibModel.convertDataToMouseCoordinates( ...
                    initialDataPos(1), initialDataPos(2), 'shown');
                [sex, ~]   = obj.mibModel.convertDataToMouseCoordinates( ...
                    initialDataPos(1)+initialDataPos(3), initialDataPos(2), 'shown');
                [~,   sey] = obj.mibModel.convertDataToMouseCoordinates( ...
                    initialDataPos(1), initialDataPos(2)+initialDataPos(4), 'shown');
                roiObject  = drawellipse(axesHandle, ...
                    'Center', [scx, scy], 'SemiAxes', [sex-scx, sey-scy], ...
                    'FixedAspectRatio', true, 'AspectRatio', 1);
            otherwise
                cImageDoc.UIFigure.Pointer = 'cross';
                cImageDoc.updateBrushCursor();
                return;
        end
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
% when off, the draw call already returned after placing all points so no wait needed.
if finetuneCheck
    try
        wait(roiObject);
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
                otherwise   % Polyline / Lasso / Point - Nx2 vertex array
                    verts = roiObject.Position;
                    [X, Y] = obj.mibModel.convertMouseToDataCoordinates(verts(:,1), verts(:,2), 'shown');
                    cRoi.drawingROI.dataPos = [X(:), Y(:)];
            end
        catch
        end
    end

    function polylineObject = drawPolylineWithVertexLimit(nVertices)
        % Interactive polyline drawing (as drawpolyline) that finishes by
        % itself once nVertices vertices are placed. images.roi.Polyline has
        % no vertex-limit option and fires no ROI event while being drawn, but
        % its Position grows by one row per click and the figure's
        % WindowMouseRelease event still fires. On the release that places
        % the last vertex the vertices are copied, the drawing ROI is deleted
        % and the figure's uiwait is resumed so draw() returns; a fresh
        % Polyline is then built from the copied vertices. Escape, or a
        % double-click before the limit, ends draw() as usual; the short ROI
        % is deleted and the caller treats the deleted handle as cancelled.
        % The listener is deleted explicitly as soon as draw() returns: an
        % onCleanup here never fires, because the listener's callback keeps
        % this workspace alive, and a surviving listener would delete the
        % rebuilt polyline on the first vertex drag during fine-tuning.
        drawingPolyline = images.roi.Polyline(axesHandle);
        limitedPosition = [];
        releaseListener = addlistener(cImageDoc.UIFigure, 'WindowMouseRelease', ...
            @(~,~) finishAtVertexLimit());
        try
            draw(drawingPolyline);
        catch drawError
            delete(releaseListener);
            rethrow(drawError);
        end
        delete(releaseListener);
        if isempty(limitedPosition)
            % Escape or a double-click before the limit: an incomplete
            % polyline is useless for a fixed vertex count, so cancel instead
            % of offering it for fine-tuning
            if isvalid(drawingPolyline); delete(drawingPolyline); end
            polylineObject = drawingPolyline;
        else
            polylineObject = images.roi.Polyline(axesHandle, 'Position', limitedPosition);
        end

        function finishAtVertexLimit()
            if isvalid(drawingPolyline) && size(drawingPolyline.Position, 1) >= nVertices
                limitedPosition = drawingPolyline.Position(1:nVertices, :);
                delete(drawingPolyline);
                % draw() blocks in uiwait on the axes' figure; deleting the ROI
                % alone does not always release it (it did in a bare uifigure,
                % not in the MIB image document), so resume explicitly
                uiresume(ancestor(axesHandle, 'figure'));
            end
        end
    end

    function cleanupDrawingROI()
        delete(movingLsn);
        delete(movedLsn);
        cRoi.drawingROI.active = false;
        cRoi.drawingROI.roi    = [];
    end
end
