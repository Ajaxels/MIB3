function renderPairView(obj)
% RENDERPAIRVIEW - Composite the current seam's COMPLETE tile pair at its offset.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.renderPairView()
%
% Renders BOTH FULL TILES placed at the current pair offset (downsampled when
% the union exceeds ~1400 px — the axes stay in full-resolution tile-*i*
% coordinates, so clicks and drags need no unit conversion), according to
% ``overlayModeDropdown``.
%
% 3D pairs are shown as ONE SLICE PAIR (named in the title), selected per
% ``fixMode``:
%
% - **Fix XY** (default) — tile *i* against tile *j*, aligned by the current
%   dz (slice ``a`` vs ``a − dz``); ``Q``/``W`` browse ``a`` through the
%   overlap slab (view-only). A Z misalignment ghosts exactly like an XY one.
% - **Fix Z** — the mosaic Z-BOUNDARY view: ONE tile (the seam's tile with Z
%   slices) at consecutive slices ``z-1`` (cyan) vs ``z`` (magenta), fully
%   overlapping — mostly WHITE when the mosaic is Z-aligned, and the magenta
%   slice is drawn at the boundary's current correction. ``Q``/``W`` move the
%   boundary; drag / Shift+click align slice ``z`` to slice ``z-1`` and hand
%   the offset to :meth:`applyZBoundaryFix`, which shifts EVERY mosaic slice
%   ``>= z``. Browsing alone never changes anything.
%
% Overlay modes:
%
% - **Falsecolor** — tile *i* cyan, tile *j* magenta: aligned structures add
%   up to WHITE, misaligned ones split into cyan/magenta ghosts
% - **Flicker** — both tiles stacked; spacebar toggles which is visible
% - **Checkerboard** / **Difference** — ``imfuse`` composites on the union
%   canvas
%
% The title is a plain colour legend (*Cyan: tile 2; Magenta: tile 4*) with,
% on 3D pairs, a second line naming the shown slices; the offset label shows
% the current solved ``[dy dx]`` vs the measured one, the seam score and the
% measurement quality.
%

if ~obj.dataValid() || isempty(obj.currentEdgeIdx); return; end
if ~obj.hasWidget('pairAxes'); return; end

pairAxes = obj.view.handles.pairAxes;
edge = obj.stitching.edges(obj.currentEdgeIdx);
layout = obj.stitching.layout;

% Fix Z = the mosaic Z-boundary view: the SAME tile at consecutive slices
% z-1 (cyan) vs z (magenta) — full overlap, mostly white when the mosaic is
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

if isempty(obj.readerFcn)
    obj.readerFcn = utils.stitch.makeTileReader(layout);
end

