function renderPairView(obj)
% RENDERPAIRVIEW - Composite the current seam's COMPLETE tile pair at its offset.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.renderPairView()
%
% Renders BOTH FULL TILES placed at the current pair offset (downsampled when
% the union exceeds ~1400 px - the axes stay in full-resolution tile-*i*
% coordinates, so clicks and drags need no unit conversion), according to
% ``overlayModeDropdown``.
%
% 3D pairs are shown as ONE SLICE PAIR (named in the title), selected per
% ``fixMode``:
%
% - **Fix XY** (default) - tile *i* against tile *j*, aligned by the current
%   dz (slice ``a`` vs ``a − dz``); ``Q``/``W`` browse ``a`` through the
%   overlap slab (view-only). A Z misalignment ghosts exactly like an XY one.
% - **Fix Z** - the mosaic Z-BOUNDARY view: ONE tile (the seam's tile with Z
%   slices) at consecutive slices ``z-1`` (cyan) vs ``z`` (magenta), fully
%   overlapping - mostly WHITE when the mosaic is Z-aligned, and the magenta
%   slice is drawn at the boundary's current correction. ``Q``/``W`` move the
%   boundary; drag / Shift+click align slice ``z`` to slice ``z-1`` and hand
%   the offset to :meth:`applyZBoundaryFix`, which shifts EVERY mosaic slice
%   ``>= z``. Browsing alone never changes anything.
%
% Overlay modes:
%
% - **Falsecolor (cyan/magenta)** - the tile on top (the one ``'Overwrite'``
%   keeps, per :meth:`currentTileStack`) magenta, the other cyan: aligned
%   structures add up to WHITE, misaligned ones split into cyan/magenta ghosts
% - **Falsecolor (green/red)** - the same with the tile on top red and the other
%   green; aligned structures come out YELLOW
% - **Preview final** - the pair as Stitch will fuse it, in grey: the Stitching
%   window's blend mode and canvas colour, the drawing order, the corrected
%   pixels (``previewFusedPair`` mirrors ``utils.stitch.fuseSliceComposite`` at
%   display scale). The way to judge which tile should be on top
% - **Flicker** - both tiles stacked; spacebar toggles which is visible
% - **Checkerboard** / **Difference** - ``imfuse`` composites on the union
%   canvas
%
% The colour follows the DRAWING ORDER, not the tile's role in the edge: before
% the order became editable magenta was always tile *j*, the one a drag moves.
% A drag still moves tile *j*, so the title says which tile that is. In the Fix Z
% boundary view slice ``z`` (the one a fix moves) takes the top colour.
%
% The title is a plain colour legend (*Cyan: tile 2; Magenta: tile 4 (on top)*)
% with, on 3D pairs, a second line naming the shown slices; the offset label
% shows the current solved ``[dy dx]`` vs the measured one, the seam score and
% the measurement quality. The drawing order itself is edited from the
% right-click menu (``pairViewButtonDown`` -> :meth:`tileOrder_Callback`).
%

if ~obj.dataValid() || isempty(obj.currentEdgeIdx); return; end
if ~obj.hasWidget('pairAxes'); return; end

pairAxes = obj.view.handles.pairAxes;
edge = obj.stitching.edges(obj.currentEdgeIdx);
layout = obj.stitching.layout;

% Fix Z = the mosaic Z-boundary view: the SAME tile at consecutive slices
% z-1 (cyan) vs z (magenta) - full overlap, mostly white when the mosaic is
% Z-aligned; a fix (applyZBoundaryFix) shifts every mosaic slice >= z. It
% uses the current seam's tile with Z slices (tile i preferred); with 2D
% tiles only the mode never engages (fixModeChanged flips the dropdown back).
boundaryTile = [];
if strcmp(obj.fixMode(), 'z')
    if layout(edge.i).tileSize(3) > 1
        boundaryTile = edge.i;
    elseif layout(edge.j).tileSize(3) > 1
        boundaryTile = edge.j;
    end
end

