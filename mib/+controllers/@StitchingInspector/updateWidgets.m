function updateWidgets(obj)
% UPDATEWIDGETS - Refresh the seam table, mini-map and status from the edges.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.updateWidgets()
%
% Table rows follow ``obj.visibleRanking`` (worst first, filtered to the
% current fix mode: in-plane x/y seams in Fix XY, cross-layer z seams in Fix
% Z). Row background colour encodes the seam score (red → green); the mini-map
% is redrawn to match.
%

if ~obj.dataValid()
    % A layout rebuild or edge reset in the Stitching window invalidated this
    % review session — nothing sensible left to show.
    if isfield(obj.view.handles, 'statusLabel')
        obj.view.handles.statusLabel.Text = 'Edges were reset in the Stitching window — close and reopen the inspector.';
    end
    return;
end

edges = obj.stitching.edges;
positions = obj.stitching.positions;

% ---- seam table -----------------------------------------------------------
if isfield(obj.view.handles, 'seamTable')
    seamTable = obj.view.handles.seamTable;
    visibleRanking = obj.visibleRanking();
    numEdges = numel(visibleRanking);
    tableData = cell(numEdges, 6);
    for rankPos = 1:numEdges
        k = visibleRanking(rankPos);
        e = edges(k);
        residual = (positions(e.j, 1:2) - positions(e.i, 1:2)) - e.measured(1:2);
        % One combined identifier per seam: the axis plus the two tiles it
        % joins — 'X (2-3)' / 'Y (3-6)' for in-plane seams, 'Z (8-9)' for
        % cross-layer ones. Folding the tile pair in here keeps a long ranked
        % list scannable and drops the need for a separate Tiles column.
        tableData{rankPos, 1} = sprintf('%s (%d-%d)', upper(e.direction), e.i, e.j);
        if isempty(e.seamScore) || isnan(e.seamScore)
            tableData{rankPos, 2} = NaN;
        else
            tableData{rankPos, 2} = round(e.seamScore, 3);
        end
        tableData{rankPos, 3} = round(norm(residual), 2);
        tableData{rankPos, 4} = round(e.quality, 2);
        tableData{rankPos, 5} = char(e.source);
        if e.valid
            tableData{rankPos, 6} = 'yes';
        else
            tableData{rankPos, 6} = 'EXCLUDED';
        end
    end
    seamTable.Data = tableData;
    seamTable.ColumnName = {'Seam', 'Seam score', 'Residual px', 'Quality', 'Source', 'Used'};
    % Give the merged Seam column room for 'X (2-3)'; the rest size to content.
    seamTable.ColumnWidth = {80, 'auto', 'auto', 'auto', 'auto', 'auto'};

    % Score-coloured row backgrounds (best-effort; harmless if unsupported).
    try
        removeStyle(seamTable);
        for rankPos = 1:numEdges
            k = visibleRanking(rankPos);
            addStyle(seamTable, uistyle('BackgroundColor', scoreColor(edges(k).seamScore, edges(k).valid)), ...
                'row', rankPos);
        end
    catch
        % row styling is cosmetic only
    end
end

% ---- status line ----------------------------------------------------------
if isfield(obj.view.handles, 'statusLabel')
    numReviewed = nnz(ismember({edges.source}, {'confirmed', 'user'}));
    numExcluded = nnz(~[edges.valid]);
    scores = [edges(logical([edges.valid])).seamScore];
    scores = scores(~isnan(scores));
    if isempty(scores); worstScore = NaN; else; worstScore = min(scores); end
    obj.view.handles.statusLabel.Text = sprintf( ...
        '%d seams | %d reviewed | %d excluded | worst score %.2f', ...
        numel(edges), numReviewed, numExcluded, worstScore);
end

obj.renderMiniMap();

end

% =====================================================================
function color = scoreColor(seamScore, valid)
% SCORECOLOR - Seam score / validity to a pale table background colour.
if ~valid
    color = [0.85 0.85 0.85];   % excluded: grey
elseif isempty(seamScore) || isnan(seamScore)
    color = [1.0 0.65 0.65];    % unscored/no overlap: red
elseif seamScore >= 0.7
    color = [0.78 0.93 0.78];   % good: green
elseif seamScore >= 0.4
    color = [1.0 0.92 0.70];    % suspicious: amber
else
    color = [1.0 0.72 0.72];    % bad: red
end
end
