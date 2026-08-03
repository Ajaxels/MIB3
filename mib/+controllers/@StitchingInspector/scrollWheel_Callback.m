function scrollWheel_Callback(obj, evnt)
% SCROLLWHEEL_CALLBACK - Mouse wheel: zoom the pair view / resize the ROI box.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.scrollWheel_Callback(evnt)
%
% While ``Shift`` is held (the hover ROI box is showing), the wheel adjusts
% ``ROIsizeSpinner`` — scroll up = larger box — clamped to the spinner's
% limits, and the box under the cursor resizes live.
%
% Without ``Shift``, the wheel ZOOMS the pair view about the cursor (scroll
% up = zoom in). Zooming out beyond the rendered extent snaps back to fit;
% the zoom survives re-renders of the same seam (nudges, drags, fixes — see
% :func:`renderPairView`) and is reset by :func:`fitView_Callback` (``F``)
% or by selecting another seam. Wheel events outside the pair view are
% ignored.
%
% Input Arguments:
%   - **evnt** — ScrollWheelData from ``WindowScrollWheelFcn``
%     (``VerticalScrollCount`` > 0 = scroll down)
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.StitchingInspector.scrollWheel_Callback: triggered\n');
end
if obj.shiftDown
    % ---- Shift+wheel: resize the correlation ROI box -----------------------
    if ~obj.hasWidget('ROIsizeSpinner'); return; end

    spinner = obj.view.handles.ROIsizeSpinner;
    step = 16;
    if isprop(spinner, 'Step') && ~isempty(spinner.Step)
        step = spinner.Step;
    end
    newValue = spinner.Value - evnt.VerticalScrollCount * step;
    newValue = max(spinner.Limits(1), min(spinner.Limits(2), newValue));
    spinner.Value = newValue;

    obj.pairViewMotion();   % resize the hover box live
    return;
end

% ---- plain wheel: zoom the pair view about the cursor -----------------------
if ~obj.hasWidget('pairAxes'); return; end
pairAxes = obj.view.handles.pairAxes;
imageHandles = findobj(pairAxes, 'Type', 'image');
if isempty(imageHandles); return; end

point = pairAxes.CurrentPoint(1, 1:2);
xLimits = pairAxes.XLim;
yLimits = pairAxes.YLim;
if point(1) < xLimits(1) || point(1) > xLimits(2) || ...
        point(2) < yLimits(1) || point(2) > yLimits(2)
    return;   % cursor is not over the pair view
end

% Full extent of everything rendered (any overlay mode, incl. two-click), with
% the half-pixel image border.
xFull = [min(cellfun(@(x) min(x), {imageHandles.XData})), ...
         max(cellfun(@(x) max(x), {imageHandles.XData}))] + [-0.5, 0.5];
yFull = [min(cellfun(@(y) min(y), {imageHandles.YData})), ...
         max(cellfun(@(y) max(y), {imageHandles.YData}))] + [-0.5, 0.5];

zoomFactor = 1.25 ^ evnt.VerticalScrollCount;   % <1 zooms in, >1 zooms out
newXLimits = point(1) + (xLimits - point(1)) * zoomFactor;
newYLimits = point(2) + (yLimits - point(2)) * zoomFactor;

% Do not zoom in past ~8 full-res pixels across.
minRange = 8;
if zoomFactor < 1 && (diff(newXLimits) < minRange || diff(newYLimits) < minRange)
    return;
end

if diff(newXLimits) >= diff(xFull) || diff(newYLimits) >= diff(yFull)
    % Zoomed out to (or beyond) the full extent: snap back to fit.
    obj.fitView_Callback();
    return;
end

% Keep the window inside the rendered extent while panning at the borders.
newXLimits = newXLimits - max(0, newXLimits(2) - xFull(2)) + max(0, xFull(1) - newXLimits(1));
newYLimits = newYLimits - max(0, newYLimits(2) - yFull(2)) + max(0, yFull(1) - newYLimits(1));

pairAxes.XLim = newXLimits;
pairAxes.YLim = newYLimits;
obj.pairZoom = struct('edgeIdx', obj.currentEdgeIdx, ...
    'xLim', newXLimits, 'yLim', newYLimits);
end