cla(pairAxes);
obj.pairImageHandles = [];
obj.flickerState = 1;
obj.pairStrip = [];
obj.roiBoxHandle = [];                    % cla deleted the hover ROI box
obj.twoClick = struct('active', false);   % any re-render cancels two-click mode

obj.tileReader();

% The pair view needs WHOLE tiles, and on a large mosaic one decode is several
% seconds - the window would otherwise sit there doing nothing visible while it
% reads. Gated on the cache: navigating back to a pair that is still resident
% must not flash a dialog, and Q/W slice browsing re-renders constantly.
if ~isempty(boundaryTile)
    tilesNeeded = boundaryTile;
else
    tilesNeeded = [edge.i, edge.j];
end
loadDialog = [];
if ~obj.tilesAreResident(tilesNeeded) && ~isempty(obj.progressParent()) && ...
        strcmp(obj.progressParent().Visible, 'on')
    loadDialog = uiprogressdlg(obj.progressParent(), 'Indeterminate', 'on', ...
        'Message', sprintf('Reading tile %s...', strjoin(string(tilesNeeded), ' and ')), ...
        'Title', 'Seam inspector');
end
loadDialogCleanup = onCleanup(@() closeIfValid(loadDialog));

if ~isempty(boundaryTile)
    % ---- boundary view: ONE tile, slices z-1 vs z ----------------------------
    tileFullI = obj.readerFcn(boundaryTile);
    tileFullJ = tileFullI;
    depthI = size(tileFullI, 3);
    depthJ = depthI;
    sizeI = layout(boundaryTile).tileSize;
    sizeJ = sizeI;
    % The browsed boundary is a property of the MOSAIC, not of the seam: it
    % is kept when the user switches tiles, so the same boundary - and the
    % correction stored at it - stays on screen everywhere (that is how the
    % global nature of a fix is visible on the other tiles).
    zBoundary = [];
    if ~isempty(obj.viewSlice) && isfield(obj.viewSlice, 'boundaryTile') && ...
            ~isempty(obj.viewSlice.boundaryTile)
        zBoundary = obj.viewSlice.sliceB;
    end
    if isempty(zBoundary); zBoundary = ceil((depthI + 1) / 2); end
    zBoundary = min(max(round(zBoundary), 2), depthI);
    sliceA = zBoundary - 1;
    sliceB = zBoundary;
    deltaYX = round(obj.boundaryDelta(zBoundary));
else
    % ---- seam view: the pair's full tiles at the current offset --------------
    deltaYX = round(obj.currentOffsetYX(obj.currentEdgeIdx));
    sizeI = layout(edge.i).tileSize;
    sizeJ = layout(edge.j).tileSize;
    tileFullI = obj.readerFcn(edge.i);
    tileFullJ = obj.readerFcn(edge.j);
    depthI = size(tileFullI, 3);
    depthJ = size(tileFullJ, 3);
end
% The pixels are in; what follows is arithmetic on a downsampled copy. The
% onCleanup above is the belt-and-braces path for an error between here and there.
closeIfValid(loadDialog);

% ---- geometry (tile-i coordinate frame) --------------------------------------
rowMin = min(1, 1 + deltaYX(1));
colMin = min(1, 1 + deltaYX(2));
unionH = max(sizeI(1), sizeJ(1) + deltaYX(1)) - rowMin + 1;
unionW = max(sizeI(2), sizeJ(2) + deltaYX(2)) - colMin + 1;

maxDisplayPx = 1400;
scale = max(1, ceil(max(unionH, unionW) / maxDisplayPx));

overlayMode = 'Falsecolor (cyan/magenta)';
if obj.hasWidget('overlayModeDropdown')
    overlayMode = obj.view.handles.overlayModeDropdown.Value;
end
isFalsecolor = startsWith(overlayMode, 'Falsecolor');
if strcmp(overlayMode, 'Falsecolor (green/red)')
    topColour = 'Red';     bottomColour = 'Green';
else
    topColour = 'Magenta'; bottomColour = 'Cyan';
end

