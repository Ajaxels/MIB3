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

% Parent figure for any dialogs — ``obj.view`` is empty in batch mode
if ~isempty(obj.view) && isvalid(obj.view) && isvalid(obj.view.gui)
    parentFig = obj.view.gui;
else
    parentFig = obj.mibModel.mibGUI;
end

[~, ~, depth, ~] = obj.mibModel.I{id}.getDatasetDimensions('image', 3, struct('blockModeSwitch', 0));
if depth < 2
    utils.dlgs.showErrorDialog(parentFig, ...
        'Single landmark alignment requires at least 2 slices.', 'Alignment');
    return;
end

% --- Choose landmark source: annotations vs. selection
%     Skipped entirely when shifts are pre-loaded from a ``.coefXY`` file.
shiftsLoaded   = ~isempty(obj.shiftsX);
useAnnotations = false;
if ~shiftsLoaded && obj.mibModel.I{id}.annotations.getLabelsNumber() > 1
    questOpt.Icon = 'puffin_question';
    questOpt.WindowStyle = 'normal';
    answer = utils.dlgs.inputQuestDlg(parentFig, ...
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
        parentFig, 'Alignment', true);
    stepIncrement = floor(depth/10);
    pwb.setIncrement(stepIncrement);
end
cleanupWb = onCleanup(@() safeDeleteWaitbar(pwb));

