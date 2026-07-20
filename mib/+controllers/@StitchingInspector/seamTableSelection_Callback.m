function seamTableSelection_Callback(obj, evnt)
% SEAMTABLESELECTION_CALLBACK - Open the seam picked in the ranked table.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.seamTableSelection_Callback(evnt)
%
% Input Arguments:
%   - **evnt** — SelectionChanged event data from the uitable (row selection)
%

if ~obj.dataValid(); return; end
selection = evnt.Selection;
if isempty(selection); return; end
rankPos = selection(1);   % row index into the (fix-mode-filtered) table
visibleRanking = obj.visibleRanking();
if rankPos >= 1 && rankPos <= numel(visibleRanking)
    obj.selectSeam(visibleRanking(rankPos));
end
end
