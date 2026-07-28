function twoClickBtn_Callback(obj)
% TWOCLICKBTN_CALLBACK - Toggle the two-click landmark match mode.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.twoClickBtn_Callback()
%
% For offsets too wrong for any search radius (e.g. a tile a whole texture
% period off): renders BOTH FULL TILES side by side (downsampled when larger
% than ~1024 px) and collects one click on the same landmark in each — the
% click difference IS the coarse offset, which a small-radius
% :func:`utils.stitch.localCorrelate` then sharpens. Clicks are routed here by
% :func:`pairViewButtonDown`; :func:`twoClickHandlePoint` applies the fix.
% Pressing the button again (or any re-render / navigation) cancels the mode.
%

if ~obj.dataValid() || isempty(obj.currentEdgeIdx); return; end
if ~obj.hasWidget('pairAxes'); return; end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.StitchingInspector.twoClickBtn_Callback: triggered\n');
end

if obj.twoClick.active
    obj.twoClick = struct('active', false);
    obj.renderPairView();
    obj.setStatus('Two-click match cancelled');
    return;
end

pairAxes = obj.view.handles.pairAxes;
edge = obj.stitching.edges(obj.currentEdgeIdx);
layout = obj.stitching.layout;

if isempty(obj.readerFcn)
    obj.readerFcn = utils.stitch.makeTileReader(layout);
end
imageI = flattenForDisplay(obj.readerFcn(edge.i));
imageJ = flattenForDisplay(obj.readerFcn(edge.j));

% Downsample large tiles for display; clicks are mapped back to full-res
% pixels in twoClickHandlePoint (the residual quantisation is absorbed by the
% scale-aware refinement radius there).
maxDim = max([size(imageI), size(imageJ)]);
scale = max(1, ceil(maxDim / 1024));
if scale > 1
    imageI = imresize(imageI, 1 / scale);
    imageJ = imresize(imageJ, 1 / scale);
end

low = min(min(imageI(:)), min(imageJ(:)));
high = max(max(imageI(:)), max(imageJ(:)));
if high <= low; high = low + 1; end

widthI = size(imageI, 2);
gap = max(8, round(0.05 * widthI));

cla(pairAxes);
obj.pairImageHandles = [];
obj.pairStrip = [];
handleI = image(pairAxes, 'XData', [1, widthI], 'YData', [1, size(imageI, 1)], ...
    'CData', repmat((imageI - low) / (high - low), 1, 1, 3));
handleJ = image(pairAxes, 'XData', [widthI + gap + 1, widthI + gap + size(imageJ, 2)], ...
    'YData', [1, size(imageJ, 1)], ...
    'CData', repmat((imageJ - low) / (high - low), 1, 1, 3));
set([handleI, handleJ], 'ButtonDownFcn', @(~, evnt) obj.pairViewButtonDown(evnt));
set(pairAxes, 'YDir', 'reverse', 'XTick', [], 'YTick', []);
axis(pairAxes, 'image');
title(pairAxes, sprintf('Two-click match: tile %d (left) and tile %d (right)', ...
    edge.i, edge.j));

obj.twoClick = struct('active', true, 'stage', 1, 'scale', scale, ...
    'leftWidth', widthI, 'gap', gap, 'clickA', []);
obj.setStatus(sprintf('Two-click match: click a distinctive landmark in tile %d (LEFT)', edge.i));
end

% =====================================================================
function tile = flattenForDisplay(tile)
% FLATTENFORDISPLAY - [H W D C] -> single 2D (first channel, mean over depth).
tile = tile(:, :, :, 1);
if size(tile, 3) > 1
    tile = mean(single(tile), 3);
end
tile = single(tile(:, :, 1));
end
