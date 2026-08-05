function ensureTileThumbs(obj)
% ENSURETILETHUMBS - Build the per-tile mini-map thumbnails once (lazy).
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.ensureTileThumbs()
%
% Reads every tile through the shared LRU reader, flattens it for display
% (first channel, mean over depth) and downsamples it so the whole mosaic
% spans ~1000 thumbnail pixels; the thumbs are jointly normalised to
% ``[0 1]``. ``renderMiniMap`` composites them at the CURRENT solved
% positions on every redraw (cheap), so a gross misplacement is visible in
% the actual image content, not just the score colouring. Built once per
% session — tiles never change while the inspector is open (``dataValid``
% guards layout rebuilds). Datasets whose tiles sum to more than ~1.5 G
% full-res pixels skip the thumbnail (patches only) instead of stalling the
% open; any read failure declines the same way.
%

if ~isnan(obj.thumbScale); return; end   % built (or declined) already
obj.thumbScale = 0;                      % declined until proven otherwise
if ~obj.dataValid(); return; end

layout = obj.stitching.layout;
positions = obj.stitching.positions;
numTiles = numel(layout);

totalPixels = 0;
for tileIdx = 1:numTiles
    totalPixels = totalPixels + prod(layout(tileIdx).tileSize(1:3));
end
if totalPixels > 1.5e9; return; end

% Mosaic extent -> one shared thumb scale (~1000 px across the long side).
tileSizes = reshape([layout.tileSize], [], numTiles)';
minYX = min(positions(:, 1:2), [], 1);
maxYX = max(positions(:, 1:2) + tileSizes(:, 1:2), [], 1);
scale = max(1, ceil(max(maxYX - minYX) / 1000));

% Progress anchored to the parent Stitching window while our own figure is
% still hidden (inspector construction), same pattern as scoreAndRank.
parentFigure = obj.progressParent();
progressDialog = [];
if ~isempty(parentFigure) && strcmp(parentFigure.Visible, 'on')
    progressDialog = uiprogressdlg(parentFigure, 'Value', 0, ...
        'Message', 'Building mini-map preview...', 'Title', 'Seam inspector');
end

try
    obj.tileReader();
    thumbs = cell(1, numTiles);
    low = Inf; high = -Inf;
    for tileIdx = 1:numTiles
        tile = obj.readerFcn(tileIdx);
        tile = tile(:, :, :, 1);                       % first channel
        if size(tile, 3) > 1
            tile = mean(single(tile), 3);              % mean over depth
        end
        tile = single(tile(:, :, 1));
        if scale > 1
            tile = imresize(tile, 1 / scale);
        end
        thumbs{tileIdx} = tile;
        low = min(low, min(tile(:)));
        high = max(high, max(tile(:)));
        if ~isempty(progressDialog) && isvalid(progressDialog)
            progressDialog.Value = tileIdx / numTiles;
        end
    end
    if high <= low; high = low + 1; end
    for tileIdx = 1:numTiles
        thumbs{tileIdx} = (thumbs{tileIdx} - low) / (high - low);
    end
    obj.tileThumbs = thumbs;
    obj.thumbScale = scale;
catch
    obj.tileThumbs = {};   % declined — the mini-map falls back to patches only
    obj.thumbScale = 0;
end
if ~isempty(progressDialog) && isvalid(progressDialog)
    close(progressDialog);
end
end
