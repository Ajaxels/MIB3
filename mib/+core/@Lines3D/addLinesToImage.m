function img = addLinesToImage(obj, img, Box, options)
% ADDLINESTOIMAGE - Render 3D lines onto a 2D image.
%
% Syntax:
%   .. code-block:: matlab
%
%       img = obj.addLinesToImage(img, Box, options)
%
% Overlays the 3D graph lines and nodes onto a 2D image slice, applying the configured
% colors and rendering parameters.
%
% Input Arguments:
%   - **img** — [numeric array] 2D or 3D image array where lines should be rendered
%   - **Box** — [1×6 numeric] clipping box ``[xmin, xmax, ymin, ymax, zmin, zmax]`` defining the region to render
%   - **options** — *(optional)* [struct] rendering settings:
%
%     - ``.orientation`` — [numeric] image plane orientation (default: ``3``):
%
%       - ``3`` — YX plane (default)
%       - ``1`` — XZ plane
%       - ``2`` — YZ plane
%
% Output Arguments:
%   - **img** — [numeric array] image with rendered lines and nodes
%

if nargin < 4; options = struct(); end
if ~isfield(options, 'orientation'); options.orientation = 3; end

pixSize = obj.G.Nodes.Properties.UserData.pixSize;
maxColor = intmax(class(img));  % maximal color intensity
imgHeight = size(img, 1);
imgWidth = size(img, 2);
imgColors = size(img, 3);

% transpose the Box,
% TransBox - is a clipping box where the TransBox(5:6) have the
% z coordinate of for the current orientation
% Box - is the clipping box oriented for the XY orientation,
% needed for clipEdge
if options.orientation == 3
    TransBox = [Box(1:4) Box(5)-pixSize.z*obj.clipExtraThickness Box(6)+pixSize.z*obj.clipExtraThickness];     % transposed box to xy, stays the same
    Box = [Box(1:4) Box(5)-pixSize.z*obj.clipExtraThickness Box(6)+pixSize.z*obj.clipExtraThickness];           % transposed box to xy
    unitsPerPixelX = (TransBox(2)-TransBox(1)+pixSize.x)/imgWidth;    % magnification of the image
    unitsPerPixelY = (TransBox(4)-TransBox(3)+pixSize.y)/imgHeight;    % magnification of the image
elseif options.orientation == 1
    TransBox = [Box(1:4) Box(5)-pixSize.y*obj.clipExtraThickness Box(6)+pixSize.y*obj.clipExtraThickness];     % transposed box to xz
    Box = [Box(3:4) Box(5)-pixSize.y*obj.clipExtraThickness Box(6)+pixSize.y*obj.clipExtraThickness Box(1:2)];  % transposed box to xy
    unitsPerPixelX = (TransBox(2)-TransBox(1)+pixSize.z)/imgWidth;    % magnification of the image
    unitsPerPixelY = (TransBox(4)-TransBox(3)+pixSize.x)/imgHeight;    % magnification of the image
elseif options.orientation == 2
    TransBox = [Box(1:4) Box(5)-pixSize.x*obj.clipExtraThickness Box(6)+pixSize.x*obj.clipExtraThickness];     % transposed box to yz
    Box = [Box(5)-pixSize.x*obj.clipExtraThickness Box(6)+pixSize.x*obj.clipExtraThickness Box(3:4) Box(1:2)];  % transposed box to xy
    unitsPerPixelX = (TransBox(2)-TransBox(1)+pixSize.z)/imgWidth;    % magnification of the image
    unitsPerPixelY = (TransBox(4)-TransBox(3)+pixSize.y)/imgHeight;    % magnification of the image
end

% get coordinates of the edges
[edgePnts, edgeIds] = obj.clipEdge(Box);   % result as [x1 y1 z1 x2 y2 z2]
noEdges = size(edgePnts, 1);

% find edges that belong to the active tree
activeTreeEdges = [];
if ~isempty(obj.activeNodeId)
    nodes1 = obj.G.Edges.EndNodes(edgeIds,1);
    nodes2 = obj.G.Edges.EndNodes(edgeIds,2);
    activeTreeEdges = unique([find(ismember(obj.G.Nodes.TreeName(nodes1), obj.G.Nodes.TreeName(obj.activeNodeId))),  ...
        find(ismember(obj.G.Nodes.TreeName(nodes2), obj.G.Nodes.TreeName(obj.activeNodeId)))]);
end

