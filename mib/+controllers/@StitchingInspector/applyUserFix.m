function applyUserFix(obj, newOffsetYX, description, deferResolve)
% APPLYUSERFIX - Write a user-fixed pair offset into the current edge.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.applyUserFix(newOffsetYX, description)
%      obj.applyUserFix(newOffsetYX, description, deferResolve)
%
% The single write path shared by every fixing tool (drag,
% click-to-correlate, two-click match): backs up the original automatic edge
% once (for ``Z`` undo), replaces the measurement by the user's offset with
% ``source = 'user'`` / ``quality = 1`` — the solvers weight user edges at
% ``userEdgeWeight`` and never prune them — and re-solves globally unless
% deferred by the caller or auto-re-solve is off.
%
% Input Arguments:
%   - **newOffsetYX** — [1x2 or 1x3 double] pair offset ``[dy dx]`` (or
%     ``[dy dx dz]``) in the ``positions(j,:) - positions(i,:)`` convention
%   - **description** — [char] short provenance text for the status line
%   - **deferResolve** *(optional)* — [logical] skip the auto re-solve
%     (default: ``false``)
%

if nargin < 4; deferResolve = false; end
if ~obj.dataValid() || isempty(obj.currentEdgeIdx); return; end
k = obj.currentEdgeIdx;

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.StitchingInspector.applyUserFix: edge %d -> [%g %g] (%s)\n', ...
        k, newOffsetYX(1), newOffsetYX(2), description);
end

% One backup per edge = the ORIGINAL automatic measurement; consecutive fixes
% (e.g. a nudge sequence) keep the first backup so undo restores the auto edge.
if numel(obj.autoBackup) < numel(obj.stitching.edges)
    obj.autoBackup{numel(obj.stitching.edges)} = [];
end
if isempty(obj.autoBackup{k})
    obj.autoBackup{k} = obj.stitching.edges(k);
end

obj.stitching.edges(k).measured(1:2) = newOffsetYX(1:2);
if numel(newOffsetYX) >= 3
    obj.stitching.edges(k).measured(3) = newOffsetYX(3);
end
obj.stitching.edges(k).source  = 'user';
obj.stitching.edges(k).quality = 1;
obj.stitching.edges(k).valid   = true;
obj.stitching.edges(k).tform   = [];   % user fixes are pure translation

edge = obj.stitching.edges(k);
if ~deferResolve && obj.autoResolveEnabled()
    obj.resolveBtn_Callback();   % re-solve + re-score + re-rank + SeamsUpdated
    obj.setStatus(sprintf('Seam %d-%d fixed (%s) — re-solved', edge.i, edge.j, description));
else
    obj.resolvePending = true;   % Stitch must re-solve first (Stitching.stitchBtn_Callback)
    obj.updateWidgets();
    obj.renderPairView();
    notify(obj, 'SeamsUpdated');
    obj.setStatus(sprintf('Seam %d-%d fixed (%s) — press Re-solve to apply globally', ...
        edge.i, edge.j, description));
end
end
