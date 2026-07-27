function applyZBoundaryFix(obj, deltaYX, description)
% APPLYZBOUNDARYFIX - Set the per-slice mosaic correction at the viewed Z boundary.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.applyZBoundaryFix(deltaYX, description)
%
% Fix-Z counterpart of :meth:`applyUserFix`: instead of editing a seam, it
% records that every mosaic output slice ``>= z`` (the boundary on screen,
% ``viewSlice.sliceB``) shifts in-plane by ``deltaYX`` relative to the slices
% below — "align slice z to slice z-1 and carry everything above along".
% Stored in the parent's ``zSliceFixes`` (one row per boundary, replaced on
% re-fix, dropped when the correction returns to zero), applied by
% ``planCanvas``/the fusers at the next fuse, and saved in the project
% sidecar. The solver is NOT involved — tile positions are untouched.
%
% Input Arguments:
%   - **deltaYX** — [1x2 double] ``[dy dx]`` shift of slices ``>= z`` relative
%     to the slices below
%   - **description** — [char] human-readable source of the fix (status line)
%

if ~obj.boundaryModeActive(); return; end

zBoundary = obj.viewSlice.sliceB;
fixes = obj.stitching.zSliceFixes;
if isempty(fixes); fixes = zeros(0, 3); end

row = find(round(fixes(:, 1)) == zBoundary, 1);
if isempty(row)
    fixes(end + 1, :) = [zBoundary, deltaYX(1), deltaYX(2)];
else
    fixes(row, 2:3) = deltaYX;
end
% A correction dragged back to (sub-pixel) zero is a removal, not a fix.
fixes(all(abs(fixes(:, 2:3)) < 0.25, 2), :) = [];

obj.stitching.zSliceFixes = fixes;
obj.stitching.canvas = [];   % re-plan with the new per-slice shifts on the next fuse

obj.renderPairView();
obj.setStatus(sprintf(['Z boundary %d: mosaic slices %d..end shifted by [%.1f %.1f] (%s) — ' ...
    'Stitch applies it; Z removes it. Saved with the project.'], ...
    zBoundary, zBoundary, deltaYX(1), deltaYX(2), description));
end
