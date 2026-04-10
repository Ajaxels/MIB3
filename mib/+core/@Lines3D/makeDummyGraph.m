function makeDummyGraph(obj)
% function makeDummyGraph(obj)
% generate a dummy graph for developmental purposes

points = [303 81 72;...
    294 90 67;...
    294 172 56;...
    290 207 20;...
    252 268 1;...
    294 172 40;...
    387 198 42;...
    400 252 25;
    314 270 19];

s = [1 2 3 4 4 6 8];
t = [2 3 4 5 6 7 9];

Graph = graph(s, t);
Graph.Nodes.PointsXYZ = points;

Graph.Nodes.Properties.UserData.pixSize = struct();
Graph.Nodes.Properties.UserData.pixSize.x = .013;
Graph.Nodes.Properties.UserData.pixSize.y = .013;
Graph.Nodes.Properties.UserData.pixSize.z = .03;
Graph.Nodes.Properties.UserData.pixSize.units = 'um';

Graph.Nodes.PointsXYZ(:,1) = Graph.Nodes.PointsXYZ(:,1)*Graph.Nodes.Properties.UserData.pixSize.x - Graph.Nodes.Properties.UserData.pixSize.x/2;
Graph.Nodes.PointsXYZ(:,2) = Graph.Nodes.PointsXYZ(:,2)*Graph.Nodes.Properties.UserData.pixSize.y - Graph.Nodes.Properties.UserData.pixSize.y/2;
Graph.Nodes.PointsXYZ(:,3) = Graph.Nodes.PointsXYZ(:,3)*Graph.Nodes.Properties.UserData.pixSize.z - Graph.Nodes.Properties.UserData.pixSize.z/2;

Graph.Nodes.TreeName = repmat({'Tree 001'}, [size(Graph.Nodes.PointsXYZ,1), 1]);
Graph.Nodes.Radius = ones([size(Graph.Nodes.PointsXYZ,1), 1]);

Graph.Nodes.ExtraParameter1 = ones([size(Graph.Nodes.PointsXYZ,1), 1])+1;
Graph.Nodes.ExtraParameter2 = repmat({'Comment'}, [size(Graph.Nodes.PointsXYZ,1), 1]);

obj.replaceGraph(Graph);
Graph.Edges.Weight = ones([size(Graph.Edges,1), 1]);
Graph.Edges.Length = ones([size(Graph.Edges,1), 1]);

end
