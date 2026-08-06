function pairViewMotion(obj)
% PAIRVIEWMOTION - Hover handler: with Shift held, the cursor becomes the ROI box.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.pairViewMotion()
%
% Wired as the figure's persistent ``WindowButtonMotionFcn``. While ``Shift``
% is held (tracked by :func:`keyPress_Callback` / :func:`keyRelease_Callback`)
% a yellow box of exactly ``ROIsizeSpinner`` full-res pixels follows the
% cursor over the pair view - a live preview of the region that Shift+click
% hands to click-to-correlate (:func:`correlateAtPoint`). The box is
% click-transparent (``PickableParts = 'none'``) so the click lands on the
% image beneath it. Hidden when Shift is up or the cursor leaves the axes.
%

if isempty(obj.view) || ~isvalid(obj.view.gui); return; end
if ~obj.shiftDown || ~obj.dataValid() || isempty(obj.currentEdgeIdx) || ...
        isempty(obj.pairStrip) || ~obj.hasWidget('pairAxes')
    hideBox(obj);
    return;
end

pairAxes = obj.view.handles.pairAxes;
currentPoint = pairAxes.CurrentPoint;
point = currentPoint(1, 1:2);
xLimits = pairAxes.XLim;
yLimits = pairAxes.YLim;
if point(1) < xLimits(1) || point(1) > xLimits(2) || ...
        point(2) < yLimits(1) || point(2) > yLimits(2)
    hideBox(obj);
    return;
end

roiSize = 128;
if obj.hasWidget('ROIsizeSpinner')
    roiSize = obj.view.handles.ROIsizeSpinner.Value;
end
half = roiSize / 2;   % axes data units are full-res tile-i pixels
boxX = point(1) + [-half, half, half, -half, -half];
boxY = point(2) + [-half, -half, half, half, -half];

if isempty(obj.roiBoxHandle) || ~isvalid(obj.roiBoxHandle)
    obj.roiBoxHandle = line(pairAxes, boxX, boxY, 'Color', [1 1 0], ...
        'LineWidth', 1, 'HitTest', 'off', 'PickableParts', 'none');
else
    set(obj.roiBoxHandle, 'XData', boxX, 'YData', boxY, 'Visible', 'on');
end
end

% =====================================================================
function hideBox(obj)
if ~isempty(obj.roiBoxHandle) && isvalid(obj.roiBoxHandle)
    obj.roiBoxHandle.Visible = 'off';
end
end
