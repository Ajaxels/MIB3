function previewLayoutBtn_Callback(obj)
% PREVIEWLAYOUTBTN_CALLBACK - Draw nominal tile positions on the preview axes.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.previewLayoutBtn_Callback()
%
% Renders a top-down view of tile nominal positions on the ``previewAxes``
% widget, colour-coded and labelled with the tile index. The axes are scaled to
% the full canvas extent.
%
% Two modes, selected by the ``editLayoutCheckbox`` state:
%   - **display** (default) — static ``patch`` rectangles (fast, read-only).
%   - **edit** — one draggable :class:`images.roi.Rectangle` per tile
%     (translate-only, fixed size); dragging a tile writes its new position into
%     ``layout(i).nomOrigin`` and invalidates the measured edges / solved
%     positions so the next Measure/Optimize run uses the corrected layout. This
%     is the interactive rough-placement workflow (Phase 3).
%
% For multi-layer (3D) layouts only the FIRST Z-layer is drawn/edited: every
% layer shares the same XY grid, so drawing them all would stack rectangles.
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Stitching.previewLayoutBtn_Callback: triggered\n');
end
if isempty(obj.layout)
    warnOptions.MsgBoxOnly  = true;
    warnOptions.Icon        = 'puffin_warning';
    warnOptions.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.view.gui, ...
        'No layout loaded. Please select input tiles first.', {}, {}, ...
        'No layout', warnOptions);
    return;
end

previewAxes = obj.view.handles.previewAxes;

% Tear down any interactive ROIs from a previous edit-mode draw before clearing.
deleteTileROIs(obj);
cla(previewAxes);
hold(previewAxes, 'on');

% Show only the first Z-layer (tiles from other layers overlap it in XY).
zLayers = arrayfun(@(t) t.zLayer, obj.layout);
distinctLayers = unique(zLayers);
firstLayerTiles = find(zLayers == distinctLayers(1));

colorMap = lines(numel(obj.layout));

editMode = isfield(obj.view.handles, 'editLayoutCheckbox') && ...
    obj.view.handles.editLayoutCheckbox.Value;

if editMode
    drawInteractiveTiles(obj, previewAxes, firstLayerTiles, colorMap);
else
    drawStaticTiles(previewAxes, obj.layout, firstLayerTiles, colorMap);
end

hold(previewAxes, 'off');
set(previewAxes, 'YDir', 'reverse');   % image convention: y increases downward
xlabel(previewAxes, 'X (pixels)');
ylabel(previewAxes, 'Y (pixels)');

if editMode
    titleText = sprintf('Drag tiles to reposition — %d tiles', numel(firstLayerTiles));
elseif numel(distinctLayers) > 1
    titleText = sprintf('Layout preview — %d tiles in layer 1 of %d', ...
        numel(firstLayerTiles), numel(distinctLayers));
else
    titleText = sprintf('Layout preview — %d tiles', numel(firstLayerTiles));
end
title(previewAxes, titleText);

end

% =========================================================================
function drawStaticTiles(previewAxes, layout, firstLayerTiles, colorMap)
% DRAWSTATICTILES - Read-only patch rectangles + index labels (two passes so the
% numbers stay on top of overlapping tiles).
for tileIdx = firstLayerTiles
    originX = layout(tileIdx).nomOrigin(2);
    originY = layout(tileIdx).nomOrigin(1);
    tileW   = layout(tileIdx).tileSize(2);
    tileH   = layout(tileIdx).tileSize(1);
    rectangleColor = colorMap(tileIdx, :);
    patch(previewAxes, ...
        'XData',     [originX, originX + tileW, originX + tileW, originX], ...
        'YData',     [originY, originY, originY + tileH, originY + tileH], ...
        'EdgeColor', rectangleColor, ...
        'FaceColor', rectangleColor, ...
        'FaceAlpha', 0.15, ...
        'LineWidth', 1.5);
end
for tileIdx = firstLayerTiles
    centerX = layout(tileIdx).nomOrigin(2) + layout(tileIdx).tileSize(2) / 2;
    centerY = layout(tileIdx).nomOrigin(1) + layout(tileIdx).tileSize(1) / 2;
    text(previewAxes, centerX, centerY, num2str(tileIdx), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
        'FontSize', 9, 'FontWeight', 'bold', 'Color', colorMap(tileIdx, :));