% Which image is ON TOP: in a seam view, the tile Overwrite keeps (the same
% utils.stitch.tileDrawOrder the fusers use); in the boundary view, slice z -
% the one a fix moves. The top one always takes the magenta / red colour.
if isempty(boundaryTile)
    stack = obj.currentTileStack();
    jOnTop = find(stack == edge.j, 1) > find(stack == edge.i, 1);
else
    jOnTop = true;
end
if jOnTop
    colourI = bottomColour; colourJ = topColour;
else
    colourI = topColour;    colourJ = bottomColour;
end

% Names the title uses for the two overlaid images: the colours in falsecolor
% mode (where they ARE the legend), plain identities in the other modes. The
% tile Overwrite keeps is marked in every mode.
if ~isempty(boundaryTile)
    if isFalsecolor
        nameI = sprintf('%s: slice %d', colourI, sliceA);
        nameJ = sprintf('%s: slice %d', colourJ, sliceB);
    else
        nameI = sprintf('slice %d', sliceA);
        nameJ = sprintf('slice %d', sliceB);
    end
else
    topMark = {'', ' (on top)'};
    if isFalsecolor
        nameI = sprintf('%s: tile %d%s', colourI, edge.i, topMark{1 + ~jOnTop});
        nameJ = sprintf('%s: tile %d%s', colourJ, edge.j, topMark{1 + jOnTop});
        sliceNameI = colourI; sliceNameJ = colourJ;
    else
        nameI = sprintf('tile %d%s', edge.i, topMark{1 + ~jOnTop});
        nameJ = sprintf('tile %d%s', edge.j, topMark{1 + jOnTop});
        sliceNameI = sprintf('Tile %d', edge.i);
        sliceNameJ = sprintf('Tile %d', edge.j);
    end
end

sliceNote = '';
if ~isempty(boundaryTile)
    shiftText = '';
    if any(deltaYX ~= 0)
        shiftText = sprintf(' - current shift [%d %d]', deltaYX(1), deltaYX(2));
    end
    sliceNote = sprintf('Tile %d, Z boundary %d/%d - a fix shifts mosaic slices %d..%d%s', ...
        boundaryTile, sliceB, depthI, sliceB, depthI, shiftText);
    obj.viewSlice = struct('edgeIdx', obj.currentEdgeIdx, 'sliceA', sliceA, ...
        'sliceB', sliceB, 'depthA', depthI, 'depthB', depthJ, 'boundaryTile', boundaryTile);
elseif depthI == 1 && depthJ == 1
    obj.viewSlice = [];
    sliceA = 1; sliceB = 1;
else
    currentDz = 0;
    if obj.pairHasDepth(obj.currentEdgeIdx)
        currentDz = round(obj.currentDz(obj.currentEdgeIdx));
    end
    requestA = [];
    if ~isempty(obj.viewSlice) && isequal(obj.viewSlice.edgeIdx, obj.currentEdgeIdx)
        requestA = obj.viewSlice.sliceA;
    end
    slabA = max(1, 1 + currentDz):min(depthI, depthJ + currentDz);
    if isempty(requestA)
        if isempty(slabA)
            requestA = ceil(depthI / 2);
        else
            requestA = slabA(ceil(numel(slabA) / 2));
        end
    end
    if isempty(slabA)
        sliceA = ceil(depthI / 2);
        sliceB = ceil(depthJ / 2);
        sliceNote = 'No overlapping Z slices at the current alignment - showing the middle slices';
    else
        % The pair aligned by the current dz, browsed within the slab.
        sliceA = min(max(round(requestA), slabA(1)), slabA(end));
        sliceB = sliceA - currentDz;
        if sliceB == sliceA
            sliceNote = sprintf('Slice %d/%d - Q/W browses', sliceA, depthI);
        else
            sliceNote = sprintf('%s: slice %d/%d; %s: slice %d/%d - Q/W browses', ...
                sliceNameI, sliceA, depthI, sliceNameJ, sliceB, depthJ);
        end
    end
    obj.viewSlice = struct('edgeIdx', obj.currentEdgeIdx, 'sliceA', sliceA, ...
        'sliceB', sliceB, 'depthA', depthI, 'depthB', depthJ, 'boundaryTile', []);