if noEdges > 0
    if options.orientation == 3
        edgePnts = edgePnts(:,[1 2 4 5]);   % [x1 y1 x2 y2], remove Z
    elseif options.orientation == 1
        edgePnts = edgePnts(:,[3 1 6 4]);   % [x1 y1 x2 y2 z1 z2], remove Y
    elseif options.orientation == 2
        edgePnts = edgePnts(:,[3 2 6 5]);   % [x1 y1 x2 y2 z1 z2], remove X
    end

    % shift coordinates to respect the bounding box of the image
    edgePnts(:,[1 3]) = edgePnts(:,[1 3]) - TransBox(1);
    edgePnts(:,[2 4]) = edgePnts(:,[2 4]) - TransBox(3);
    % shift points to respect magnification
    edgePnts(:,[1 3]) = edgePnts(:,[1 3])/unitsPerPixelX;
    edgePnts(:,[2 4]) = edgePnts(:,[2 4])/unitsPerPixelY;

    % allocate space
    edgesVec = cell([noEdges, 1]); % {edgeId}(x, y)

    % calculate points for each edge
    for edgeId=1:noEdges
        minX = min([edgePnts(edgeId,1), edgePnts(edgeId,3)]);
        maxX = max([edgePnts(edgeId,1), edgePnts(edgeId,3)]);
        minY = min([edgePnts(edgeId,2), edgePnts(edgeId,4)]);
        maxY = max([edgePnts(edgeId,2), edgePnts(edgeId,4)]);

        dX = maxX-minX;
        dY = maxY-minY;
        nPnts = ceil(max([dX dY]));

        edgesVec{edgeId}(:,1) = linspace(edgePnts(edgeId,1), edgePnts(edgeId,3), nPnts+1);
        edgesVec{edgeId}(:,2) = linspace(edgePnts(edgeId,2), edgePnts(edgeId,4), nPnts+1);
    end

    if ~isempty(activeTreeEdges)
        nonActiveIndices = 1:size(edgesVec,1);
        nonActiveIndices(activeTreeEdges) = [];
        pointsVec{1} = round(cell2mat(edgesVec(nonActiveIndices)));
        pointsVec{1}(pointsVec{1}==0) = 1;
        pointsVec{2} = round(cell2mat(edgesVec(activeTreeEdges)));
        pointsVec{2}(pointsVec{2}==0) = 1;
    else
        pointsVec{1} = round(cell2mat(edgesVec));
        pointsVec{1}(pointsVec{1}==0) = 1;
    end

    % calculate points required to make edge thicker
    if obj.edgeThickness > 1
        for i=1:numel(pointsVec)
            if isempty(pointsVec{i}); continue; end
            thickVec = -(obj.edgeThickness-1):obj.edgeThickness-1;
            thickVec(thickVec==0) = [];
            newX = bsxfun(@plus, pointsVec{i}(:,1), thickVec);
            newX = reshape(newX, [numel(newX) 1]);
            pointsVec2 = [newX repmat(pointsVec{i}(:,2), [numel(thickVec) 1])];

            newY = bsxfun(@plus, pointsVec{i}(:,2), thickVec);
            newY = reshape(newY, [numel(newY) 1]);
            pointsVec2 = [pointsVec2; repmat(pointsVec{i}(:,1), [numel(thickVec) 1]) newY];
            % find and remove points that are out of the boundary
            ids = [find(pointsVec2(:,1)<1); find(pointsVec2(:,1)>imgWidth); find(pointsVec2(:,2)<1); find(pointsVec2(:,2)>imgHeight)];
            pointsVec2(ids,:) = [];
            pointsVec{i} = [pointsVec{i}; pointsVec2];
        end
    end

    % add edges to the image
    for colId = 1:imgColors
        if ~isempty(pointsVec{1})
            pointsVec{1}(:,3) = colId;
            pointsVecIndices = sub2ind([imgHeight, imgWidth, imgColors], pointsVec{1}(:,2), pointsVec{1}(:,1), pointsVec{1}(:,3));
            img(pointsVecIndices) = obj.edgeColor(colId)*maxColor;
        end
        if numel(pointsVec) == 2
            pointsVec{2}(:,3) = colId;
            pointsVecIndices = sub2ind([imgHeight, imgWidth, imgColors], pointsVec{2}(:,2), pointsVec{2}(:,1), pointsVec{2}(:,3));
            img(pointsVecIndices) = obj.edgeActiveColor(colId)*maxColor;
        end
    end
end

% add nodes to the image
sliceId = mean([TransBox(5), TransBox(6)]);
[nodes, nodeIds] = obj.findSliceNodes(sliceId, options.orientation);   % [x, y, z]

% transpose coordinates
if options.orientation == 1
    nodes = [nodes(:,3) nodes(:,1)];
elseif options.orientation == 2
    nodes = [nodes(:,3) nodes(:,2)];
end

ids = unique([find(nodes(:,1)<TransBox(1)); find(nodes(:,1)>TransBox(2)); find(nodes(:,2)<TransBox(3)); find(nodes(:,2)>TransBox(4))]);
nodes(ids, :) = [];
nodeIds(ids) = [];

if ~isempty(nodes)
    % shift coordinates to respect the bounding box of the image
    nodes(:,1) = nodes(:,1) - TransBox(1);
    nodes(:,2) = nodes(:,2) - TransBox(3);

    nodes(:,1) = round(nodes(:,1)/unitsPerPixelX);
    nodes(:,2) = round(nodes(:,2)/unitsPerPixelY);
    nodes(nodes==0) = 1;  % replace nodes that have value 0

    nodeStrelCopy = obj.nodeStrel;
    seWidth = floor(size(nodeStrelCopy, 1)/2);

    if ~isempty(obj.activeNodeId)
        activeNodeIndex = find(nodeIds == obj.activeNodeId);
    else
        activeNodeIndex = -1;
    end

    for nodeId = 1:size(nodes, 1)
        if nodeId == activeNodeIndex
            currNodeColor = obj.nodeActiveColor;
        else
            currNodeColor = obj.nodeColor;
        end

        dx = nodes(nodeId, 1)-seWidth;
        dy = nodes(nodeId, 2)-seWidth;
        x1 = max([1 dx]);
        x2 = min([size(img, 2) nodes(nodeId, 1)+seWidth]);
        y1 = max([1 dy]);
        y2 = min([size(img, 1) nodes(nodeId, 2)+seWidth]);
        if dx > 0
            x0 = seWidth+1;
        else
            x0 = seWidth+dx;
        end
        if dy > 0
            y0 = seWidth+1;
        else
            y0 = seWidth+dy;
        end

        mask = zeros([y2-y1+1, x2-x1+1], 'uint8');
        mask(y0, x0) = 1;
        mask = imdilate(mask, nodeStrelCopy);

        for colId = 1:imgColors
            imgCrop = img(y1:y2, x1:x2, colId);
            imgCrop(mask==1) = currNodeColor(colId)*maxColor;
            img(y1:y2, x1:x2, colId) = imgCrop;
        end
    end
end

end
