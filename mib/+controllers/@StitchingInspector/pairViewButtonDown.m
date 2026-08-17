function pairViewButtonDown(obj, evnt)
% PAIRVIEWBUTTONDOWN - Click/drag state machine of the pair view.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.pairViewButtonDown(evnt)
%
% A **Shift+click** (``SelectionType = 'extend'``; the hover ROI box from
% :func:`pairViewMotion` previews the region) triggers click-to-correlate at
% that spot (:meth:`correlateAtPoint`) - the automated fine-tune. A plain
% DRAG switches the axes to a live two-layer overlay - tile *i* as a grey
% background, tile *j* at 50% alpha following the pointer (per the plan, no
% ``imfuse`` recompute per mouse event) - and applies the released delta as a
% user fix. A plain click without movement does nothing (stray clicks must
% never move tiles). In two-click landmark mode the point is routed to the
% landmark collector instead. A **right-click drag** (``SelectionType =
% 'alt'``) pans the view instead - it never edits alignment, so it works in
% every mode (including two-click and Fix Z) and is never mistaken for a
% tile fix.
%
% Input Arguments:
%   - **evnt** - hit event from an image ``ButtonDownFcn``
%     (``IntersectionPoint`` in pairAxes data coordinates)
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.StitchingInspector.pairViewButtonDown: triggered\n');
end
if ~obj.dataValid() || isempty(obj.currentEdgeIdx); return; end

startPoint = evnt.IntersectionPoint(1:2);   % [x y] in axes data coords
figureHandle = obj.view.gui;
pairAxes = obj.view.handles.pairAxes;
panPoint = []; panXFull = []; panYFull = [];

if strcmp(figureHandle.SelectionType, 'alt')   % right-click = pan, never a tile fix
    beginPan();
    return;
end

if obj.twoClick.active
    obj.twoClickHandlePoint(startPoint);
    return;
end
if isempty(obj.pairStrip); return; end

if strcmp(figureHandle.SelectionType, 'extend')   % Shift+click = correlate in the box
    obj.correlateAtPoint(startPoint);
    return;
end

edge = obj.stitching.edges(obj.currentEdgeIdx);
deltaYX = obj.pairStrip.deltaYX;
displayScale = obj.pairStrip.scale;
% Axes data units are full-res pixels: keep the click-vs-drag threshold at
% ~3 SCREEN pixels regardless of the display downsampling.
dragThreshold = 3 * displayScale;

dragActive = false;
imageJ = [];
baseX = []; baseY = [];

