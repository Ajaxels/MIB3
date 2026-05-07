function SingleLandmark_Alignment(obj, parameters)
% SINGLELANDMARK_ALIGNMENT - Align a stack using a single corresponding landmark per slice.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.SingleLandmark_Alignment(parameters)
%
% Computes per-slice X/Y shifts so that one landmark on each slice maps onto
% the matching landmark of the previous slice, then applies the cumulative
% shifts via :func:`utils.align.crossShiftStack`. Landmarks may be marked
% either with the Selection layer (centroid of the connected region per
% slice) or with the Annotation tool (a single annotation per slice).
%
% Cancellation: a :class:`core.PoolWaitbar` is constructed with
% ``Cancelable = true`` whenever ``BatchOpt.showWaitbar`` is set; the cancel
% state is polled at the top of every iteration and before any irreversible
% write back to the model.
%
% Input Arguments:
%   - **parameters** — struct produced by :meth:`continueBtn_Callback`. Only
%     ``backgroundColor``, ``useBatchMode`` are used here.

id = obj.mibModel.getActiveId();
[~, ~, depth, ~] = obj.mibModel.I{id}.getDatasetDimensions('image', 3, struct('blockModeSwitch', 0));
if depth < 2
    utils.dlgs.showErrorDialog(obj.view.gui, ...
        'Single landmark alignment requires at least 2 slices.', 'Alignment');
    return;
end

% --- Choose landmark source: annotations vs. selection
useAnnotations = false;
if obj.mibModel.I{id}.annotations.getLabelsNumber() > 1
    questOpt.Icon = 'puffin_question';
    questOpt.WindowStyle = 'modal';
    answer = utils.dlgs.inputQuestDlg(obj.view.gui, ...
        sprintf(['Were the corresponding points marked with the Annotation tool, ' ...
                 'or with the Brush + Selection layer?']), ...
        'Annotations or Selection?', ...
        'Annotations', 'Selection', 'Cancel', 'Annotations', questOpt);
    if isempty(answer) || strcmp(answer, 'Cancel'); return; end
    useAnnotations = strcmp(answer, 'Annotations');
end

% --- Backup before any modification
backupOpt.id = id;
obj.mibModel.backup('mibDataset', 1, backupOpt);

pwb = [];
if obj.BatchOpt.showWaitbar
    pwb = core.PoolWaitbar(depth, 'Computing single-landmark shifts...', ...
        obj.view.gui, 'Alignment', true);
end
cleanupWb = onCleanup(@() safeDeleteWaitbar(pwb));

obj.shiftsX = zeros(1, depth);
obj.shiftsY = zeros(1, depth);
shiftX = 0;
shiftY = 0;

if ~useAnnotations
    % --- Selection-layer centroids
    optionsGetData.blockModeSwitch = 0;
    prevStats = struct([]);
    for layer = 2:depth
        if ~isempty(pwb)
            if pwb.getCancelState(); return; end
            pwb.increment();
        end
        if isempty(prevStats)
            prevSel = cell2mat(obj.mibModel.getData2D('selection', layer-1, [], NaN, optionsGetData));
            prevStats = regionprops(prevSel, 'Centroid');
        end
        if isempty(prevStats); continue; end
        currSel = cell2mat(obj.mibModel.getData2D('selection', layer, [], NaN, optionsGetData));
        currStats = regionprops(currSel, 'Centroid');
        if isempty(currStats)
            prevStats = struct([]);
            continue;
        end
        shiftX = shiftX + round(prevStats(1).Centroid(1) - currStats(1).Centroid(1));
        shiftY = shiftY + round(prevStats(1).Centroid(2) - currStats(1).Centroid(2));
        obj.shiftsX(layer:end) = shiftX;
        obj.shiftsY(layer:end) = shiftY;
        prevStats = currStats;
    end
else
    % --- Annotation positions
    prevPos = [];
    for layer = 2:depth
        if ~isempty(pwb)
            if pwb.getCancelState(); return; end
            pwb.increment();
        end
        if isempty(prevPos)
            [~, ~, prevPos] = obj.mibModel.I{id}.getSliceLabels(layer-1);   % [zxyt]
        end
        if isempty(prevPos); continue; end
        [~, ~, currPos] = obj.mibModel.I{id}.getSliceLabels(layer);
        if isempty(currPos)
            prevPos = [];
            continue;
        end
        if size(prevPos, 1) > 1 || size(currPos, 1) > 1
            utils.dlgs.showErrorDialog(obj.view.gui, ...
                sprintf(['Single-landmark alignment allows at most 1 landmark per slice.\n' ...
                        'Extra landmarks were detected on slice %d or %d.'], layer-1, layer), ...
                'Wrong number of landmarks');
            return;
        end
        shiftX = shiftX + round(prevPos(2) - currPos(2));
        shiftY = shiftY + round(prevPos(3) - currPos(3));
        obj.shiftsX(layer:end) = shiftX;
        obj.shiftsY(layer:end) = shiftY;
        prevPos = currPos;
    end
end

% --- Optional preview / confirmation in interactive mode
if ~parameters.useBatchMode
    figure(155); clf;
    plot(1:length(obj.shiftsX), obj.shiftsX, '.-', ...
         1:length(obj.shiftsY), obj.shiftsY, '.-');
    legend('Shift X', 'Shift Y'); grid on;
    xlabel('Frame number'); ylabel('Displacement');
    title('Detected single-landmark shifts');

    if ~isdeployed
        assignin('base', 'shiftX', obj.shiftsX);
        assignin('base', 'shiftY', obj.shiftsY);
    end

    questOpt2.Icon = 'puffin_question';
    questOpt2.WindowStyle = 'modal';
    choice = utils.dlgs.inputQuestDlg(obj.view.gui, ...
        'Align the stack using these displacements?', 'Align dataset', ...
        'Apply current values', 'Quit alignment', 'Quit alignment', ...
        'Apply current values', questOpt2);
    if isempty(choice) || strcmp(choice, 'Quit alignment')
        return;
    end
