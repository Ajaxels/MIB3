function [edge, edgeIds] = clipEdge(obj, Box)
% CLIPEDGE - clip the edge using the Box matrix.
%
% Syntax:
%   .. code-block:: matlab
%
%       [edge, edgeIds] = obj.clipEdge(Box)
%
% Input Arguments:
%   - **Box** — a vector used for cliping the edges [xMin, xMax, yMin, yMax, zMin, zMax]
%
% Output Arguments:
%   - **edge** — a matrix of edges shown inside the clipping box, [x1 y1 z1 x2 y2 z2]
%   - **edgeIds** — indices of the returned edges
%

try
    % remove edges that are outside the bounding box
    % speeds up clipEdge3d in about 5-10 times
    Edges = obj.G.Edges.Edges;  % [x1 y1 z1 x2 y2 z2]
    Edges(Edges(:,1) < Box(1) & Edges(:,4) < Box(1), :) = [];
    Edges(Edges(:,1) > Box(2) & Edges(:,4) > Box(2), :) = [];
    Edges(Edges(:,2) < Box(3) & Edges(:,5) < Box(3), :) = [];
    Edges(Edges(:,2) > Box(4) & Edges(:,5) > Box(4), :) = [];
    Edges(Edges(:,3) < Box(5) & Edges(:,6) < Box(5), :) = [];
    Edges(Edges(:,3) > Box(6) & Edges(:,6) > Box(6), :) = [];

    edge = clipEdge3d(Edges, Box);
catch err
    edge = []; edgeIds = []; return;
end
edgeIds = find(~isnan(edge(:,1)));
% remove NaN edges
edge = edge(edgeIds, :);

end
