function refuseBtn_Callback(obj)
% REFUSEBTN_CALLBACK - Re-fuse the mosaic with the corrected positions.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.refuseBtn_Callback()
%
% Delegates the full fuse to the parent Stitching window's
% ``stitchBtn_Callback`` — both output modes work identically to pressing
% *Stitch* there: **In memory** re-fuses in seconds and opens a new dataset,
% **OME-Zarr (BigData)** re-runs the streaming fuse over the whole canvas and
% reopens it. If a user fix is still awaiting its global re-solve
% (auto-re-solve off or a deferred nudge), the re-solve runs FIRST so the
% fuse never uses stale positions. A partial (dirty-region) BigData re-fuse
% is a listed future optimisation — v1 always re-fuses fully.
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.StitchingInspector.refuseBtn_Callback: triggered\n');
end
if ~obj.dataValid(); return; end

if obj.resolvePending
    obj.setStatus('Applying the pending re-solve before fusing...');
    obj.resolveBtn_Callback();
    if ~obj.dataValid(); return; end
end

obj.setStatus('Re-fusing with the corrected positions...');
drawnow;
try
    obj.stitching.stitchBtn_Callback();
    obj.setStatus('Re-fuse complete — the fused dataset opened in MIB.');
catch fuseError
    obj.setStatus(sprintf('Re-fuse failed: %s', fuseError.message));
end
end
