function LandmarksBigData_Alignment(obj, parameters)
% LANDMARKSBIGDATA_ALIGNMENT - Landmark-based alignment (single/three/multi) for BigData.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.LandmarksBigData_Alignment(parameters)
%
% Landmark alignment for disk-backed pyramidal (BigData) stores; branches on
% ``parameters.method``:
%
%   - ``'Single landmark point'`` - one annotation per slice → per-slice
%     cumulative **translation** (``applyAlignmentBigData`` ``mode='translation'``).
%   - ``'Three landmark points'`` - the first slice pair carrying 3+
%     matching-labelled annotations → a single **affine** transform broadcast to
%     the tail (head unchanged).
%   - ``'Landmarks, multi points'`` - 3+ matching-labelled annotations per slice
%     pair → per-slice cumulative **affine** (``fitgeotrans``).
%
% Annotation positions are already in full-resolution (level-0) coordinates, so
% **no pyramid-level scaling is needed** - the transforms go straight into
% :meth:`applyAlignmentBigData`, which streams a NEW aligned OME-Zarr v3 store
% (+ ``Labels_<stem>.zarr3``) and swaps the active buffer. The source is never
% modified.
%
% .. note::
%    Phase 3 uses the **Annotation** layer as the landmark source (the practical
%    choice for gigapixel slides). Selection-layer landmark extraction (bounded
%    by ``selectionBBoxFull``) is a later addition.
%
% Input Arguments:
%   - **parameters** - struct built by :meth:`continueBtn_Callback`; BigData
%     fields ``isBigData`` (true), ``outputPath``, plus ``method``,
%     ``TransformationType``, ``TransformationMode``, ``transformationDegree``,
%     ``colorCh``, ``backgroundColor``, ``useBatchMode``.
%
% See also: controllers.Alignment.applyAlignmentBigData,
% controllers.Alignment.SingleLandmark_Alignment,
% controllers.Alignment.LandmarkMultiPoint_Alignment

id = obj.mibModel.getActiveId();
ds = obj.mibModel.I{id};

if ~isempty(obj.view) && isvalid(obj.view) && isvalid(obj.view.gui)
    parentFig = obj.view.gui;
else
    parentFig = obj.mibModel.mibGUI;
end

H0    = ds.image.height;
W0    = ds.image.width;
depth = ds.image.depth;

if depth < 2
    utils.dlgs.showErrorDialog(parentFig, ...
        'Landmark alignment requires at least 2 slices.', 'Alignment');
    return;
end
if ds.orientation ~= 3
    utils.dlgs.showErrorDialog(parentFig, ...
        'BigData alignment currently supports XY (orientation 3) datasets only.', 'Alignment');
    return;
end
if ds.annotations.getLabelsNumber() == 0
    utils.dlgs.showErrorDialog(parentFig, ...
        ['BigData landmark alignment uses the Annotation layer as the landmark source. ' ...
         'Place corresponding (matching-name) annotation points on consecutive slices ' ...
         'and try again.'], 'Alignment');
    return;
end

% --- Background fill (numeric); 'mean' from a level-0 first slice
if isnumeric(parameters.backgroundColor)
    bgImage = double(parameters.backgroundColor);
elseif strcmpi(parameters.backgroundColor, 'white')
    bgImage = double(ds.image.maxInt);
elseif strcmpi(parameters.backgroundColor, 'mean')
    firstSlice = squeeze(ds.image.getData('image', 3, parameters.colorCh, ...
        struct('pyramidLevel', 1, 'z', [1 1])));
    bgImage = mean(double(firstSlice(:)));
else   % 'black'
    bgImage = 0;
end