if ~isempty(boundaryTile)
    % ---- boundary view: ONE tile, slices z-1 vs z ----------------------------
    tileFullI = obj.readerFcn(boundaryTile);
    tileFullJ = tileFullI;
    depthI = size(tileFullI, 3);
    depthJ = depthI;
    sizeI = layout(boundaryTile).tileSize;
    sizeJ = sizeI;
    % The browsed boundary is a property of the MOSAIC, not of the seam: it
    % is kept when the user switches tiles, so the same boundary — and the
    % correction stored at it — stays on screen everywhere (that is how the
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

% ---- geometry (tile-i coordinate frame) --------------------------------------
rowMin = min(1, 1 + deltaYX(1));
colMin = min(1, 1 + deltaYX(2));
unionH = max(sizeI(1), sizeJ(1) + deltaYX(1)) - rowMin + 1;
unionW = max(sizeI(2), sizeJ(2) + deltaYX(2)) - colMin + 1;

maxDisplayPx = 1400;
scale = max(1, ceil(max(unionH, unionW) / maxDisplayPx));

overlayMode = 'Falsecolor';
if obj.hasWidget('overlayModeDropdown')
    overlayMode = obj.view.handles.overlayModeDropdown.Value;
end
% Names the title uses for the two overlaid images: the colours in falsecolor
% mode (where they ARE the legend), plain identities in the other modes.
if ~isempty(boundaryTile)
    if strcmp(overlayMode, 'Falsecolor')
        nameI = sprintf('Cyan: slice %d', sliceA);
        nameJ = sprintf('Magenta: slice %d', sliceB);
    else
        nameI = sprintf('slice %d', sliceA);
        nameJ = sprintf('slice %d', sliceB);
    end
elseif strcmp(overlayMode, 'Falsecolor')
    nameI = sprintf('Cyan: tile %d', edge.i);
    nameJ = sprintf('Magenta: tile %d', edge.j);
    sliceNameI = 'Cyan'; sliceNameJ = 'Magenta';
else
    nameI = sprintf('tile %d', edge.i);
    nameJ = sprintf('tile %d', edge.j);
    sliceNameI = sprintf('Tile %d', edge.i);
    sliceNameJ = sprintf('Tile %d', edge.j);
end

sliceNote = '';
if ~isempty(boundaryTile)
    shiftText = '';
    if any(deltaYX ~= 0)
        shiftText = sprintf(' — current shift [%d %d]', deltaYX(1), deltaYX(2));
    end
    sliceNote = sprintf('Tile %d, Z boundary %d/%d — a fix shifts mosaic slices %d..%d%s', ...
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
        sliceNote = 'No overlapping Z slices at the current alignment — showing the middle slices';
    else
        % The pair aligned by the current dz, browsed within the slab.
        sliceA = min(max(round(requestA), slabA(1)), slabA(end));
        sliceB = sliceA - currentDz;
        if sliceB == sliceA
            sliceNote = sprintf('Slice %d/%d — Q/W browses', sliceA, depthI);
        else
            sliceNote = sprintf('%s: slice %d/%d; %s: slice %d/%d — Q/W browses', ...
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
% slice pair (3D only) — a single line does not fit the axes width.
switch overlayMode
    case 'Flicker'
        imageA = image(pairAxes, 'XData', extentI{1}, 'YData', extentI{2}, ...
            'CData', repmat(imageI, 1, 1, 3));
        imageB = image(pairAxes, 'XData', extentJ{1}, 'YData', extentJ{2}, ...
            'CData', repmat(imageJ, 1, 1, 3));
        imageB.Visible = 'off';
        obj.pairImageHandles = [imageA, imageB];
        if ~isempty(boundaryTile)
            titleLine = sprintf('Flicker — showing slice %d (Space toggles)', sliceA);
        else
            titleLine = sprintf('Flicker — showing tile %d (Space toggles)', edge.i);
        end
    case {'Checkerboard', 'Difference'}
        [canvasI, canvasJ, canvasExtent] = unionCanvases(imageI, imageJ, ...
            deltaYX, rowMin, colMin, scale);
        if strcmp(overlayMode, 'Checkerboard')
            composite = repmat(mat2gray( ...
                imfuse(canvasI, canvasJ, 'checkerboard', 'Scaling', 'joint')), 1, 1, 3);
            titleLine = sprintf('Checkerboard — %s vs %s', nameI, nameJ);
        else
            composite = repmat(mat2gray(imfuse(canvasI, canvasJ, 'diff')), 1, 1, 3);
            titleLine = sprintf('Difference — %s vs %s (dark = match)', nameI, nameJ);
        end
        image(pairAxes, 'XData', canvasExtent{1}, 'YData', canvasExtent{2}, ...
            'CData', composite);
    otherwise   % Falsecolor: i = cyan, j = magenta, aligned structures = white
        [canvasI, canvasJ, canvasExtent] = unionCanvases(imageI, imageJ, ...
            deltaYX, rowMin, colMin, scale);
        composite = cat(3, canvasJ, canvasI, max(canvasI, canvasJ));
        image(pairAxes, 'XData', canvasExtent{1}, 'YData', canvasExtent{2}, ...
            'CData', composite);
        titleLine = sprintf('%s; %s', nameI, nameJ);
end
if isempty(sliceNote)
    title(pairAxes, titleLine);
else
    title(pairAxes, {titleLine, sliceNote});
end
set(pairAxes, 'YDir', 'reverse', 'XTick', [], 'YTick', []);
axis(pairAxes, 'image');

% Re-apply the wheel zoom across re-renders of the SAME seam — nudges, drags
% and fixes all re-render, and losing the zoom on every arrow key would make
% fine alignment unusable. Selecting another seam resets to fit.
if ~isempty(obj.pairZoom) && isequal(obj.pairZoom.edgeIdx, obj.currentEdgeIdx)
    pairAxes.XLim = obj.pairZoom.xLim;
    pairAxes.YLim = obj.pairZoom.yLim;
else
    obj.pairZoom = [];
end

% Phase C interactions: click = correlate at that spot, drag = move tile j.
set(findobj(pairAxes, 'Type', 'image'), ...
    'ButtonDownFcn', @(~, evnt) obj.pairViewButtonDown(evnt));

updateOffsetLabel(obj, edge, deltaYX);
end

% =====================================================================
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