figureHandle.WindowButtonMotionFcn = @(~, ~) onMotion();
figureHandle.WindowButtonUpFcn = @(~, ~) onRelease();

    % -----------------------------------------------------------------
    function point = axesPoint()
        currentPoint = pairAxes.CurrentPoint;
        point = currentPoint(1, 1:2);
    end

    % -----------------------------------------------------------------
    function beginPan()
        % Right-click drag: pans XLim/YLim, clamped to the rendered extent
        % (same border clamp as the mouse-wheel zoom in scrollWheel_Callback)
        % so the view cannot be dragged into empty space.
        panPoint = axesPoint();
        imageHandles = findobj(pairAxes, 'Type', 'image');
        if ~isempty(imageHandles)
            panXFull = [min(cellfun(@(x) min(x), {imageHandles.XData})), ...
                        max(cellfun(@(x) max(x), {imageHandles.XData}))] + [-0.5, 0.5];
            panYFull = [min(cellfun(@(y) min(y), {imageHandles.YData})), ...
                        max(cellfun(@(y) max(y), {imageHandles.YData}))] + [-0.5, 0.5];
        else
            panXFull = pairAxes.XLim;
            panYFull = pairAxes.YLim;
        end
        figureHandle.Pointer = 'hand';
        figureHandle.WindowButtonMotionFcn = @(~, ~) onPanMotion();
        figureHandle.WindowButtonUpFcn = @(~, ~) onPanRelease();
    end

    % -----------------------------------------------------------------
    function onPanMotion()
        point = axesPoint();
        shift = point - panPoint;
        if all(shift == 0); return; end
        newXLimits = pairAxes.XLim - shift(1);
        newYLimits = pairAxes.YLim - shift(2);
        newXLimits = newXLimits - max(0, newXLimits(2) - panXFull(2)) + max(0, panXFull(1) - newXLimits(1));
        newYLimits = newYLimits - max(0, newYLimits(2) - panYFull(2)) + max(0, panYFull(1) - newYLimits(1));
        pairAxes.XLim = newXLimits;
        pairAxes.YLim = newYLimits;
        panPoint = axesPoint();   % re-anchor using the (possibly clamped) new mapping
    end

    % -----------------------------------------------------------------
    function onPanRelease()
        figureHandle.Pointer = 'arrow';
        figureHandle.WindowButtonMotionFcn = @(~, ~) obj.pairViewMotion();
        figureHandle.WindowButtonUpFcn = '';
        % Persist like the wheel zoom, so the panned view survives the next
        % re-render (score refresh, nudge, fix) of this same seam.
        obj.pairZoom = struct('edgeIdx', obj.currentEdgeIdx, ...
            'xLim', pairAxes.XLim, 'yLim', pairAxes.YLim);
    end

    % -----------------------------------------------------------------
    function onMotion()
        point = axesPoint();
        if ~dragActive
            if max(abs(point - startPoint)) < dragThreshold; return; end
            beginDrag();
        end
        if ~isempty(imageJ) && isvalid(imageJ)
            shift = point - startPoint;
            imageJ.XData = baseX + shift(1);
            imageJ.YData = baseY + shift(2);
        end
    end

    % -----------------------------------------------------------------
    function onRelease()
        % Restore the persistent hover handler (the Shift ROI box).
        figureHandle.WindowButtonMotionFcn = @(~, ~) obj.pairViewMotion();
        figureHandle.WindowButtonUpFcn = '';
        if ~dragActive
            return;   % plain click without movement: intentionally a no-op
        end
        shift = axesPoint() - startPoint;               % [dx dy] in full-res px
        if obj.boundaryModeActive()
            % Fix Z boundary view: the drag re-aligns mosaic slice z to z-1.
            newDelta = deltaYX + [shift(2), shift(1)];
            obj.applyZBoundaryFix(newDelta, sprintf('drag [%.1f %.1f]', shift(2), shift(1)));
        else
            newOffsetYX = obj.currentOffsetYX(obj.currentEdgeIdx) + [shift(2), shift(1)];
            obj.applyUserFix([newOffsetYX, obj.fixDz(obj.currentEdgeIdx)], ...
                sprintf('drag [%.1f %.1f]', shift(2), shift(1)));
        end
    end

    % -----------------------------------------------------------------
    function beginDrag()
        % Two-layer full-pair overlay in the tile-i coordinate frame (same
        % frame as renderPairView, so pointer deltas are full-res pixels):
        % tile i grey in place, tile j at 50% alpha following the pointer.
        dragActive = true;
        % Drag exactly the slices on screen (renderPairView stored them).
        sliceA = 1; sliceB = 1;
        if ~isempty(obj.viewSlice) && isequal(obj.viewSlice.edgeIdx, obj.currentEdgeIdx)
            sliceA = obj.viewSlice.sliceA;
            sliceB = obj.viewSlice.sliceB;
        end
        if obj.boundaryModeActive()
            % Fix Z boundary view: both layers are the SAME tile (z-1 and z).
            boundaryFull = obj.readerFcn(obj.viewSlice.boundaryTile);
            tileI = takeSlice(boundaryFull, sliceA);
            tileJ = takeSlice(boundaryFull, sliceB);
        else
            tileI = takeSlice(obj.readerFcn(edge.i), sliceA);
            tileJ = takeSlice(obj.readerFcn(edge.j), sliceB);
        end
        if displayScale > 1
            tileI = imresize(tileI, 1 / displayScale);
            tileJ = imresize(tileJ, 1 / displayScale);
        end
        low = min(min(tileI(:)), min(tileJ(:)));
        high = max(max(tileI(:)), max(tileJ(:)));
        if high <= low; high = low + 1; end

        cla(pairAxes);
        obj.pairImageHandles = [];
        xI = [1, 1 + (size(tileI, 2) - 1) * displayScale];
        yI = [1, 1 + (size(tileI, 1) - 1) * displayScale];
        xJ = xI + deltaYX(2);
        yJ = yI + deltaYX(1);
        image(pairAxes, 'XData', xI, 'YData', yI, ...
            'CData', repmat((tileI - low) / (high - low), 1, 1, 3));
        imageJ = image(pairAxes, 'XData', xJ, 'YData', yJ, ...
            'CData', repmat((tileJ - low) / (high - low), 1, 1, 3));
        imageJ.AlphaData = 0.5;
        baseX = xJ; baseY = yJ;
        set(pairAxes, 'YDir', 'reverse', 'XTick', [], 'YTick', []);
        if ~isempty(obj.pairZoom) && isequal(obj.pairZoom.edgeIdx, obj.currentEdgeIdx)
            % Keep the user's wheel zoom - fine drags are done zoomed in.
            set(pairAxes, 'XLim', obj.pairZoom.xLim, 'YLim', obj.pairZoom.yLim);
        else
            % Filled to the axes' shape like every other view, so the drag
            % preview does not jump to a letterboxed column and back.
            [dragXLim, dragYLim] = obj.pairAxesFillLimits( ...
                [min(xI(1), xJ(1)) - 1, max(xI(2), xJ(2)) + 1], ...
                [min(yI(1), yJ(1)) - 1, max(yI(2), yJ(2)) + 1]);
            set(pairAxes, 'XLim', dragXLim, 'YLim', dragYLim);
        end
        if obj.boundaryModeActive()
            title(pairAxes, sprintf(['Dragging slice %d (50%% alpha) over slice %d - ' ...
                'release to shift the mosaic above'], sliceB, sliceA));
        else
            title(pairAxes, sprintf('Dragging tile %d (50%% alpha) over tile %d - release to fix', ...
                edge.j, edge.i));
        end
    end
end

% =====================================================================
function slice = takeSlice(tile, sliceIdx)
% TAKESLICE - [H W D C] -> single 2D slice (first channel), index clamped.
tile = single(tile(:, :, :, 1));
slice = tile(:, :, min(max(sliceIdx, 1), size(tile, 3)));
end
