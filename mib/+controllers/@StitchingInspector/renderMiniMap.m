function renderMiniMap(obj)
% RENDERMINIMAP - Layout overview: tiles coloured by their worst seam score.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.renderMiniMap()
%
% Each tile is a patch at its SOLVED position, coloured by the worst score of
% its incident edges (green → red; grey when all incident edges are excluded).
% The current pair's tiles get a bold blue outline. Clicking jumps the review
% to whichever SEAM of the current layer is nearest the click point — not
% just the clicked tile's single worst seam, and not just whichever patch
% happens to be drawn on top of an overlap — see
% :meth:`controllers.StitchingInspector.edgeAtMiniMapPoint`.
%
% Only the tiles of ONE Z-layer are drawn — the layer of the current seam (the
% lower tile of a cross-layer pair). A multi-layer mosaic stacks every layer at
% the same XY, so drawing them all overlaps the boxes and merges the labels;
% restricting to the current layer keeps the overview readable and it follows
% the selected seam. The layer is named in the axes title when there is more
% than one.
%
% When the per-tile thumbnails are available (:func:`ensureTileThumbs`), a
% low-res FUSED preview is composited at the solved positions behind the
% patches (which then drop to a light tint), so a gross misplacement shows in
% the actual image content — re-composited on every redraw, so it tracks each
% re-solve.
%

if ~obj.hasWidget('miniMapAxes'); return; end
mapAxes = obj.view.handles.miniMapAxes;
cla(mapAxes);
% Harmless fallback only — see the real (always-present, always-pickable)
% hit target laid down below, which is what actually receives every click.
mapAxes.ButtonDownFcn = @(~, ~) obj.miniMapButtonDown();

layout = obj.stitching.layout;
edges = obj.stitching.edges;
positions = obj.stitching.positions;
numTiles = numel(layout);

% Worst incident VALID seam score per tile.
worstScore = nan(numTiles, 1);
for k = 1:numel(edges)
    if ~edges(k).valid; continue; end
    s = edges(k).seamScore;
    if isempty(s); s = NaN; end
    for tileIdx = [edges(k).i, edges(k).j]
        if isnan(worstScore(tileIdx)) || (~isnan(s) && s < worstScore(tileIdx))
            worstScore(tileIdx) = s;
        end
        if isnan(s); worstScore(tileIdx) = -Inf; end   % NaN-scored edge: worst
    end
end

currentTiles = [];
if ~isempty(obj.currentEdgeIdx)
    currentTiles = [edges(obj.currentEdgeIdx).i, edges(obj.currentEdgeIdx).j];
end

% Draw a single Z-layer: the current seam's layer (its lower tile for a
% cross-layer pair), else the first layer. Layers stack at the same XY, so
% this is what stops the boxes/labels from overlapping.
zLayers = arrayfun(@(t) t.zLayer, layout);
drawTiles = obj.currentLayerTiles();
currentLayer = layout(drawTiles(1)).zLayer;

hold(mapAxes, 'on');

% One CLICKABLE object spanning every drawn tile's bounding box, laid down
% FIRST (bottom of the stack). The tile patches above it are
% PickableParts='none', so a click anywhere in the layout passes straight
% through them to whichever pixel of THIS object is underneath — giving an
% exact CurrentPoint with no z-order ambiguity. (A UIAxes' own ButtonDownFcn
% is not a reliable fallback once every child is non-pickable, so the mini-map
% needs one real, always-present hit target rather than relying on that.)
extentX0 = min(positions(drawTiles, 2)); extentY0 = min(positions(drawTiles, 1));
extentX1 = max(positions(drawTiles, 2) + arrayfun(@(t) layout(t).tileSize(2), drawTiles));
extentY1 = max(positions(drawTiles, 1) + arrayfun(@(t) layout(t).tileSize(1), drawTiles));