end
imageI = takeSlice(tileFullI, sliceA);
imageJ = takeSlice(tileFullJ, sliceB);
if scale > 1
    imageI = imresize(imageI, 1 / scale);
    imageJ = imresize(imageJ, 1 / scale);
end

% Joint normalisation so both tiles render at comparable brightness.
low = min(min(imageI(:)), min(imageJ(:)));
high = max(max(imageI(:)), max(imageJ(:)));
if high <= low; high = low + 1; end
imageI = (imageI - low) / (high - low);
imageJ = (imageJ - low) / (high - low);

% Click/drag geometry: axes data coords ARE tile-i full-res pixels.
obj.pairStrip = struct('bboxA', [1, sizeI(1); 1, sizeI(2)], ...
    'deltaYX', deltaYX, 'scale', scale);

% Full-res extents of the (possibly downsampled) tile images, pixel-centre
% convention: N downsampled pixels span (N-1)*scale full-res units.
extentI = {[1, 1 + (size(imageI, 2) - 1) * scale], [1, 1 + (size(imageI, 1) - 1) * scale]};
extentJ = {[1 + deltaYX(2), 1 + deltaYX(2) + (size(imageJ, 2) - 1) * scale], ...
           [1 + deltaYX(1), 1 + deltaYX(1) + (size(imageJ, 1) - 1) * scale]};

% ---- render per overlay mode -------------------------------------------------
% Two-line title: line 1 = a plain legend naming the tiles, line 2 = the
% slice pair (3D only) - a single line does not fit the axes width.
switch overlayMode
    case 'Flicker'
        imageA = image(pairAxes, 'XData', extentI{1}, 'YData', extentI{2}, ...
            'CData', repmat(imageI, 1, 1, 3));
        imageB = image(pairAxes, 'XData', extentJ{1}, 'YData', extentJ{2}, ...
            'CData', repmat(imageJ, 1, 1, 3));
        imageB.Visible = 'off';
        obj.pairImageHandles = [imageA, imageB];
        if ~isempty(boundaryTile)
            titleLine = sprintf('Flicker - showing slice %d (Space toggles)', sliceA);
        else
            titleLine = sprintf('Flicker - showing tile %d (Space toggles)', edge.i);
        end
    case {'Checkerboard', 'Difference'}
        [canvasI, canvasJ, canvasExtent] = unionCanvases(imageI, imageJ, ...
            deltaYX, rowMin, colMin, scale);
        if strcmp(overlayMode, 'Checkerboard')
            composite = repmat(mat2gray( ...
                imfuse(canvasI, canvasJ, 'checkerboard', 'Scaling', 'joint')), 1, 1, 3);
            titleLine = sprintf('Checkerboard - %s vs %s', nameI, nameJ);
        else
            composite = repmat(mat2gray(imfuse(canvasI, canvasJ, 'diff')), 1, 1, 3);
            titleLine = sprintf('Difference - %s vs %s (dark = match)', nameI, nameJ);
        end
        image(pairAxes, 'XData', canvasExtent{1}, 'YData', canvasExtent{2}, ...
            'CData', composite);
    case 'Preview final'
        % The pair as Stitch will fuse it: the Stitching window's blend mode,
        % the drawing order (Overwrite keeps the tile on top), the tiles as the
        % intensity correction reads them, uncovered pixels in the canvas colour.
        [canvasI, canvasJ, canvasExtent] = unionCanvases(imageI, imageJ, ...
            deltaYX, rowMin, colMin, scale);
        [coverI, coverJ] = unionCanvases(ones(size(imageI), 'single'), ...
            ones(size(imageJ), 'single'), deltaYX, rowMin, colMin, scale);
        blendMode = obj.stitching.BatchOpt.BlendMode{1};
        if strcmp(blendMode, 'Feather')
            [weightI, weightJ] = unionCanvases(utils.stitch.blendWeights(size(imageI)), ...
                utils.stitch.blendWeights(size(imageJ)), deltaYX, rowMin, colMin, scale);
        else
            weightI = coverI; weightJ = coverJ;
        end
        background = single(strcmp(obj.stitching.BatchOpt.CanvasColor{1}, 'white'));
        if jOnTop
            fused = previewFusedPair(canvasJ, canvasI, coverJ > 0, coverI > 0, ...
                weightJ, weightI, blendMode, background);
        else
            fused = previewFusedPair(canvasI, canvasJ, coverI > 0, coverJ > 0, ...
                weightI, weightJ, blendMode, background);
        end
        image(pairAxes, 'XData', canvasExtent{1}, 'YData', canvasExtent{2}, ...
            'CData', repmat(fused, 1, 1, 3));
        titleLine = sprintf('Preview final (%s) - %s; %s', blendMode, nameI, nameJ);
    otherwise   % Falsecolor: the image on top red (+blue = magenta), the other green (+blue = cyan)
        [canvasI, canvasJ, canvasExtent] = unionCanvases(imageI, imageJ, ...
            deltaYX, rowMin, colMin, scale);
        if jOnTop
            canvasTop = canvasJ; canvasBottom = canvasI;
        else
            canvasTop = canvasI; canvasBottom = canvasJ;
        end
        if strcmp(topColour, 'Red')
            % Aligned structures come out yellow.
            composite = cat(3, canvasTop, canvasBottom, zeros(size(canvasTop), 'like', canvasTop));
        else
            % Aligned structures come out white.
            composite = cat(3, canvasTop, canvasBottom, max(canvasTop, canvasBottom));
        end
        image(pairAxes, 'XData', canvasExtent{1}, 'YData', canvasExtent{2}, ...
            'CData', composite);
        titleLine = sprintf('%s; %s', nameI, nameJ);
