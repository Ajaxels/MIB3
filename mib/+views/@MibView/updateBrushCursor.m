function updateBrushCursor(obj, xyCoordinate, lineStyle, isInsideAxes)
% function updateBrushCursor(obj, xyCoordinate, lineStyle, isInsideAxes)
% Update brush cursor
%
% Parameters:
% xyCoordinate: [x, y] coordinates for the cursor, when empty gets it from the CurrentPoint
% lineStyle: @b [optional] a char, a line style to use with the brush cursor
%       @li @b ':' (default) - show dashed cursor
%       @li @b '-' % show solid cursor when painting.
% isInsideAxes: @b [optional] true if mouse is inside axes (default true)
%
% Return values:

if nargin < 4; isInsideAxes = true; end
if nargin < 3; lineStyle = []; end
if nargin < 2; xyCoordinate = []; end

if isempty(lineStyle); lineStyle = ':'; end

% get aliases
selectedSet = obj.mibModel.Sets.selectedSet;
imView = obj.handles.imView{selectedSet};

% Determine if cursor should be visible:
% Show only when globally enabled AND mouse is inside axes
shouldShow = obj.brushCursorShow && isInsideAxes;
if shouldShow
    % Get cursor coordinates if not provided
    if isempty(xyCoordinate)
        currPoint = imView.handles.imViewAxes.CurrentPoint;
        xy = [round(currPoint(1, 1)), round(currPoint(1, 2))];
    else
        xy = xyCoordinate;
    end

    % Calculate brush cursor offset (circle points) if not yet initialized
    % obj.brushCursorOffset is a 2×N array containing circle coordinates
    % Row 1: X offsets, Row 2: Y offsets relative to center
    if isempty(obj.brushCursorOffset); obj.updateBrushCursorOffset(); end

    % hold axes
    %hold(imView.handles.imViewAxes, 'on');

    if isempty(imView.brushCursor) || ~isvalid(imView.brushCursor)
        % Create cursor line once
        imView.brushCursor = ...
            plot(imView.handles.imViewAxes, ...
            xy(1) + obj.brushCursorOffset(1,:), xy(2) + obj.brushCursorOffset(2,:), ...
            'Color', [0, 0.5, 0], 'LineWidth', 2, 'LineStyle', lineStyle, 'PickableParts', 'none');
    else
        % Fast update: only change position data
        imView.brushCursor.XData = xy(1) + obj.brushCursorOffset(1,:);
        imView.brushCursor.YData = xy(2) + obj.brushCursorOffset(2,:);
        if ~strcmp(imView.brushCursor.LineStyle, lineStyle)
            % update cursor style if needed
            imView.brushCursor.LineStyle = lineStyle;
        end

        % Ensure cursor is visible
        imView.brushCursor.Visible = 'on';
    end
    
    % release axes
    % hold(imView.handles.imViewAxes, 'off');
else
    % clear the cursor offset
    %obj.brushCursorOffset = [];

    % if isvalid(imView.brushCursor)
    %     imView.brushCursor.Visible = false;
    % else
    %     imView.brushCursor = plot(imView.handles.imViewAxes, [], []);
    % end

    % Hide cursor when:
    % - obj.brushCursorShow is false (globally disabled), OR
    % - Mouse is outside axes boundaries
    if ~isempty(imView.brushCursor) && isvalid(imView.brushCursor)
        imView.brushCursor.Visible = 'off';
    end
end

end