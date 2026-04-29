function Graph = calculateLengthOfNodes(obj, Graph, options)
% CALCULATELENGTHOFNODES - calculate length of nodes.
%
% Syntax:
%   function Graph = calculateLengthOfNodes(obj, Graph, options)
%
% Input Arguments:
%   - **Graph** — a graph object
%   - **options** — *(optional)* - an optional structure with
%     additional parameters
%     .nodeId - ids of nodes that include edges that should be recalculated
%
% Output Arguments:
%   - **Graph** — the graph object with added/modified Length field
%

if obj.noTrees == 0; return; end

if nargin < 3; options = struct(); end

if isfield(options, 'nodeId')   % calculate length only for specified nodes
    edge1 = find(ismember(Graph.Edges.EndNodes(:,1), options.nodeId));
    edge2 = find(ismember(Graph.Edges.EndNodes(:,2), options.nodeId));
    edgeIds = unique([edge1; edge2]);
    for edgeId = edgeIds'   % should be horizontal vector
        Graph.Edges.Length(edgeId) = sqrt(...
            (Graph.Edges.Edges(edgeId,1)-Graph.Edges.Edges(edgeId,4))^2 + ...
            (Graph.Edges.Edges(edgeId,2)-Graph.Edges.Edges(edgeId,5))^2 + ...
            (Graph.Edges.Edges(edgeId,3)-Graph.Edges.Edges(edgeId,6))^2);
    end

    % get tree name of the node
    treeName = Graph.Nodes.TreeName{options.nodeId(1)};

elseif isfield(options, 'edgeId') % calculate length only for specified edges
    % transpose to horizontal vector
    if size(options.edgeId,1) > size(options.edgeId,2); options.edgeId = options.edgeId'; end
    for edgeId = options.edgeId     % options.edgeId should be horizontal vector
        Graph.Edges.Length(edgeId) = sqrt(...
            (Graph.Edges.Edges(edgeId,1)-Graph.Edges.Edges(edgeId,4))^2 + ...
            (Graph.Edges.Edges(edgeId,2)-Graph.Edges.Edges(edgeId,5))^2 + ...
            (Graph.Edges.Edges(edgeId,3)-Graph.Edges.Edges(edgeId,6))^2);
    end
else    % calculate length for all edges
    Length = zeros([size(Graph.Edges.Edges, 1) 1]);
    for edgeId = 1:size(Graph.Edges.Edges, 1)
        Length(edgeId) = sqrt(...
            (Graph.Edges.Edges(edgeId,1)-Graph.Edges.Edges(edgeId,4))^2 + ...
            (Graph.Edges.Edges(edgeId,2)-Graph.Edges.Edges(edgeId,5))^2 + ...
            (Graph.Edges.Edges(edgeId,3)-Graph.Edges.Edges(edgeId,6))^2);
    end
    Graph.Edges.Length = Length;
end

end
