function previewLayoutBtn_Callback(obj)
% PREVIEWLAYOUTBTN_CALLBACK - Draw nominal tile rectangles on the preview axes.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.previewLayoutBtn_Callback()
%
% Renders a top-down view of tile nominal positions as colour-coded rectangles
% on the ``previewAxes`` widget.  Each rectangle is labelled with its tile
% index.  The axes are auto-scaled to the full canvas extent.
%

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
cla(previewAxes);
hold(previewAxes, 'on');

numTiles = numel(obj.layout);
colorMap = lines(numTiles);

% Draw all rectangles first (patch honours FaceAlpha in uiaxes, unlike the RGBA
% FaceColor of rectangle()), then all labels, so numbers stay on top of overlaps.
for tileIdx = 1:numTiles
    tileOrigin = obj.layout(tileIdx).nomOrigin;  % [y x z]
    tileSize   = obj.layout(tileIdx).tileSize;    % [H W D C]

    originX = tileOrigin(2);
    originY = tileOrigin(1);
    tileW   = tileSize(2);
    tileH   = tileSize(1);

    rectangleColor = colorMap(tileIdx, :);

    patch(previewAxes, ...
        'XData',     [originX, originX + tileW, originX + tileW, originX], ...
        'YData',     [originY, originY, originY + tileH, originY + tileH], ...
        'EdgeColor', rectangleColor, ...
        'FaceColor', rectangleColor, ...
        'FaceAlpha', 0.15, ...
        'LineWidth', 1.5);
end

for tileIdx = 1:numTiles
    tileOrigin = obj.layout(tileIdx).nomOrigin;
    tileSize   = obj.layout(tileIdx).tileSize;

    centerX = tileOrigin(2) + tileSize(2) / 2;
    centerY = tileOrigin(1) + tileSize(1) / 2;
    text(previewAxes, centerX, centerY, num2str(tileIdx), ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment',   'middle', ...
        'FontSize',            9, ...
        'FontWeight',          'bold', ...
        'Color',               colorMap(tileIdx, :));
end

hold(previewAxes, 'off');
axis(previewAxes, 'equal');
axis(previewAxes, 'tight');
set(previewAxes, 'YDir', 'reverse');   % image convention: y increases downward
xlabel(previewAxes, 'X (pixels)');
ylabel(previewAxes, 'Y (pixels)');
title(previewAxes, sprintf('Layout preview — %d tiles', numTiles));

end