if ~shiftsLoaded
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
                if mod(layer, stepIncrement) == 0; pwb.increment(); end
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
                if mod(layer, stepIncrement) == 0; pwb.increment(); end
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
                utils.dlgs.showErrorDialog(parentFig, ...
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
        questOpt2.WindowStyle = 'normal';
        choice = utils.dlgs.inputQuestDlg(parentFig, ...
            'Align the stack using these displacements?', 'Align dataset', ...
            'Apply current values', 'Quit alignment', ...
            'Apply current values', questOpt2);
        if isempty(choice) || strcmp(choice, 'Quit alignment')
            return;
        end
    end
else
    % --- Shifts came from a .coefXY file; pad/truncate to match the
    %     current dataset depth so crossShiftStack receives the right size.
    if numel(obj.shiftsX) < depth
        obj.shiftsX(end+1:depth) = obj.shiftsX(end);
        obj.shiftsY(end+1:depth) = obj.shiftsY(end);
    elseif numel(obj.shiftsX) > depth
        obj.shiftsX = obj.shiftsX(1:depth);
        obj.shiftsY = obj.shiftsY(1:depth);
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

% Replace the image canvas directly — alignment enlarges height/width and
% setData4D cannot resize the fixed-size data{1}.
img5D = obj.mibModel.I{id}.image;
newH  = size(imageStackOut, 1);
newW  = size(imageStackOut, 2);
img5D.data   = reshape(imageStackOut, [newH, newW, img5D.depth, img5D.colors, img5D.time]);
img5D.height    = newH;
img5D.width     = newW;
img5D.dim_yxzct = [newH, newW, img5D.depth, img5D.colors, img5D.time];
clear imageStack imageStackOut;

% --- Sync MibDataset metadata to the new (enlarged) canvas before any
% setData4D() call below — the layer setters validate against ds.dim_yxzct
ds = obj.mibModel.I{id};
ds.dim_yxzct = img5D.dim_yxzct;
oldSlices = ds.slices;
ds.slices{1} = [1, newH];
ds.slices{2} = [1, newW];
ds.slices{3} = 1:img5D.depth;
ds.slices{4} = [1, 1];
ds.slices{5} = [1, 1];
ds.slices{ds.orientation} = repmat(oldSlices{ds.orientation}(1), 1, 2);

% --- Apply to service layers
serviceShiftOpts.backgroundColor = 0;
serviceShiftOpts.waitbar         = pwb;
isLabels63 = isa(obj.mibModel.I{id}.labels, 'core.MibLabels63');

if isLabels63
    if ~isempty(pwb); pwb.updateText('Applying shifts to selection / mask / labels...'); end
    layer = cell2mat(obj.mibModel.getData4D('everything', [], 0));
    shifted = utils.align.crossShiftStack(layer, obj.shiftsX, obj.shiftsY, serviceShiftOpts);
    if isempty(shifted); return; end
    obj.mibModel.I{id}.labels.data  = zeros([newH, newW, img5D.depth, img5D.time], 'uint8');
    obj.mibModel.I{id}.labels.height    = newH;
    obj.mibModel.I{id}.labels.width     = newW;
    obj.mibModel.I{id}.labels.depth     = img5D.depth;
    obj.mibModel.I{id}.labels.dim_yxzct = [newH, newW, img5D.depth, 1, img5D.time];
    obj.mibModel.setData4D(shifted, 'everything', [], 0);
else
    if obj.mibModel.I{id}.modelExist
        if ~isempty(pwb); pwb.updateText('Applying shifts to labels...'); end
        layer = cell2mat(obj.mibModel.getData4D('labels', [], NaN));
        shifted = utils.align.crossShiftStack(layer, obj.shiftsX, obj.shiftsY, serviceShiftOpts);
        if isempty(shifted); return; end
        obj.mibModel.I{id}.labels.data  = zeros([newH, newW, img5D.depth, img5D.time], class(obj.mibModel.I{id}.labels.data));
        obj.mibModel.I{id}.labels.height    = newH;
        obj.mibModel.I{id}.labels.width     = newW;
        obj.mibModel.I{id}.labels.dim_yxzct = [newH, newW, img5D.depth, 1, img5D.time];
        obj.mibModel.setData4D(shifted, 'labels', [], NaN);
    end
    if obj.mibModel.I{id}.maskExist
        if ~isempty(pwb); pwb.updateText('Applying shifts to mask...'); end
        layer = cell2mat(obj.mibModel.getData4D('mask', [], 0));
        shifted = utils.align.crossShiftStack(layer, obj.shiftsX, obj.shiftsY, serviceShiftOpts);
        if isempty(shifted); return; end
        obj.mibModel.I{id}.mask.data  = zeros([newH, newW, img5D.depth, img5D.time], 'uint8');
        obj.mibModel.I{id}.mask.height    = newH;
        obj.mibModel.I{id}.mask.width     = newW;
        obj.mibModel.I{id}.mask.dim_yxzct = [newH, newW, img5D.depth, 1, img5D.time];
        obj.mibModel.setData4D(shifted, 'mask', [], 0);
    end
    if obj.mibModel.I{id}.enableSelection
        if ~isempty(pwb); pwb.updateText('Applying shifts to selection...'); end
        layer = cell2mat(obj.mibModel.getData4D('selection', [], NaN));
        shifted = utils.align.crossShiftStack(layer, obj.shiftsX, obj.shiftsY, serviceShiftOpts);
        if isempty(shifted); return; end
        obj.mibModel.I{id}.selection.data  = zeros([newH, newW, img5D.depth, img5D.time], 'uint8');
        obj.mibModel.I{id}.selection.height    = newH;
        obj.mibModel.I{id}.selection.width     = newW;
        obj.mibModel.I{id}.selection.dim_yxzct = [newH, newW, img5D.depth, 1, img5D.time];
        obj.mibModel.setData4D(shifted, 'selection', [], NaN);
    end
end

% --- Clear the landmarks now that they have been consumed (only when we
%     actually used them to detect shifts; when shifts were loaded from a
%     file the user has not declared which source to clear).
if ~shiftsLoaded
    if ~useAnnotations
        obj.mibModel.I{id}.clearLayer('selection', '4D');
    else
        obj.mibModel.I{id}.annotations.clearContents();
    end
end

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

if shiftsLoaded
    obj.mibModel.I{id}.image.updateActionLog(sprintf( ...
        'Aligned using %s; shifts loaded from file', ...
        obj.BatchOpt.Algorithm{1}));
else
    obj.mibModel.I{id}.image.updateActionLog(sprintf( ...
        'Aligned using %s; landmark source = %s', ...
        obj.BatchOpt.Algorithm{1}, ternary(useAnnotations, 'Annotations', 'Selection')));
end

% --- Save shifts to file if requested
if obj.BatchOpt.SaveShiftsToFile
    saveShiftsToFile(obj, id, parameters.useBatchMode, parentFig);
end

% keepBackup=true so the 'mibDataset' snapshot stored by backup() at the top
% of this method is not wiped by listener_newDataset.
notify(obj.mibModel, 'NewDataset', core.ToggleEventData(struct('index', id, 'keepBackup', true)));
notify(obj.mibModel, 'ShowImage');

end

% =============================================================================
function out = ternary(condition, ifTrue, ifFalse)
if condition; out = ifTrue; else; out = ifFalse; end
end

% =============================================================================
function saveShiftsToFile(obj, id, useBatchMode, parentFig)
% In batch mode the destination is derived from the dataset filename so the
% run is fully unattended; in GUI mode the path comes from the
% ``saveShiftsXYpath`` text field next to the Save-shifts checkbox.
if useBatchMode
    fn = obj.mibModel.I{id}.image.sliceName('Filename');
    [pathstr, name, ~] = fileparts(fn);
    fullPath = fullfile(pathstr, [name '_align.coefXY']);
elseif ~isempty(obj.view) && isvalid(obj.view) && isfield(obj.view.handles, 'saveShiftsXYpath')
    fullPath = obj.view.handles.saveShiftsXYpath.Value;
else
    return;
end
shiftsX = obj.shiftsX;
shiftsY = obj.shiftsY;
fprintf('Saving alignment shifts to file: %s ... ', fullPath);
try
    save(fullPath, 'shiftsX', 'shiftsY');
    fprintf('done!\n');
catch ME
    fprintf('failed.\n');
    utils.dlgs.showErrorDialog(parentFig, ME, 'Save shifts');
end
end

% =============================================================================
function safeDeleteWaitbar(pwb)
if ~isempty(pwb) && isvalid(pwb)
    pwb.deletePoolWaitbar();
end
end