% Low-res fused preview behind the patches (skipped when thumbs declined).
obj.ensureTileThumbs();
patchAlpha = 0.85;   % opaque score fill when there is no image behind
if ~isempty(obj.tileThumbs)
    scale = obj.thumbScale;
    minY = min(positions(drawTiles, 1)); minX = min(positions(drawTiles, 2));
    canvasH = 1; canvasW = 1;
    placeRC = zeros(numTiles, 2);
    for tileIdx = drawTiles(:)'
        placeRC(tileIdx, :) = round((positions(tileIdx, 1:2) - [minY, minX]) / scale) + 1;
        canvasH = max(canvasH, placeRC(tileIdx, 1) + size(obj.tileThumbs{tileIdx}, 1) - 1);
        canvasW = max(canvasW, placeRC(tileIdx, 2) + size(obj.tileThumbs{tileIdx}, 2) - 1);
    end
    fusedCanvas = zeros(canvasH, canvasW, 'single');
    for tileIdx = drawTiles(:)'
        thumb = obj.tileThumbs{tileIdx};
        rows = placeRC(tileIdx, 1):placeRC(tileIdx, 1) + size(thumb, 1) - 1;
        cols = placeRC(tileIdx, 2):placeRC(tileIdx, 2) + size(thumb, 2) - 1;
        fusedCanvas(rows, cols) = thumb;   % overwrite blend — preview only
    end
    % Pixel-centre extents in full-res units, same convention as the pair view.
    hitTarget = image(mapAxes, 'XData', [minX, minX + (canvasW - 1) * scale], ...
        'YData', [minY, minY + (canvasH - 1) * scale], ...
        'CData', repmat(fusedCanvas, 1, 1, 3));
    patchAlpha = 0.25;   % light score tint so the image stays readable
else
    % No thumbnail to double as the hit target: an invisible patch instead.
    % FaceAlpha=0 makes it fully transparent WITHOUT disabling hit-testing on
    % its face (only HitTest/PickableParts do that).
    hitTarget = patch(mapAxes, 'XData', [extentX0, extentX1, extentX1, extentX0], ...
        'YData', [extentY0, extentY0, extentY1, extentY1], ...
        'FaceColor', [1 1 1], 'FaceAlpha', 0, 'EdgeColor', 'none');
end
hitTarget.ButtonDownFcn = @(~, ~) obj.miniMapButtonDown();
for tileIdx = drawTiles(:)'
    x0 = positions(tileIdx, 2);
    y0 = positions(tileIdx, 1);
    w = layout(tileIdx).tileSize(2);
    h = layout(tileIdx).tileSize(1);
    if ismember(tileIdx, currentTiles)
        edgeColor = [0.10 0.35 0.95]; lineWidth = 2.5;
    else
        edgeColor = [0.25 0.25 0.25]; lineWidth = 0.5;
    end
    patch(mapAxes, 'XData', [x0, x0 + w, x0 + w, x0], ...
        'YData', [y0, y0, y0 + h, y0 + h], ...
        'FaceColor', tileColor(worstScore(tileIdx)), 'FaceAlpha', patchAlpha, ...
        'EdgeColor', edgeColor, 'LineWidth', lineWidth, ...
        'HitTest', 'off', 'PickableParts', 'none');
    text(mapAxes, x0 + w/2, y0 + h/2, sprintf('%d', tileIdx), ...
        'HorizontalAlignment', 'center', 'FontSize', 9, 'HitTest', 'off', ...
        'PickableParts', 'none');
end
hold(mapAxes, 'off');
set(mapAxes, 'YDir', 'reverse', 'XTick', [], 'YTick', []);
axis(mapAxes, 'equal');
axis(mapAxes, 'tight');

% Name the shown layer only when the mosaic actually has more than one.
if numel(unique(zLayers)) > 1
    title(mapAxes, sprintf('Z-layer %d', currentLayer), 'FontSize', 9);
else
    title(mapAxes, '');
end

end

% =====================================================================
function color = tileColor(worstScore)
% TILECOLOR - Worst incident score to a face colour (grey = no scored edges).
if isnan(worstScore)
    color = [0.8 0.8 0.8];
elseif worstScore >= 0.7
    color = [0.55 0.85 0.55];
elseif worstScore >= 0.4
    color = [0.98 0.85 0.45];
else
    color = [0.95 0.45 0.45];
end
end