end
% A drag always moves tile j; once the colours follow the drawing order that
% is no longer "the magenta one", so say so.
if isempty(boundaryTile)
    titleLine = sprintf('%s | drag moves tile %d', titleLine, edge.j);
end
if isempty(sliceNote)
    title(pairAxes, titleLine);
else
    title(pairAxes, {titleLine, sliceNote});
end
set(pairAxes, 'YDir', 'reverse', 'XTick', [], 'YTick', []);
axis(pairAxes, 'image');

% Re-apply the wheel zoom across re-renders of the SAME seam - nudges, drags
% and fixes all re-render, and losing the zoom on every arrow key would make
% fine alignment unusable.
%
% The zoom LEVEL also follows the user ACROSS seams: a QC pass means judging
% every seam at the same magnification, and re-zooming after each Enter was
% the most repetitive thing in it. Only the CENTRE is re-anchored, onto the
% new pair's overlap - the part actually being judged - because the axes are
% in tile-*i* pixels and the same coordinates mean something different for
% every pair. A carried zoom wider than the new pair just fits instead.
if ~isempty(obj.pairZoom) && isequal(obj.pairZoom.edgeIdx, obj.currentEdgeIdx)
    [xLim, yLim] = obj.pairAxesFillLimits(obj.pairZoom.xLim, obj.pairZoom.yLim);
else
    [xLim, yLim] = carriedZoomOnNewSeam(obj, deltaYX, sizeI, sizeJ, ...
        [colMin, colMin + unionW - 1], [rowMin, rowMin + unionH - 1]);
    if isempty(xLim)
        obj.pairZoom = [];
        [xLim, yLim] = obj.pairAxesFillLimits();   % 'axis image' left it letterboxed
    else
        obj.pairZoom = struct('edgeIdx', obj.currentEdgeIdx, 'xLim', xLim, 'yLim', yLim);
    end
end
% Fill the whole reserved cell instead of a letterboxed column (see
% pairAxesFillLimits); the pixels stay 1:1, only the shown context grows.
if ~isempty(xLim)
    pairAxes.XLim = xLim;
    pairAxes.YLim = yLim;
end

% Phase C interactions: click = correlate at that spot, drag = move tile j.
set(findobj(pairAxes, 'Type', 'image'), ...
    'ButtonDownFcn', @(~, evnt) obj.pairViewButtonDown(evnt));
