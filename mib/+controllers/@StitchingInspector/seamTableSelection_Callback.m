function seamTableSelection_Callback(obj, evnt)
% SEAMTABLESELECTION_CALLBACK - Open the seam (or slice boundary) picked in the table.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.seamTableSelection_Callback(evnt)
%
% When the table lists slice boundaries (:meth:`listsSliceBoundaries`), row
% ``r`` shows boundary ``z = r + 1`` in the Fix Z mosaic view - the same state
% Q/W browsing reaches. Otherwise the row is a seam of the fix-mode-filtered
% ranking and becomes the current seam (a cross-layer seam brings its
% boundary into the Fix Z view).
%
% Input Arguments:
%   - **evnt** - SelectionChanged event data from the uitable (row selection)
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.StitchingInspector.seamTableSelection_Callback: triggered\n');
end
if ~obj.dataValid(); return; end
selection = evnt.Selection;
if isempty(selection); return; end
rankPos = selection(1);   % row index into the (fix-mode-filtered) table

if obj.listsSliceBoundaries()
    if isempty(obj.currentEdgeIdx); return; end
    depth = obj.sliceBoundaryDepth();
    zBoundary = min(max(rankPos + 1, 2), depth);
    obj.viewSlice = struct('edgeIdx', obj.currentEdgeIdx, 'sliceA', zBoundary - 1, ...
        'sliceB', zBoundary, 'depthA', depth, 'depthB', depth, 'mosaic', true);
    obj.renderPairView();
    return;
end

visibleRanking = obj.visibleRanking();
if rankPos >= 1 && rankPos <= numel(visibleRanking)
    obj.selectSeam(visibleRanking(rankPos));
end
end