end
axis(previewAxes, 'equal');
axis(previewAxes, 'tight');
end

% =========================================================================
function drawInteractiveTiles(obj, previewAxes, firstLayerTiles, colorMap)
% DRAWINTERACTIVETILES - One draggable Rectangle ROI per tile (translate-only,
% fixed size). ROIMoved writes the new origin back into obj.layout.
obj.tileROIs     = images.roi.Rectangle.empty;
obj.roiListeners = {};

% Fix the axes limits with a margin so a dragged tile stays visible (auto-limits
% would jump around as ROIs move).
[xLimits, yLimits] = layerBounds(obj.layout, firstLayerTiles, 0.25);
daspect(previewAxes, [1 1 1]);
xlim(previewAxes, xLimits);
ylim(previewAxes, yLimits);

for tileIdx = firstLayerTiles
    originX = obj.layout(tileIdx).nomOrigin(2);
    originY = obj.layout(tileIdx).nomOrigin(1);
    tileW   = obj.layout(tileIdx).tileSize(2);
    tileH   = obj.layout(tileIdx).tileSize(1);

    roi = images.roi.Rectangle(previewAxes, ...
        'Position', [originX, originY, tileW, tileH], ...
        'Color', colorMap(tileIdx, :), ...
        'FaceAlpha', 0.15, ...
        'LineWidth', 1.5, ...
        'InteractionsAllowed', 'translate', ...   % move only — tile size is fixed
        'Deletable', false, ...
        'Label', num2str(tileIdx), ...
        'LabelVisible', 'hover');

    obj.tileROIs(end + 1)     = roi;
    obj.roiListeners{end + 1} = addlistener(roi, 'ROIMoved', ...
        @(src, ~) tileMoved(obj, tileIdx, src));
end
end

% =========================================================================
function tileMoved(obj, tileIdx, roi)
% TILEMOVED - ROIMoved handler: write the dragged position into the layout and
% invalidate the downstream pipeline (edges / positions / canvas).
if ~isvalid(roi); return; end
position = roi.Position;             % [xMin yMin width height]
obj.layout(tileIdx).nomOrigin(1) = position(2);   % y
obj.layout(tileIdx).nomOrigin(2) = position(1);   % x

% Manual placement supersedes any prior measurement/solve.
obj.edges     = [];
obj.positions = [];
obj.canvas    = [];
obj.updateWidgets();   % refreshes the status + resets the alignment chip
end

% =========================================================================
function deleteTileROIs(obj)
% DELETETILEROIS - Remove any live tile ROIs + their listeners.
if ~isempty(obj.roiListeners)
    for listenerIdx = 1:numel(obj.roiListeners)
        if isvalid(obj.roiListeners{listenerIdx})
            delete(obj.roiListeners{listenerIdx});
        end
    end
    obj.roiListeners = {};
end
if ~isempty(obj.tileROIs)
    validROIs = obj.tileROIs(isvalid(obj.tileROIs));
    delete(validROIs);
    obj.tileROIs = images.roi.Rectangle.empty;
end
end

% =========================================================================
function [xLimits, yLimits] = layerBounds(layout, tileIndices, marginFraction)
% LAYERBOUNDS - Axis limits covering the given tiles, padded by marginFraction of
% the larger extent so dragged tiles stay in view.
originX = arrayfun(@(idx) layout(idx).nomOrigin(2), tileIndices);
originY = arrayfun(@(idx) layout(idx).nomOrigin(1), tileIndices);
tileW   = arrayfun(@(idx) layout(idx).tileSize(2), tileIndices);
tileH   = arrayfun(@(idx) layout(idx).tileSize(1), tileIndices);
xMin = min(originX);            yMin = min(originY);
xMax = max(originX + tileW);    yMax = max(originY + tileH);
margin = marginFraction * max(xMax - xMin, yMax - yMin);
xLimits = [xMin - margin, xMax + margin];
yLimits = [yMin - margin, yMax + margin];
end
