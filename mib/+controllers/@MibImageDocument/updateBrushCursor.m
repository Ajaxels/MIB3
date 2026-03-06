function updateBrushCursor(obj, xyCoordinate, lineStyle, resetOffset)
% function updateBrushCursor(obj, xyCoordinate, lineStyle, resetOffset)
% Update brush cursor position and visibility
%
% Creates or updates a circular cursor overlay that visualizes
% the current brush size. The cursor follows the mouse and
% changes style based on painting state.
%
% Parameters:
%   xyCoordinate: [x, y] double array, cursor position in axes coordinates
%                 If empty, gets position from CurrentPoint
%   lineStyle: char, line style for cursor
%              ':' = dashed (default, hover mode)
%              '-' = solid (painting mode)
%   resetOffset: logical, when true the cursor offset will be reset, needed when magnification is changed
%
% Return values:
%   none
%
% Example:
%   % Update cursor at position [100, 150] with dashed style
%   obj.updateBrushCursor([100, 150], ':', true);
%
%
%   % Use solid line during painting
%   obj.updateBrushCursor([], '-');

if nargin < 4; resetOffset = false; end
if nargin < 3; lineStyle = []; end
if nargin < 2; xyCoordinate = []; end
if isempty(lineStyle); lineStyle = ':'; end

% Determine visibility: show only when globally enabled AND inside axes
% if Virtual mode, do not show cursor
shouldShow = obj.view.brushCursorShow && obj.isInsideImage && obj.mibModel.I{obj.mibModel.id}.datasetType(1) ~= 'V'; 

if resetOffset; obj.brushCursorOffset = []; end

if shouldShow
    % Get cursor coordinates
    if isempty(xyCoordinate)
        currPoint = obj.handles.imViewAxes.CurrentPoint;
        xy = [round(currPoint(1, 1)), round(currPoint(1, 2))];
    else
        xy = xyCoordinate;
    end

    % Calculate brush cursor offset if not initialized
    if isempty(obj.brushCursorOffset)
        obj.updateBrushCursorOffset();
    end

    % Create or update cursor plot
    if isempty(obj.brushCursor) || ~isvalid(obj.brushCursor)
        % Create cursor line once
        obj.brushCursor = plot(obj.handles.imViewAxes, ...
            xy(1) + obj.brushCursorOffset(1,:), ...
            xy(2) + obj.brushCursorOffset(2,:), ...
            'Color', [0, 0.5, 0], 'LineWidth', 2, ...
            'LineStyle', lineStyle, 'PickableParts', 'none');
    else
        % Fast update: only change position data
        obj.brushCursor.XData = xy(1) + obj.brushCursorOffset(1,:);
        obj.brushCursor.YData = xy(2) + obj.brushCursorOffset(2,:);

        % Update line style if changed
        if ~strcmp(obj.brushCursor.LineStyle, lineStyle)
            obj.brushCursor.LineStyle = lineStyle;
        end

        % Ensure visibility
        obj.brushCursor.Visible = 'on';
    end
else
    % Hide cursor when brushCursorShow is disabled OR mouse is outside axes
    if ~isempty(obj.brushCursor) && isvalid(obj.brushCursor)
        obj.brushCursor.Visible = 'off';
    end
end
end
