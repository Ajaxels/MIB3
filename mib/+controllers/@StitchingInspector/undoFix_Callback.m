function undoFix_Callback(obj)
% UNDOFIX_CALLBACK - Restore the current seam's original automatic edge.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.undoFix_Callback()
%
% Undoes ALL fixes applied to the current seam this session (``Z`` or
% ``undoFixBtn``): the first :func:`applyUserFix` on an edge backs up the
% original automatic measurement, and this restores it - measurement,
% quality, validity, transform and provenance alike. In-memory only; a saved
% project keeps whatever state was current at save time. In the Fix-Z
% boundary view it instead removes the per-slice mosaic correction at the
% boundary on screen.
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.StitchingInspector.undoFix_Callback: triggered\n');
end
if ~obj.dataValid() || isempty(obj.currentEdgeIdx); return; end

if obj.boundaryModeActive()
    zBoundary = obj.viewSlice.sliceB;
    fixes = obj.stitching.zSliceFixes;
    if isempty(fixes) || ~any(round(fixes(:, 1)) == zBoundary)
        obj.setStatus(sprintf('No correction at Z boundary %d to remove', zBoundary));
        return;
    end
    fixes(round(fixes(:, 1)) == zBoundary, :) = [];
    obj.stitching.zSliceFixes = fixes;
    obj.stitching.canvas = [];
    obj.renderPairView();
    obj.setStatus(sprintf('Z boundary %d correction removed', zBoundary));
    return;
end

k = obj.currentEdgeIdx;
if numel(obj.autoBackup) < k || isempty(obj.autoBackup{k})
    obj.setStatus('Nothing to undo on this seam (no fix applied this session)');
    return;
end

edge = obj.autoBackup{k};
obj.stitching.edges(k) = edge;
obj.autoBackup{k} = [];

if obj.autoResolveEnabled()
    obj.resolveBtn_Callback();
else
    obj.resolvePending = true;   % positions are stale until the next re-solve
    obj.updateWidgets();
    obj.renderPairView();
    notify(obj, 'SeamsUpdated');
end
obj.setStatus(sprintf('Seam %d-%d restored to the automatic measurement', edge.i, edge.j));
end
