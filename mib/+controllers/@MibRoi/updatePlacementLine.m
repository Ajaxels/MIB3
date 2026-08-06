function updatePlacementLine(obj, axH)
% UPDATEPLACEMENTLINE - Update polygon outline during custom Polyline placement.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.updatePlacementLine(axH)
%
% Converts data-pixel vertices stored in ``obj.drawingROI.placementVertices``
% to current axes coordinates and creates or updates the placement line
% object on the given axes.
%
% Input Arguments:
%   - **axH** - handle to the image axes (``imViewAxes``)
%
% Output Arguments:
%   (none)
%

vertices = obj.drawingROI.placementVertices;
if isempty(vertices)
    if ~isempty(obj.drawingROI.placementLine) && isvalid(obj.drawingROI.placementLine)
        delete(obj.drawingROI.placementLine);
    end
    obj.drawingROI.placementLine = [];
    return;
end

[axX, axY] = obj.mibModel.convertDataToMouseCoordinates(vertices(:,1), vertices(:,2), 'shown');

if size(axX, 1) >= 2
    plotX = [axX(:); axX(1)];
    plotY = [axY(:); axY(1)];
else
    plotX = axX(:);
    plotY = axY(:);
end

lineH = obj.drawingROI.placementLine;
if isempty(lineH) || ~isvalid(lineH)
    lineH = line(axH, plotX, plotY, ...
        'Color', [0 0.447 0.741], 'LineWidth', 1.5, 'LineStyle', '-', ...
        'Marker', 'o', 'MarkerSize', 6, 'MarkerFaceColor', [0 0.447 0.741], ...
        'Tag', 'polylinePlacement', 'HitTest', 'off', 'PickableParts', 'none');
    obj.drawingROI.placementLine = lineH;
else
    lineH.XData = plotX;
    lineH.YData = plotY;
end

end