switch parameters.method
    % =================================================================
    case 'Single landmark point'
        [shiftX0, shiftY0, ok] = singleLandmarkShifts(ds, id, depth, parentFig, obj);
        if ~ok; return; end
        if ~parameters.useBatchMode && ~confirmDetectedTransforms(parentFig, 'shifts', ...
                struct('shiftX', shiftX0, 'shiftY', shiftY0), 'Detected single-landmark shifts')
            return;
        end
        tformInfo = struct('mode', 'translation', 'shiftX0', shiftX0, ...
            'shiftY0', shiftY0, 'backgroundValue', bgImage);
        obj.applyAlignmentBigData(parameters, tformInfo);

    % =================================================================
    case 'Three landmark points'
        [cumTforms, ok] = threeLandmarkTforms(ds, id, depth, parentFig);
        if ~ok; return; end
        if ~parameters.useBatchMode && ~confirmDetectedTransforms(parentFig, 'tforms', ...
                struct('tforms', {cumTforms}), 'Detected three-landmark transforms')
            return;
        end
        tformInfo = buildAffineTformInfo(cumTforms, H0, W0, depth, ...
            parameters.TransformationMode, bgImage);
        tformInfo = attachWarpedAnnotations(tformInfo, ds, cumTforms, depth);
        obj.applyAlignmentBigData(parameters, tformInfo);

    % =================================================================
    case 'Landmarks, multi points'
        switch parameters.TransformationType
            case 'nonreflectivesimilarity'; minLandmarks = 2;
            case {'similarity', 'affine'};  minLandmarks = 3;
            case {'projective', 'pwl'};     minLandmarks = 4;
            case {'polynomial', 'lwm'};     minLandmarks = 6;
            otherwise;                      minLandmarks = 3;
        end
        [cumTforms, ok] = multiPointTforms(ds, id, depth, minLandmarks, ...
            parameters.TransformationType, parameters.transformationDegree, parentFig);
        if ~ok; return; end
        if ~parameters.useBatchMode && ~confirmDetectedTransforms(parentFig, 'tforms', ...
                struct('tforms', {cumTforms}), 'Detected multi-point landmark transforms')
            return;
        end
        tformInfo = buildAffineTformInfo(cumTforms, H0, W0, depth, ...
            parameters.TransformationMode, bgImage);
        tformInfo = attachWarpedAnnotations(tformInfo, ds, cumTforms, depth);
        obj.applyAlignmentBigData(parameters, tformInfo);

    otherwise
        utils.dlgs.showErrorDialog(parentFig, ...
            sprintf('Unknown landmark method "%s".', parameters.method), 'Alignment');
        return;
end

end

