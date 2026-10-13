function fixZSelectPoint(obj, pointXY)
% FIXZSELECTPOINT - Fix Z: centre the mosaic view on a mini-map point.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.fixZSelectPoint(pointXY)
%
% In Fix Z the mini-map picks WHERE to look, not a tile or a seam
% (:func:`miniMapButtonDown`): the mosaic crops of slices z-1 / z
% (:func:`buildZMosaicCrops`) are re-composed around the clicked point, at the
% SAME boundary - a boundary correction moves the whole mosaic slice, so the
% boundary belongs to the mosaic and any spot of it may be used to judge or
% measure it. The previous zoom is dropped (it framed the old crop). Nothing
% is edited.
%
% Input Arguments:
%   - **pointXY** - [1x2 double] ``[x y]`` in mini-map (solved-position)
%     coordinates (``[]`` = no-op)
%

if isempty(pointXY) || ~obj.dataValid(); return; end
obj.zMosaicCenter = [pointXY(2), pointXY(1)];   % stored [y x], like positions
obj.pairZoom = [];
obj.renderPairView();
obj.renderMiniMap();
obj.setStatus(sprintf(['Fix Z: mosaic view around [%d %d] - the boundary and its correction ' ...
    'are the same everywhere; Shift+click a distinctive spot to measure it.'], ...
    round(pointXY(2)), round(pointXY(1))));
end
