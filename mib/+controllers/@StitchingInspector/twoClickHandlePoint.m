function twoClickHandlePoint(obj, pointXY)
% TWOCLICKHANDLEPOINT - Collect the two landmark clicks and apply the match.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.twoClickHandlePoint(pointXY)
%
% Stage 1 stores the landmark click in tile *i* (left image); stage 2 takes
% the same landmark in tile *j* (right image) — the click difference is the
% coarse pair offset (``dy = rowA - rowB``, the ``pos_j - pos_i`` convention),
% then :func:`utils.stitch.localCorrelate` refines it within a small,
% scale-aware radius. An unconfident refinement falls back to the coarse
% offset (it is the user's explicit statement) instead of being dropped.
%
% Input Arguments:
%   - **pointXY** — [1x2 double] click ``[x y]`` in the side-by-side view's
%     display coordinates (from :func:`pairViewButtonDown`)
%

if ~obj.dataValid() || isempty(obj.currentEdgeIdx) || ~obj.twoClick.active; return; end

state = obj.twoClick;
splitX = state.leftWidth + state.gap / 2;
% Display pixel u -> full-res pixel (centre-aligned imresize mapping).
toFullRes = @(u) (u - 0.5) * state.scale + 0.5;
edge = obj.stitching.edges(obj.currentEdgeIdx);

if state.stage == 1
    if pointXY(1) > splitX
        obj.setStatus(sprintf('First click the landmark in tile %d — the LEFT image', edge.i));
        return;
    end
    obj.twoClick.clickA = [toFullRes(pointXY(1)), toFullRes(pointXY(2))];
    obj.twoClick.stage = 2;
    obj.setStatus(sprintf('Now click the SAME landmark in tile %d (RIGHT)', edge.j));
    return;
end

if pointXY(1) <= splitX
    obj.setStatus(sprintf('Now the landmark in tile %d — the RIGHT image', edge.j));
    return;
end
clickA = state.clickA;
clickB = [toFullRes(pointXY(1) - state.leftWidth - state.gap), toFullRes(pointXY(2))];
coarseOffsetYX = [clickA(2) - clickB(2), clickA(1) - clickB(1)];
obj.twoClick = struct('active', false);

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.StitchingInspector.twoClickHandlePoint: coarse [%.1f %.1f]\n', ...
        coarseOffsetYX(1), coarseOffsetYX(2));
end

% Sharpen the eyeballed offset: small radius (the coarse offset is close),
% widened with the display downsampling so click quantisation stays covered.
options = struct('roiSize', 128, 'searchRadius', max(12, 4 * state.scale));
if isfield(obj.view.handles, 'roiSizeSpinner')
    options.roiSize = obj.view.handles.roiSizeSpinner.Value;
end
tileA = obj.readerFcn(edge.i);
tileB = obj.readerFcn(edge.j);
[refinedOffsetYX, score, confident] = utils.stitch.localCorrelate( ...
    tileA, tileB, clickA, coarseOffsetYX, options);

if confident
    obj.applyUserFix(refinedOffsetYX, sprintf('two-click + refine, NCC %.2f', score));
else
    obj.applyUserFix(coarseOffsetYX, 'two-click (coarse — refinement unconfident)');
end
end
