function confirmSeam_Callback(obj)
% CONFIRMSEAM_CALLBACK - Mark the current seam as reviewed-OK and advance.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.confirmSeam_Callback()
%
% Confirmation is bookkeeping only (``source = 'confirmed'``): the edge weight
% stays quality-based (design decision in plan_inspector.md). A user-fixed
% edge keeps its ``'user'`` provenance. Afterwards the review jumps to the
% next worst unreviewed seam.
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.StitchingInspector.confirmSeam_Callback: triggered\n');
end
if ~obj.dataValid() || isempty(obj.currentEdgeIdx); return; end

k = obj.currentEdgeIdx;
if strcmp(obj.stitching.edges(k).source, 'auto')
    obj.stitching.edges(k).source = 'confirmed';
end
obj.updateWidgets();
obj.advanceToNextUnreviewed();
notify(obj, 'SeamsUpdated');
end
