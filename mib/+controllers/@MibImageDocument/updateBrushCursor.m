function updateBrushCursor(obj, xyCoordinate, lineStyle, isInsideAxes)
% function updateBrushCursor(obj, xyCoordinate, lineStyle, isInsideAxes)
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
%   isInsideAxes: logical, true if mouse is inside axes (default true)
%
% Return values:
%   none
%
% Example:
%   % Update cursor at position [100, 150] with dashed style
%   obj.updateBrushCursor([100, 150], ':', true);
%
%   % Hide cursor when mouse leaves axes
%   obj.updateBrushCursor([], [], false);
%
%   % Use solid line during painting
%   obj.updateBrushCursor([], '-', true);

if nargin < 4; isInsideAxes = true; end
if nargin < 3; lineStyle = []; end
if nargin < 2; xyCoordinate = []; end
if isempty(lineStyle); lineStyle = ':'; end

% Determine visibility: show only when globally enabled AND inside axes
shouldShow = obj.view.brushCursorShow && isInsideAxes;

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
