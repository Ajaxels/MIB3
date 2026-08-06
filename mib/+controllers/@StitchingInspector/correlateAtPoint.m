function correlateAtPoint(obj, stripPointXY)
% CORRELATEATPOINT - Click-to-correlate: snap the pair offset from a click.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.correlateAtPoint(stripPointXY)
%
% The "human picks WHERE, machine finds EXACTLY" tool: maps a click on the
% pair-view strip back to tile-*i* pixels and runs
% :func:`utils.stitch.localCorrelate` (ROI ``normxcorr2`` around the click,
% searched in tile *j* near the current offset). A confident peak is applied
% as a user fix - or, in the Fix-Z boundary view (both layers = the SAME tile
% at slices z-1 / z), as the per-slice mosaic correction via
% :meth:`applyZBoundaryFix`. A weak/ambiguous match only reports why and
% never moves anything. ROI size and search radius come from
% ``ROIsizeSpinner`` / ``SearchradiusSpinner`` when present (defaults 128 / 64 px).
%
% Input Arguments:
%   - **stripPointXY** - [1x2 double] click ``[x y]`` in pair-view strip
%     coordinates (the rendered overlap region, pixel 1 = strip origin)
%

if ~obj.dataValid() || isempty(obj.currentEdgeIdx) || isempty(obj.pairStrip); return; end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.StitchingInspector.correlateAtPoint: strip [%.1f %.1f]\n', ...
        stripPointXY(1), stripPointXY(2));
end

edge = obj.stitching.edges(obj.currentEdgeIdx);
bboxA = obj.pairStrip.bboxA;
clickXY = [stripPointXY(1) + bboxA(2, 1) - 1, stripPointXY(2) + bboxA(1, 1) - 1];

options = struct('roiSize', 128, 'searchRadius', 64);
if obj.hasWidget('ROIsizeSpinner')
    options.roiSize = obj.view.handles.ROIsizeSpinner.Value;
end
if obj.hasWidget('SearchradiusSpinner')
    options.searchRadius = obj.view.handles.SearchradiusSpinner.Value;
end

obj.setStatus(sprintf('Correlating a %dx%d px ROI around the click...', ...
    options.roiSize, options.roiSize));
drawnow;

% Correlate exactly the DISPLAYED slice pair. In the Fix-Z boundary view both
% "tiles" are the SAME tile at consecutive slices z-1 / z, and a confident
% match becomes the per-slice mosaic correction instead of a seam fix.
boundaryMode = obj.boundaryModeActive();
if boundaryMode
    boundaryFull = obj.readerFcn(obj.viewSlice.boundaryTile);
    tileA = boundaryFull(:, :, obj.viewSlice.sliceA, :);
    tileB = boundaryFull(:, :, obj.viewSlice.sliceB, :);
    baseOffsetYX = obj.pairStrip.deltaYX;
else
    tileA = obj.readerFcn(edge.i);
    tileB = obj.readerFcn(edge.j);
    if ~isempty(obj.viewSlice) && isequal(obj.viewSlice.edgeIdx, obj.currentEdgeIdx)
        tileA = tileA(:, :, min(max(obj.viewSlice.sliceA, 1), size(tileA, 3)), :);
        tileB = tileB(:, :, min(max(obj.viewSlice.sliceB, 1), size(tileB, 3)), :);
    end
    baseOffsetYX = obj.currentOffsetYX(obj.currentEdgeIdx);
end
[newOffsetYX, score, confident, debugInfo] = utils.stitch.localCorrelate( ...
    tileA, tileB, clickXY, baseOffsetYX, options);

if confident && boundaryMode
    obj.applyZBoundaryFix(newOffsetYX, sprintf('click-correlate, NCC %.2f', score));
elseif confident
    obj.applyUserFix([newOffsetYX, obj.fixDz(obj.currentEdgeIdx)], ...
        sprintf('click-correlate, NCC %.2f', score));
else
    obj.setStatus(sprintf(['No confident match at the click (%s, peak %.2f) - ' ...
        'offset unchanged. Try a more distinctive spot, a larger ROI, or a wider search.'], ...
        debugInfo.reason, score));
end
end
