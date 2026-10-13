function correlateStackAtPoint(obj, stripPointXY)
% CORRELATESTACKATPOINT - Ctrl+Shift+click: correlate every Z boundary at one spot.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.correlateStackAtPoint(stripPointXY)
%
% The whole-stack version of the Fix Z click-to-correlate
% (:func:`correlateAtPoint`): at the clicked spot of the mosaic crop on
% screen, EVERY boundary ``z = 2..depth`` is measured the same way - an ROI
% around the click in mosaic slice ``z-1`` matched in slice ``z``
% (:func:`utils.stitch.localCorrelate`), searched around that boundary's
% current correction - and each confident match becomes that boundary's
% correction (:attr:`zSliceFixes`, the same rigid "slice z and everything
% above" shift a single Fix Z fix stores). A boundary without a confident
% match keeps the correction it had; the status line lists them.
%
% Each slice is composed once (:meth:`fuseZMosaicSlice`) from the plan WITHOUT
% corrections (:meth:`zViewCanvas`), so every boundary is measured on its own
% raw offset, independent of the others; slice ``z`` is reused as slice
% ``z-1`` of the next boundary. The run shows a cancelable progress dialog;
% cancelling stores nothing. The whole run is ONE step of the Fix Z undo
% history (``zFixHistory``): **Ctrl+Z** gives every boundary its previous
% correction back at once (plain ``Z`` still removes only the boundary on
% screen). Only the Fix Z mosaic view offers it - in Fix XY
% a seam has one offset, not one per slice.
%
% Input Arguments:
%   - **stripPointXY** - [1x2 double] click ``[x y]`` in pair-view coordinates
%     (the crop's pixels, 1 = its origin)
%

if ~obj.dataValid() || isempty(obj.currentEdgeIdx); return; end
if ~obj.boundaryModeActive() || isempty(obj.zMosaicCrops)
    obj.setStatus('Ctrl+Shift+click correlates every Z boundary of the stack - switch the Fix mode to Fix Z.');
    return;
end

viewCanvas = obj.zViewCanvas();
mosaicDepth = viewCanvas.size(3);
region = obj.zMosaicCrops.region;
options = struct('roiSize', 128, 'searchRadius', 64);
if obj.hasWidget('ROIsizeSpinner')
    options.roiSize = obj.view.handles.ROIsizeSpinner.Value;
end
if obj.hasWidget('SearchradiusSpinner')
    options.searchRadius = obj.view.handles.SearchradiusSpinner.Value;
end

progressDialog = [];
if ~isempty(obj.progressParent()) && strcmp(obj.progressParent().Visible, 'on')
    progressDialog = uiprogressdlg(obj.progressParent(), 'Cancelable', 'on', 'Value', 0, ...
        'Title', 'Seam inspector', 'Message', 'Correlating every Z boundary at the clicked spot...');
end
dialogCleanup = onCleanup(@() closeIfValid(progressDialog));

measured = nan(mosaicDepth, 2);   % row z: the correction measured at boundary z
scores = nan(mosaicDepth, 1);
sliceBelow = obj.fuseZMosaicSlice(1, region, viewCanvas);
for zBoundary = 2:mosaicDepth
    if ~isempty(progressDialog) && isvalid(progressDialog) && progressDialog.CancelRequested
        obj.setStatus('Stack correlation cancelled - no correction changed.');
        return;
    end
    sliceAbove = obj.fuseZMosaicSlice(zBoundary, region, viewCanvas);
    [offsetYX, score, confident] = utils.stitch.localCorrelate(sliceBelow, sliceAbove, ...
        stripPointXY, obj.boundaryDelta(zBoundary), options);
    scores(zBoundary) = score;
    if confident
        measured(zBoundary, :) = offsetYX;
    end
    sliceBelow = sliceAbove;
    if ~isempty(progressDialog) && isvalid(progressDialog)
        progressDialog.Value = (zBoundary - 1) / (mosaicDepth - 1);
    end
end
if ~isempty(progressDialog) && isvalid(progressDialog) && progressDialog.CancelRequested
    obj.setStatus('Stack correlation cancelled - no correction changed.');
    return;
end

% Write every confident boundary at once; the others keep their row. The
% corrections replaced are ONE undo step: Ctrl+Z restores them all.
obj.pushZFixHistory(sprintf('stack correlation (%d boundaries set)', sum(~isnan(measured(:, 1)))));
fixes = obj.stitching.zSliceFixes;
if isempty(fixes); fixes = zeros(0, 3); end
confidentBoundaries = find(~isnan(measured(:, 1)))';
for zBoundary = confidentBoundaries
    fixes(round(fixes(:, 1)) == zBoundary, :) = [];
    fixes(end + 1, :) = [zBoundary, measured(zBoundary, :)]; %#ok<AGROW>
end
fixes(all(abs(fixes(:, 2:3)) < 0.25, 2), :) = [];   % aligned boundaries carry no correction
fixes = sortrows(fixes, 1);
obj.stitching.zSliceFixes = fixes;
obj.stitching.canvas = [];

obj.renderPairView();
obj.rescoreAfterZFix();
missed = setdiff(2:mosaicDepth, confidentBoundaries);
if isempty(missed)
    missedText = 'all boundaries matched';
else
    missedText = sprintf('no confident match (kept as before) at z = %s', ...
        strjoin(arrayfun(@(z) sprintf('%d', z), missed, 'UniformOutput', false), ', '));
end
obj.setStatus(sprintf('Stack correlation at [%d %d] of the crop: %d of %d boundaries set; %s. Ctrl+Z undoes the whole run.', ...
    round(stripPointXY(1)), round(stripPointXY(2)), numel(confidentBoundaries), mosaicDepth - 1, missedText));
end

% =====================================================================
function closeIfValid(progressDialog)
% CLOSEIFVALID - Close a progress dialog once; safe to call again.
if ~isempty(progressDialog) && isvalid(progressDialog)
    close(progressDialog);
end
end
