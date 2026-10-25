function labels = polygonsToLabel(points, rayDist, scores, imageSize)
% POLYGONSTOLABEL - Draw StarDist polygons into an instance label image, higher scores on top.
%
% Syntax:
%   .. code-block:: matlab
%
%      labels = deepmib.stardist.polygonsToLabel(points, rayDist, scores, imageSize)
%
% Polygons are drawn from the lowest to the highest score, so where kept polygons overlap the
% higher-scoring one wins. Label 1 is the polygon with the highest score, label ``n`` the
% lowest; a polygon fully covered by higher-scoring ones leaves no pixels, so the label image
% can have gaps in its ids. Pixels are filled when their centre is inside the polygon (see
% deepmib.stardist.starPolygonMask), which matches ``skimage.draw.polygon`` used by StarDist
% ``polygons_to_label``. Parts outside the image are cut off.
%
% Input Arguments:
%   - **points** - [double] ``[n, 2]`` polygon centres ``[row col]``, 0-based pixels
%   - **rayDist** - [numeric] ``[n, nRays]`` ray lengths
%   - **scores** - [numeric] ``[n, 1]`` scores
%   - **imageSize** - [1x2 numeric] ``[height width]`` of the label image
%
% Output Arguments:
%   - **labels** - [uint32] label image ``[height, width]``, 0 = background

labels = zeros(imageSize(1:2), 'uint32');
nPolygons = numel(scores);
if nPolygons == 0; return; end
[~, rankDescending] = sort(scores, 'descend');
labelIds = zeros(nPolygons, 1, 'uint32');
labelIds(rankDescending) = 1:nPolygons;
nRays = size(rayDist, 2);
phi = (0:nRays-1) * 2*pi / nRays;
for polygonId = rankDescending(end:-1:1)'
    vertexRow = points(polygonId, 1) + double(rayDist(polygonId, :)) .* sin(phi);
    vertexCol = points(polygonId, 2) + double(rayDist(polygonId, :)) .* cos(phi);
    rowRange = max(0, ceil(min(vertexRow))) : min(imageSize(1)-1, floor(max(vertexRow)));
    colRange = max(0, ceil(min(vertexCol))) : min(imageSize(2)-1, floor(max(vertexCol)));
    if isempty(rowRange) || isempty(colRange); continue; end
    inside = deepmib.stardist.starPolygonMask(points(polygonId, :), rayDist(polygonId, :), rowRange, colRange);
    window = labels(rowRange+1, colRange+1);
    window(inside) = labelIds(polygonId);
    labels(rowRange+1, colRange+1) = window;
end
end
