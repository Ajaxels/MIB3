function excludeSeam_Callback(obj)
% EXCLUDESEAM_CALLBACK - Exclude the current seam from the solve (or re-include).
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.excludeSeam_Callback()
%
% Toggles ``valid`` on the current edge. Excluding also resets the provenance
% to ``'auto'`` — a user fix that gets excluded is withdrawn (user edges are
% otherwise never pruned by the solver). The nominal springs hold the pair
% together once its measurement is excluded.
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.StitchingInspector.excludeSeam_Callback: triggered\n');
end
if ~obj.dataValid() || isempty(obj.currentEdgeIdx); return; end

k = obj.currentEdgeIdx;
if obj.stitching.edges(k).valid
    obj.stitching.edges(k).valid = false;
    obj.stitching.edges(k).source = 'auto';
else
    obj.stitching.edges(k).valid = true;   % re-include a previously excluded seam
end
obj.resolvePending = true;   % positions are stale until the next Re-solve
obj.updateWidgets();
obj.renderPairView();
notify(obj, 'SeamsUpdated');
end