end

% --- Apply to image
if ~isempty(pwb)
    if pwb.getCancelState(); return; end
    pwb.updateText('Applying shifts to the image stack...');
end

shiftOpts.backgroundColor = parameters.backgroundColor;
shiftOpts.waitbar         = pwb;

imageStack = cell2mat(obj.mibModel.getData4D('image', [], NaN));
imageStackOut = utils.align.crossShiftStack(imageStack, obj.shiftsX, obj.shiftsY, shiftOpts);
if isempty(imageStackOut); return; end
obj.mibModel.setData4D(imageStackOut, 'image', [], NaN);
clear imageStack imageStackOut;

% --- Apply to service layers
serviceShiftOpts.backgroundColor = 0;
serviceShiftOpts.waitbar         = pwb;
isLabels63 = isa(obj.mibModel.I{id}.labels, 'core.MibLabels63');

if isLabels63
    if ~isempty(pwb); pwb.updateText('Applying shifts to selection / mask / labels...'); end
    layer = cell2mat(obj.mibModel.getData4D('everything', [], 0));
    shifted = utils.align.crossShiftStack(layer, obj.shiftsX, obj.shiftsY, serviceShiftOpts);
    if isempty(shifted); return; end
    obj.mibModel.setData4D(shifted, 'everything', [], 0);
else
    if obj.mibModel.I{id}.modelExist
        if ~isempty(pwb); pwb.updateText('Applying shifts to labels...'); end
        layer = cell2mat(obj.mibModel.getData4D('labels', [], NaN));
        shifted = utils.align.crossShiftStack(layer, obj.shiftsX, obj.shiftsY, serviceShiftOpts);
        if isempty(shifted); return; end
        obj.mibModel.setData4D(shifted, 'labels', [], NaN);
    end
    if obj.mibModel.I{id}.maskExist
        if ~isempty(pwb); pwb.updateText('Applying shifts to mask...'); end
        layer = cell2mat(obj.mibModel.getData4D('mask', [], 0));
        shifted = utils.align.crossShiftStack(layer, obj.shiftsX, obj.shiftsY, serviceShiftOpts);
        if isempty(shifted); return; end
        obj.mibModel.setData4D(shifted, 'mask', [], 0);
    end
    if obj.mibModel.I{id}.enableSelection
        if ~isempty(pwb); pwb.updateText('Applying shifts to selection...'); end
        layer = cell2mat(obj.mibModel.getData4D('selection', [], NaN));
        shifted = utils.align.crossShiftStack(layer, obj.shiftsX, obj.shiftsY, serviceShiftOpts);
        if isempty(shifted); return; end
        obj.mibModel.setData4D(shifted, 'selection', [], NaN);
    end
end

% --- Clear the landmarks now that they have been consumed
if ~useAnnotations
    obj.mibModel.I{id}.clearLayer('selection', '4D');
else
    obj.mibModel.I{id}.annotations.clearContents();
end

% --- Sync MibDataset metadata to the new (enlarged) canvas
ds = obj.mibModel.I{id};
ds.image.height = size(ds.image.data{1}, 1);
ds.image.width  = size(ds.image.data{1}, 2);
ds.dim_yxzct    = [ds.image.height, ds.image.width, ds.image.depth, ds.image.colors, ds.image.time];
oldSlices = ds.slices;
ds.slices{1} = [1, ds.image.height];
ds.slices{2} = [1, ds.image.width];
ds.slices{3} = 1:ds.image.depth;
ds.slices{4} = [1, 1];
ds.slices{5} = [1, 1];
ds.slices{ds.orientation} = repmat(oldSlices{ds.orientation}(1), 1, 2);

% --- Bounding box shift
maxXshift = min(obj.shiftsX);
maxYshift = min(obj.shiftsY);
maxZshift = 0;
switch ds.orientation
    case 3
        maxXshift = maxXshift * ds.image.pixSize.x;
        maxYshift = maxYshift * ds.image.pixSize.y;
    case 2
        maxZshift = maxXshift * ds.image.pixSize.z;
        maxYshift = maxYshift * ds.image.pixSize.y;
        maxXshift = 0;
    case 1
        maxZshift = maxXshift * ds.image.pixSize.z;
        maxXshift = maxYshift * ds.image.pixSize.x;
        maxYshift = 0;
end
obj.mibModel.I{id}.updateBoundingBox([], [maxXshift, maxYshift, maxZshift]);

obj.mibModel.I{id}.image.updateActionLog(sprintf( ...
    'Aligned using %s; landmark source = %s', ...
    obj.BatchOpt.Algorithm{1}, ternary(useAnnotations, 'Annotations', 'Selection')));

notify(obj.mibModel, 'NewDataset');
notify(obj.mibModel, 'ShowImage');

end

% =============================================================================
function out = ternary(condition, ifTrue, ifFalse)
if condition; out = ifTrue; else; out = ifFalse; end
end

% =============================================================================
function safeDeleteWaitbar(pwb)
if ~isempty(pwb) && isvalid(pwb)
    pwb.deletePoolWaitbar();
end
end