% Right-click (without dragging) = tile-order menu; images do not inherit the
% axes' ContextMenu, and they cover most of the axes.
if ~isempty(obj.tileOrderMenu) && isvalid(obj.tileOrderMenu)
    set(findobj(pairAxes, 'Type', 'image'), 'ContextMenu', obj.tileOrderMenu);
end

updateOffsetLabel(obj, edge, deltaYX);
end

% =====================================================================
function fused = previewFusedPair(canvasTop, canvasBottom, coverTop, coverBottom, ...
    weightTop, weightBottom, blendMode, background)
% PREVIEWFUSEDPAIR - Blend the two union canvases the way the fusers do.
%
% A display-scale mirror of utils.stitch.fuseSliceComposite for exactly two
% tiles: Overwrite keeps the tile on top, Max/Min only compare pixels a tile
% actually covers (an empty canvas never wins), Average/Feather divide the
% weighted sum by the summed weights. Pixels neither tile covers take the
% background (canvas colour, on the 0..1 display scale).
switch blendMode
    case 'Overwrite'
        fused = canvasBottom;
        fused(coverTop) = canvasTop(coverTop);
    case {'Max', 'Min'}
        if strcmp(blendMode, 'Max'); emptyValue = -Inf; else; emptyValue = Inf; end
        top = canvasTop;       top(~coverTop) = emptyValue;
        bottom = canvasBottom; bottom(~coverBottom) = emptyValue;
        if strcmp(blendMode, 'Max'); fused = max(top, bottom); else; fused = min(top, bottom); end
    otherwise   % Average / Feather: weights are the coverage or the feather ramps
        weightSum = weightTop + weightBottom;
        fused = (canvasTop .* weightTop + canvasBottom .* weightBottom) ./ max(weightSum, eps('single'));
end
fused(~(coverTop | coverBottom)) = background;
end

% =====================================================================
function closeIfValid(progressDialog)
% CLOSEIFVALID - Close a progress dialog once; safe to call again afterwards
% (renderPairView closes it explicitly, and its onCleanup then repeats the call
% on the way out).
if ~isempty(progressDialog) && isvalid(progressDialog)
    close(progressDialog);
end
end

% =========================================================================
function [canvasI, canvasJ, canvasExtent] = unionCanvases(imageI, imageJ, ...
    deltaYX, rowMin, colMin, scale)
% UNIONCANVASES - Place both (downsampled) tiles into same-size union buffers
% so pixel-aligned composites (falsecolor / imfuse) can be built; black
% outside each tile. Returns the buffers' full-res extent for XData/YData.
positionI = max(1, round(([1, 1] - [rowMin, colMin]) / scale) + 1);
positionJ = max(1, round(([1 + deltaYX(1), 1 + deltaYX(2)] - [rowMin, colMin]) / scale) + 1);
bufferH = max(positionI(1) + size(imageI, 1), positionJ(1) + size(imageJ, 1)) - 1;
bufferW = max(positionI(2) + size(imageI, 2), positionJ(2) + size(imageJ, 2)) - 1;
canvasI = zeros(bufferH, bufferW, 'single');
canvasJ = zeros(bufferH, bufferW, 'single');
canvasI(positionI(1):positionI(1) + size(imageI, 1) - 1, ...
        positionI(2):positionI(2) + size(imageI, 2) - 1) = imageI;
canvasJ(positionJ(1):positionJ(1) + size(imageJ, 1) - 1, ...
        positionJ(2):positionJ(2) + size(imageJ, 2) - 1) = imageJ;
canvasExtent = {[colMin, colMin + (bufferW - 1) * scale], ...
                [rowMin, rowMin + (bufferH - 1) * scale]};
end

