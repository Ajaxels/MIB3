function updateBrushCursor(obj, xyCoordinate, lineStyle, resetOffset)
% UPDATEBRUSHCURSOR - Update brush cursor position and visibility.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.updateBrushCursor(xyCoordinate, lineStyle, resetOffset)
%
% Creates or updates a circular cursor overlay that visualizes
% the current brush size. The cursor follows the mouse and
% changes style based on painting state.
%
% Input Arguments:
%   - **xyCoordinate** *(optional)* — [double] ``[x, y]`` cursor position in axes coordinates; if empty, uses ``CurrentPoint``
%   - **lineStyle** *(optional)* — [char] line style for cursor (default: ``':'``):
%
%     - ``':'`` — dashed line (hover mode)
%     - ``'-'`` — solid line (painting mode)
%
%   - **resetOffset** *(optional)* — [logical] reset cursor offset when ``true``, needed when magnification changes (default: ``false``)
%
% Output Arguments:
%   (none)
%
% **Example 1** — update cursor at specific position with dashed style:
%
%   .. code-block:: matlab
%
%      obj.updateBrushCursor([100, 150], ':', true);
%
% **Example 2** — use solid line during painting:
%
%   .. code-block:: matlab
%
%      obj.updateBrushCursor([], '-');
%

if nargin < 4; resetOffset = false; end
if nargin < 3; lineStyle = []; end
if nargin < 2; xyCoordinate = []; end
if isempty(lineStyle); lineStyle = ':'; end

% Determine visibility: show only when globally enabled AND inside axes
% if Virtual mode, do not show cursor.
% Use this document's local id — mibModel.id is stale in split view.
localId = obj.mibModel.Sets.selectedDataset(obj.setOfDatasetsIndex) + ...
    (obj.setOfDatasetsIndex - 1) * obj.mibModel.Sets.datasetsInSet;
shouldShow = obj.view.brushCursorShow && obj.isInsideImage && obj.mibModel.I{localId}.datasetType(1) ~= 'V';

if resetOffset; obj.brushCursorOffset = []; end

if shouldShow
    % Get cursor coordinates
    if isempty(xyCoordinate)
        currPoint = obj.handles.imViewAxes.CurrentPoint;
        xy = [round(currPoint(1, 1)), round(currPoint(1, 2))];
    else
        xy = xyCoordinate;
    end

    % Recalculate brush cursor offset when not yet initialised or when the
    % magnification has changed (e.g. after switching to a panel with a
    % different zoom level — wasInsideAxes cannot detect this because the
    % callback simply stops firing while the cursor is in another panel).
    currentMagFactor = obj.mibModel.I{localId}.magFactor;
    if isempty(obj.brushCursorOffset) || ...
            isempty(obj.brushCursorMagFactor) || ...
            obj.brushCursorMagFactor ~= currentMagFactor
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

        % Ensure visibility (guard against unnecessary graphics invalidation)
        if obj.brushCursor.Visible ~= "on"
            obj.brushCursor.Visible = 'on';
        end
    end
else
    % Hide cursor when brushCursorShow is disabled OR mouse is outside axes
    if ~isempty(obj.brushCursor) && isvalid(obj.brushCursor)
        obj.brushCursor.Visible = 'off';
    end
end
end
