function inside = starPolygonMask(centre, rayDist, rowRange, colRange)
% STARPOLYGONMASK - Rasterise one star-convex StarDist polygon on a pixel window.
%
% Syntax:
%   .. code-block:: matlab
%
%      inside = deepmib.stardist.starPolygonMask(centre, rayDist, rowRange, colRange)
%
% The polygon has vertex ``k`` at ``centre + rayDist(k) * [sin(phi_k), cos(phi_k)]`` (row,
% column) with ``phi_k = 2*pi*(k-1)/N``, the StarDist convention. A pixel belongs to the polygon
% when its centre lies in the triangle (centre, vertex ``k``, vertex ``k+1``) of the angular
% sector that contains it, i.e. on the same side of that edge as the polygon centre (points on
% the edge count as inside). The test is exact for any polygon that is star-shaped with respect
% to its centre, which every StarDist polygon is by construction, and it is vectorised over the
% window, so it is faster than ``poly2mask`` or ``inpolygon`` for the small windows of the NMS.
%
% Coordinates are 0-based pixel centres, as in StarDist: pixel ``(r, c)`` of a MATLAB array is
% at ``(r-1, c-1)``.
%
% Input Arguments:
%   - **centre** - [1x2 double] polygon centre ``[row col]``, 0-based
%   - **rayDist** - [1xN numeric] ray lengths in pixels
%   - **rowRange** - [vector] 0-based row coordinates of the window
%   - **colRange** - [vector] 0-based column coordinates of the window
%
% Output Arguments:
%   - **inside** - [logical] ``[numel(rowRange), numel(colRange)]``

nRays = numel(rayDist);
angleStep = 2*pi / nRays;
phi = (0:nRays-1) * angleStep;
vertexCol = double(rayDist(:)') .* cos(phi);      % offsets from the centre
vertexRow = double(rayDist(:)') .* sin(phi);

offsetCol = (colRange(:)' - centre(2)) + zeros(numel(rowRange), 1);
offsetRow = (rowRange(:) - centre(1)) + zeros(1, numel(colRange));
sector = floor(mod(atan2(offsetRow, offsetCol), 2*pi) / angleStep);
sector(sector >= nRays) = nRays - 1;
firstVertex = sector + 1;
secondVertex = mod(sector + 1, nRays) + 1;
% reshape: indexing a row vector with a vector index returns a row whatever the shape of the
% index, so a one-column window would come back as a row and expand to a square
windowSize = size(sector);
edgeStartCol = reshape(vertexCol(firstVertex), windowSize);
edgeStartRow = reshape(vertexRow(firstVertex), windowSize);
edgeCol = reshape(vertexCol(secondVertex), windowSize) - edgeStartCol;
edgeRow = reshape(vertexRow(secondVertex), windowSize) - edgeStartRow;
% the sign of the cross product tells the side of the edge
crossPixel = edgeCol .* (offsetRow - edgeStartRow) - edgeRow .* (offsetCol - edgeStartCol);
crossCentre = edgeCol .* (-edgeStartRow) - edgeRow .* (-edgeStartCol);
inside = crossPixel .* crossCentre >= 0;
end