% =====================================================================
function [xLim, yLim] = carriedZoomOnNewSeam(obj, deltaYX, sizeI, sizeJ, xFull, yFull)
% CARRIEDZOOMONNEWSEAM - Same magnification, re-centred on the new seam.
%
% Returns the stored zoom's SPAN placed over the overlap between the two
% tiles - where the seam is, and the only part of the pair worth being zoomed
% into - clamped to stay inside the rendered union. ``[]`` when there is no
% zoom to carry or it is no longer a zoom on this pair (span at least as big
% as the union in both directions), which tells the caller to fit instead.
xLim = []; yLim = [];
if isempty(obj.pairZoom); return; end

spanX = diff(obj.pairZoom.xLim);
spanY = diff(obj.pairZoom.yLim);
if spanX >= diff(xFull) && spanY >= diff(yFull); return; end

% Overlap in the tile-i frame; the union centre when the tiles do not overlap
% at all (a badly placed pair - then the whole pair is the subject).
overlapY = [max(1, 1 + deltaYX(1)), min(sizeI(1), sizeJ(1) + deltaYX(1))];
overlapX = [max(1, 1 + deltaYX(2)), min(sizeI(2), sizeJ(2) + deltaYX(2))];
if diff(overlapY) <= 0 || diff(overlapX) <= 0
    centre = [mean(xFull), mean(yFull)];
else
    centre = [mean(overlapX), mean(overlapY)];
end

xLim = centre(1) + [-0.5, 0.5] * spanX;
yLim = centre(2) + [-0.5, 0.5] * spanY;
% Same border clamp as the wheel zoom: a span wider than the union collapses
% to "centred on the union", which is what that direction wants.
xLim = xLim - max(0, xLim(2) - xFull(2)) + max(0, xFull(1) - xLim(1));
yLim = yLim - max(0, yLim(2) - yFull(2)) + max(0, yFull(1) - yLim(1));

[xLim, yLim] = obj.pairAxesFillLimits(xLim, yLim);
end

% =====================================================================
function updateOffsetLabel(obj, edge, deltaYX)
% UPDATEOFFSETLABEL - Current vs measured offset + scores readout; in the
% Fix-Z boundary view, the boundary position and the mosaic shift above it.
if ~obj.hasWidget('offsetLabel'); return; end
if obj.boundaryModeActive()
    storedText = 'none stored';
    fixes = obj.stitching.zSliceFixes;
    if ~isempty(fixes)
        storedText = sprintf('stored at z: %s', strjoin( ...
            arrayfun(@(z) sprintf('%d', z), sort(round(fixes(:, 1)))', ...
            'UniformOutput', false), ', '));
    end
    obj.view.handles.offsetLabel.Text = sprintf( ...
        'Z boundary %d/%d (tile %d)  |  shift of slices above [dy dx] = [%d %d]  |  corrections: %s  |  Q/W moves the boundary', ...
        obj.viewSlice.sliceB, obj.viewSlice.depthB, obj.viewSlice.boundaryTile, ...
        deltaYX(1), deltaYX(2), storedText);
    return;
end
if isempty(edge.seamScore) || isnan(edge.seamScore)
    scoreText = 'n/a';
else
    scoreText = sprintf('%.2f', edge.seamScore);
end
dzText = '';
if obj.pairHasDepth(obj.currentEdgeIdx)
    dzText = sprintf('  |  dz %g', obj.currentDz(obj.currentEdgeIdx));
end
if isfield(edge, 'dzHint') && ~isempty(edge.dzHint) && edge.dzHint ~= 0
    dzText = sprintf('%s  |  pixels prefer dz%+d', dzText, edge.dzHint);
end
obj.view.handles.offsetLabel.Text = sprintf( ...
    'Solved offset [dy dx] = [%d %d]  |  measured [%.1f %.1f]  |  seam score %s  |  quality %.2f  |  %s%s', ...
    deltaYX(1), deltaYX(2), edge.measured(1), edge.measured(2), scoreText, ...
    edge.quality, char(edge.source), dzText);
end

% =====================================================================
function slice = takeSlice(tile, sliceIdx)
% TAKESLICE - [H W D C] -> single 2D slice (first channel), index clamped.
tile = single(tile(:, :, :, 1));
slice = tile(:, :, min(max(sliceIdx, 1), size(tile, 3)));
end
