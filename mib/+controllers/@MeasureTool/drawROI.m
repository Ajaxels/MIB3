function [pixelX, pixelY, wasCancelled] = drawROI(obj, roiType)
% DRAWROI - Interactively draw a ROI on the image axes and return pixel coords.
%
% Syntax:
%   .. code-block:: matlab
%
%       [pixelX, pixelY, wasCancelled] = obj.drawROI(roiType)
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
            roiObject = drawpolygon(axesHandle, 'Closed', false);
        case 'ellipse'
            roiObject = drawellipse(axesHandle);
        case 'point'
            roiObject = drawpoint(axesHandle);
        case 'freehand'
            roiObject = drawfreehand(axesHandle, 'Closed', false);
        otherwise
            cImageDoc.UIFigure.Pointer = 'cross';
            cImageDoc.updateBrushCursor();
            return;
    end
catch
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

% wait for user to finalise (double-click confirms)
try
    wait(roiObject);
catch
    if isvalid(roiObject); delete(roiObject); end
    cImageDoc.UIFigure.Pointer = 'cross';
    cImageDoc.updateBrushCursor();
    return;
end

cImageDoc.UIFigure.Pointer = 'cross';
cImageDoc.updateBrushCursor();

if ~isvalid(roiObject)
    return;
end

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
end
