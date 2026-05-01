function Graph = calculateLengthOfNodes(obj, Graph, options)
% CALCULATELENGTHOFNODES - Calculate edge lengths from coordinate endpoints.
%
% Syntax:
%   .. code-block:: matlab
%
%       Graph = obj.calculateLengthOfNodes(Graph, options)
%
% Computes the Euclidean distance for edges in the graph, updating or populating
% the ``.Length`` field based on node coordinates and optional filters.
%
% Input Arguments:
%   - **Graph** — [graph] a MATLAB graph object with node and edge information
%   - **options** — *(optional)* [struct] specifies which edges to recalculate:
%
%     - ``.nodeId`` — [numeric vector] node IDs; edges incident to these nodes are recalculated
%     - ``.edgeId`` — [numeric vector] edge IDs to recalculate (alternative to nodeId)
%     - If neither option is provided, all edges are recalculated
%
% Output Arguments:
%   - **Graph** — [graph] the input graph with ``.Length`` field populated or updated
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
