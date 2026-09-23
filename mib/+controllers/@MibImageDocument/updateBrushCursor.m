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
% With ``preferences.Colors.CursorMaterialColor`` on (the default), the cursor is
% drawn in the color of the target of the brush stroke, i.e. the ``'AddTo'``
% column of the materials table: a material takes its color from
% ``labels.materialColors``, Mask from ``preferences.Colors.MaskColor``.
% It falls back to dark green (``[0, 0.5, 0]``) when the preference is off, when
% Exterior is selected, when no model exists, or when the material index falls
% outside the palette.
%
% The color is re-evaluated on every call, so the cursor follows a change of the
% selected material. Because the call is normally driven by mouse motion, a
% change made from the keyboard or from the materials table has to trigger it -
% see ``MibSegmentation.materialsTable_CellSelectionCallback``.
%
% Input Arguments:
%   - **xyCoordinate** *(optional)* - [double] ``[x, y]`` cursor position in axes coordinates; if empty, uses ``CurrentPoint``
%   - **lineStyle** *(optional)* - [char] line style for cursor (default: ``':'``):
%
%     - ``':'`` - dashed line (hover mode)
%     - ``'-'`` - solid line (painting mode)
%
%   - **resetOffset** *(optional)* - [logical] reset cursor offset when ``true``, needed when magnification changes (default: ``false``)
%
% Output Arguments:
%   (none)
%
% **Example 1** - update cursor at specific position with dashed style:
%
%   .. code-block:: matlab
%
%      obj.updateBrushCursor([100, 150], ':', true);
%
% **Example 2** - use solid line during painting:
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
% Use this document's local id - mibModel.id is stale in split view.
localId = obj.mibModel.Sets.selectedDataset(obj.setOfDatasetsIndex) + ...
    (obj.setOfDatasetsIndex - 1) * obj.mibModel.Sets.datasetsInSet;
% Virtual is browse-only; BigData supports the brush only once a model exists.
dsLocal = obj.mibModel.I{localId};
browseOnly = dsLocal.datasetType(1) == 'V' || (dsLocal.datasetType(1) == 'B' && ~dsLocal.modelExist);
shouldShow = obj.view.brushCursorShow && obj.isInsideImage && ...
    ~browseOnly && ~obj.mibModel.disableSegmentation;

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
    % different zoom level - wasInsideAxes cannot detect this because the
    % callback simply stops firing while the cursor is in another panel).
    currentMagFactor = obj.mibModel.I{localId}.magFactor;
    if isempty(obj.brushCursorOffset) || ...
            isempty(obj.brushCursorMagFactor) || ...
            obj.brushCursorMagFactor ~= currentMagFactor
        obj.updateBrushCursorOffset();
    end

    % Cursor color: the color of the material the brush stroke is added to while
    % Preferences -> Colors -> "cursor matching selected material" is on,
    % otherwise the dark green fallback below.
    % isfield: a preferences file written by this version before the setting
    % existed has no such field - fall back to the default, which is on.
    cursorColor = [0, 0.5, 0];
    colorPrefs = obj.mibModel.preferences.Colors;
    if ~isfield(colorPrefs, 'CursorMaterialColor') || colorPrefs.CursorMaterialColor
        % 'AddTo' is the destination of the stroke; it follows the Material
        % column unless the two are unlinked in the Segmentation panel.
        % double(): Line.Color rejects a single/integer triplet, and the
        % isequal() check below compares against the double it stores
        materialIndex = dsLocal.getSelectedMaterialIndex('AddTo');
        if materialIndex == -1      % Mask row of the materials table
            cursorColor = double(colorPrefs.MaskColor);
        elseif materialIndex > 0    % Exterior (0) keeps the default color
            materialColors = dsLocal.labels.materialColors;
            if dsLocal.labels.maxMaterials > 65535
                % same wrap as MibModel.getRGBimage: the palette repeats every 65535 materials
                materialIndex = mod(materialIndex - 1, 65535) + 1;
            end
            % an index past the end of the palette keeps the default color
            if materialIndex <= size(materialColors, 1)
                cursorColor = double(materialColors(materialIndex, :));
            end
        end
    end

    % Create or update cursor plot
    if isempty(obj.brushCursor) || ~isvalid(obj.brushCursor)
        % Create cursor line once
        obj.brushCursor = plot(obj.handles.imViewAxes, ...
            xy(1) + obj.brushCursorOffset(1,:), ...
            xy(2) + obj.brushCursorOffset(2,:), ...
            'Color', cursorColor, 'LineWidth', 2, ...
            'LineStyle', lineStyle, 'PickableParts', 'none');
    else
        % Fast update: only change position data
        obj.brushCursor.XData = xy(1) + obj.brushCursorOffset(1,:);
        obj.brushCursor.YData = xy(2) + obj.brushCursorOffset(2,:);

        % Update line style if changed
        if ~strcmp(obj.brushCursor.LineStyle, lineStyle)
            obj.brushCursor.LineStyle = lineStyle;
        end

        % Update color if the selected material or the preference changed
        if ~isequal(obj.brushCursor.Color, cursorColor)
            obj.brushCursor.Color = cursorColor;
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