% =============================================================================
function [shiftX0, shiftY0, ok] = singleLandmarkShifts(ds, id, depth, parentFig, obj) %#ok<INUSD>
% One annotation per slice → cumulative integer X/Y shifts (align each slice's
% landmark onto the previous slice's landmark). Level-0 coordinates.
ok = false;
shiftX0 = zeros(depth, 1);
shiftY0 = zeros(depth, 1);
shiftX = 0; shiftY = 0;
prevPos = [];
for layer = 2:depth
    if isempty(prevPos)
        [~, ~, prevPos] = ds.getSliceLabels(layer - 1);   % [z x y (t)]
    end
    if isempty(prevPos); continue; end
    [~, ~, currPos] = ds.getSliceLabels(layer);
    if isempty(currPos); prevPos = []; continue; end
    if size(prevPos, 1) > 1 || size(currPos, 1) > 1
        utils.dlgs.showErrorDialog(parentFig, ...
            sprintf(['Single-landmark alignment allows at most 1 annotation per slice.\n' ...
                    'Extra landmarks were detected on slice %d or %d.'], layer-1, layer), ...
            'Wrong number of landmarks');
        return;
    end
    shiftX = shiftX + round(prevPos(2) - currPos(2));
    shiftY = shiftY + round(prevPos(3) - currPos(3));
    shiftX0(layer:end) = shiftX;
    shiftY0(layer:end) = shiftY;
    prevPos = currPos;
end
ok = true;
end

% =============================================================================
function [cumTforms, ok] = threeLandmarkTforms(ds, id, depth, parentFig) %#ok<INUSD>
% Find the first slice pair with 3+ matching-labelled annotations, fit an affine
% transform, and broadcast it to the tail (identity on the head).
ok = false;
cumTforms = repmat({affinetform2d(eye(3))}, depth, 1);
for layer = 2:depth
    [labels1, ~, X1] = ds.getSliceLabels(layer - 1);
    if numel(labels1) < 3; continue; end
    [labels2, ~, X2] = ds.getSliceLabels(layer);
    if numel(labels2) < 3; continue; end
    [fixedPnts, movingPnts, nMatched] = matchByLabel(labels1, X1, labels2, X2);
    if nMatched < 3; continue; end
    try
        tform = fitgeotrans(movingPnts, fixedPnts, 'affine');
    catch ME
        utils.dlgs.showErrorDialog(parentFig, ME, 'fitgeotrans'); return;
    end
    for z = layer:depth; cumTforms{z} = tform; end
    ok = true;
    return;
end
utils.dlgs.showErrorDialog(parentFig, ...
    ['No slice pair with at least three matching-name annotations was found. ' ...
     'Place 3+ corresponding annotations on two consecutive slices and retry.'], ...
    'Three-landmark alignment');
end

% =============================================================================
function [cumTforms, ok] = multiPointTforms(ds, id, depth, minLandmarks, ...
    transformType, transformDegree, parentFig) %#ok<INUSD>
% Per-slice cumulative transform from matching-labelled annotations.
ok = false;
cumTforms = cell(depth, 1);
hasAny = false;
for layer = 2:depth
    [labels1, ~, X1] = ds.getSliceLabels(layer - 1);
    if numel(labels1) < minLandmarks; continue; end
    [labels2, ~, X2] = ds.getSliceLabels(layer);
    if numel(labels2) < minLandmarks; continue; end
    [fixedPnts, movingPnts, nMatched] = matchByLabel(labels1, X1, labels2, X2);
    if nMatched < minLandmarks; continue; end
    try
        if strcmp(transformType, 'polynomial')
            tform2 = fitgeotrans(movingPnts, fixedPnts, transformType, transformDegree);
        else
            tform2 = fitgeotrans(movingPnts, fixedPnts, transformType);
        end
    catch ME
        utils.dlgs.showErrorDialog(parentFig, ME, 'fitgeotrans'); return;
    end
    if isempty(cumTforms{layer})
        for z = layer:depth; cumTforms{z} = tform2; end
    else
        if isprop(tform2, 'T') && isprop(cumTforms{layer}, 'T')
            tform2.T = tform2.T * cumTforms{layer}.T;
        end
        for z = layer:depth; cumTforms{z} = tform2; end
    end
    hasAny = true;
end
if ~hasAny
    utils.dlgs.showErrorDialog(parentFig, ...
        ['Landmark points are missing. Place at least ' num2str(minLandmarks) ...
         ' corresponding annotations on each of two consecutive slices.'], ...
        'Multi-point landmark alignment');
    return;
end
% Fill any leading empty entries (before the first fitted pair) with identity
for z = 1:depth
    if isempty(cumTforms{z}); cumTforms{z} = affinetform2d(eye(3)); end
end
ok = true;
end

% =============================================================================
function [fixedPnts, movingPnts, nMatched] = matchByLabel(labels1, X1, labels2, X2)
% Match annotation points between two slices by identical label text. X* columns
% are [z x y (t)]; returns fixed (slice layer-1) and moving (slice layer) [x y].
fixedPnts = zeros(0, 2);
movingPnts = zeros(0, 2);
for k = 1:numel(labels1)
    j = find(strcmp(labels2, labels1{k}), 1);
    if isempty(j); continue; end
    fixedPnts(end+1, :)  = X1(k, 2:3); %#ok<AGROW>
    movingPnts(end+1, :) = X2(j, 2:3); %#ok<AGROW>
end
nMatched = size(fixedPnts, 1);
end

% =============================================================================
function tformInfo = buildAffineTformInfo(cumTforms, H0, W0, depth, transformMode, bgImage)
% Corner-project the level-0 tforms to size the output canvas and build the
% affine tformInfo for applyAlignmentBigData. Uses a world-limited OutputView
% (extended) so raw (unbaked) tforms of any type place correctly.
corners = [1, 1; W0, 1; W0, H0; 1, H0];
allX = zeros(4 * depth, 1);
allY = zeros(4 * depth, 1);
for k = 1:depth
    [wx, wy] = transformPointsForward(cumTforms{k}, corners(:, 1), corners(:, 2));
    allX((k-1)*4+1:k*4) = wx;
    allY((k-1)*4+1:k*4) = wy;
end
if strcmp(transformMode, 'extended')
    minX0 = floor(min(allX));   maxX0 = ceil(max(allX));
    minY0 = floor(min(allY));   maxY0 = ceil(max(allY));
    newW0 = maxX0 - minX0 + 1;
    newH0 = maxY0 - minY0 + 1;
    outputView = imref2d([newH0, newW0], [minX0, maxX0], [minY0, maxY0]);
    originShift = [minX0 - 1, minY0 - 1];
else   % cropped
    newW0 = W0;   newH0 = H0;
    outputView = imref2d([H0, W0]);
    originShift = [0, 0];
end
tformInfo = struct();
tformInfo.mode            = 'affine';
tformInfo.tforms          = cumTforms;
tformInfo.outputSize      = [newH0, newW0];
tformInfo.originShift     = originShift;
tformInfo.outputView      = outputView;
tformInfo.backgroundValue = bgImage;
end

% =============================================================================
function tformInfo = attachWarpedAnnotations(tformInfo, ds, cumTforms, depth)
% Capture + warp annotations into the new-canvas frame (positions [z x y t];
% warp x/y via the per-slice tform then map world->pixel through the OutputView).
if ds.annotations.getLabelsNumber() == 0; return; end
[aText, aVal, aPos] = ds.annotations.getLabels();   % [z x y t]
warpedPos = aPos;
for a = 1:size(aPos, 1)
    zSlice = round(aPos(a, 1));
    if zSlice < 1 || zSlice > depth; continue; end
    [wx, wy] = transformPointsForward(cumTforms{zSlice}, aPos(a, 2), aPos(a, 3));
    [px, py] = worldToIntrinsic(tformInfo.outputView, wx, wy);
    warpedPos(a, 2) = px;
    warpedPos(a, 3) = py;
end
tformInfo.annotations = struct('labelText', {aText}, ...
    'labelPositions', warpedPos, 'labelValues', aVal);
end
