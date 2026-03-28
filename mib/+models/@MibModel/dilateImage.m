function dilateImage(obj, BatchOptIn)
% function dilateImage(obj, BatchOptIn)
% Dilate (expand) the selection, mask, or labels layer.
%
% Expands the binary content of the chosen layer using either a 2D
% disk-like structuring element (applied slice-by-slice) or a 3D ball
% structuring element (applied across the full volume).  An optional
% Difference mode retains only the pixels that were added by dilation
% (i.e. the outer ring), useful for creating boundary/outline selections.
%
% Dilation can be clipped to the extent of a model material or to the
% mask layer via the restrictSelectionToMaterial / restrictSelectionToMask
% options.
%
% Parallel 2D dilation is supported via parfor when the Parallel Computing
% Toolbox is available; use core.PoolWaitbar for thread-safe progress.
%
% Parameters:
% BatchOptIn: [@em optional] structure for batch processing mode; when NaN,
%   returns default options via the "SyncBatch" event
% @li .TargetLayer  - cell string, {'selection','mask','labels'} layer to dilate
% @li .DatasetType  - cell string, {'2D, Slice','3D, Stack','4D, Dataset'} scope
% @li .DilateMode   - cell string, {'2D','3D'} strel dimensionality
% @li .StrelSize    - string, strel radius in pixels; one value (isotropic)
%     or two values separated by a space (first = XY radius, second = Z radius
%     for 3D mode or X radius for 2D mode)
% @li .Difference   - logical, keep only the dilated ring (dilated minus original)
% @li .restrictSelectionToMaterial - string, material index (e.g. '2') or
%     'NaN' to disable; clips dilation to pixels inside the material
% @li .restrictSelectionToMask - logical, clip dilation to the mask layer
% @li .MaterialIndex - string, material index for TargetLayer='labels'
% @li .Use2DParallelComputing - logical, use parfor for 2D slice-by-slice dilation
% @li .showWaitbar  - logical, show or not the progress dialog
% @li .id           -> [@em optional] dataset index 1-9, default = obj.id
%
% Return values:
%   (none)
%

%|
% @b Examples:
% @code obj.mibModel.dilateImage();  // dilate selection on current slice with defaults @endcode
% @code
% % Dilate the mask layer across the full z-stack with a 5-px radius
% BatchOpt.TargetLayer = {'mask'};
% BatchOpt.DatasetType = {'3D, Stack'};
% BatchOpt.DilateMode  = {'2D'};
% BatchOpt.StrelSize   = '5';
% BatchOpt.Difference  = false;
% BatchOpt.showWaitbar = true;
% obj.mibModel.dilateImage(BatchOpt);
% @endcode
% @code
% % 3D ball dilation clipped to material 2, difference mode
% BatchOpt.TargetLayer = {'selection'};
% BatchOpt.DatasetType = {'4D, Dataset'};
% BatchOpt.DilateMode  = {'3D'};
% BatchOpt.StrelSize   = '3';
% BatchOpt.Difference  = true;
% BatchOpt.restrictSelectionToMaterial = '2';
% BatchOpt.showWaitbar = false;
% obj.mibModel.dilateImage(BatchOpt);
% @endcode
% @code
% % Return default BatchOpt to the Batch Processing editor
% obj.mibModel.dilateImage(NaN);
% @endcode

% Updates
% 24.03.2026 - ported from MIB2 mibModel.dilateImage; replaced waitbar/
%              PoolWaitbar with uiprogressdlg/core.PoolWaitbar; changed
%              layer name 'model' -> 'labels'; orientation 4 -> 3 for XY;
%              fixed obj.I{obj.id} -> obj.I{BatchOpt.id} throughout;
%              removed adaptive dilation (not implemented in MIB3 panel);
%              extracted do_dilate as a local function at end of file

if nargin < 2; BatchOptIn = struct(); end

%% Default BatchOpt
BatchOpt = struct();
BatchOpt.TargetLayer = {'selection'};
BatchOpt.TargetLayer{2} = {'selection', 'mask', 'labels'};
BatchOpt.DatasetType = {'2D, Slice'};
BatchOpt.DatasetType{2} = {'2D, Slice', '3D, Stack', '4D, Dataset'};
BatchOpt.DilateMode = {'2D'};
BatchOpt.DilateMode{2} = {'2D', '3D'};
BatchOpt.StrelSize = '3';
BatchOpt.MaterialIndex = '1';
BatchOpt.Difference = obj.differenceSelection;
BatchOpt.restrictSelectionToMaterial = 'NaN';
BatchOpt.restrictSelectionToMask = false;
BatchOpt.Use2DParallelComputing = false;
BatchOpt.id = obj.getActiveId();
BatchOpt.showWaitbar = true;

BatchOpt.mibBatchSectionName = 'Panel -> Selection and View Settings';
BatchOpt.mibBatchActionName  = 'Dilate';

BatchOpt.mibBatchTooltip.TargetLayer  = 'Layer to be dilated';
BatchOpt.mibBatchTooltip.DatasetType  = 'Specify whether to dilate the current slice (2D, Slice), the stack (3D, Stack) or complete dataset (4D, Dataset)';
BatchOpt.mibBatchTooltip.DilateMode   = 'Type of the strel element for dilation';
BatchOpt.mibBatchTooltip.StrelSize    = 'Radius of the strel element in pixels; one or two numbers — when two values are given the second defines Z radius (3D) or X radius (2D)';
BatchOpt.mibBatchTooltip.MaterialIndex = 'Index of the material to dilate; only for TargetLayer="labels"';
BatchOpt.mibBatchTooltip.Difference   = 'Obtain the difference between dilated and original (dilated ring only)';
BatchOpt.mibBatchTooltip.restrictSelectionToMaterial = 'Clip dilation to pixels inside the specified material index; "NaN" disables';
BatchOpt.mibBatchTooltip.restrictSelectionToMask = 'Clip dilation to the masked area';
BatchOpt.mibBatchTooltip.Use2DParallelComputing = 'Use parallel processing for 2D slice-by-slice dilation';
BatchOpt.mibBatchTooltip.showWaitbar  = 'Show or not the progress dialog during execution';

%% Batch mode check
batchModeSwitch = 0;
if isstruct(BatchOptIn) == 0
    if isnan(BatchOptIn)
        BatchOpt = rmfield(BatchOpt, 'id');
        eventdata = core.ToggleEventData(BatchOpt);
        notify(obj, 'SyncBatch', eventdata);
    else
        ErrorDlgOpt.Title  = 'BatchOpt Error';
        ErrorDlgOpt.String = 'A structure as the 1st parameter is required!';
        ErrorDlgOpt.Icon   = 'puffin_error';
        notify(obj, 'ShowErrorDialog', core.ToggleEventData(ErrorDlgOpt));
    end
    return;
else
    BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    if isfield(BatchOptIn, 'mibBatchTooltip'); batchModeSwitch = 1; end
end

%% Guard: selection disabled
if obj.I{BatchOpt.id}.enableSelection == 0
    notify(obj, 'StopProtocol');
    return;
end

tic;

%% Demote 4D to 3D when only one time point
if strcmp(BatchOpt.DatasetType{1}, '4D, Dataset') && obj.I{BatchOpt.id}.image.time == 1
    BatchOpt.DatasetType{1} = '3D, Stack';
end

%% Backup (skipped in batch mode to avoid redundant undo entries)
getDataOptions.id = BatchOpt.id;
if ~batchModeSwitch
    do3Dbackup = strcmp(BatchOpt.DilateMode{1}, '3D') || ...
                 ~strcmp(BatchOpt.DatasetType{1}, '2D, Slice');
    obj.backup(BatchOpt.TargetLayer{1}, do3Dbackup, getDataOptions);
end

%% Time-point range
if strcmp(BatchOpt.DatasetType{1}, '4D, Dataset')
    t1 = 1;
    t2 = obj.I{BatchOpt.id}.image.time;
else
    t1 = obj.I{BatchOpt.id}.slices{5}(1);
    t2 = obj.I{BatchOpt.id}.slices{5}(2);
end

%% Parse StrelSize
seSize = str2num(BatchOpt.StrelSize); %#ok<ST2NM>
if numel(seSize) == 2
    se_size(1) = seSize(1);   % XY radius
    se_size(2) = seSize(2);   % Z radius (3D) or X radius (2D anisotropic)
else
    if strcmp(BatchOpt.DilateMode{1}, '3D')
        se_size(1) = seSize;
        se_size(2) = max(round(se_size(1) * obj.I{BatchOpt.id}.image.pixSize.x / ...
                                            obj.I{BatchOpt.id}.image.pixSize.z), 1);
    else
        se_size(1) = seSize;
        se_size(2) = se_size(1);
    end
end
se_size(1) = max(se_size(1), 0);
se_size(2) = max(se_size(2), 0);

%% Material index (only relevant for 'labels' layer)
if strcmp(BatchOpt.TargetLayer{1}, 'labels')
    materialIndex = str2double(BatchOpt.MaterialIndex);
else
    materialIndex = [];
end

restrictSelectionToMaterial = str2double(BatchOpt.restrictSelectionToMaterial);

%% ================================================================
%  3D strel dilation
%% ================================================================
if strcmp(BatchOpt.DilateMode{1}, '3D')

    if BatchOpt.showWaitbar
        wb = uiprogressdlg(obj.mibGUI, 'Value', 0, ...
            'Message', sprintf('Dilating %s...\nStrel: XY=%d px  Z=%d px', ...
                BatchOpt.TargetLayer{1}, se_size(1)*2+1, se_size(2)*2+1), ...
            'Title', 'Dilating (3D)...');
    end

    % Build ball-shaped 3D structuring element
    se = zeros(se_size(1)*2+1, se_size(1)*2+1, se_size(2)*2+1);
    [x, y, z] = meshgrid(-se_size(1):se_size(1), ...
                          -se_size(1):se_size(1), ...
                          -se_size(2):se_size(2));
    ball = sqrt((x / max(se_size(1),1)).^2 + ...
                (y / max(se_size(1),1)).^2 + ...
                (z / max(se_size(2),1)).^2);
    se(ball <= 1) = 1;

    tMax = t2 - t1 + 1;
    for idx = 1:tMax
        t = t1 + idx - 1;
        if BatchOpt.showWaitbar; wb.Value = (idx-1) / tMax; end

        % Always use XY orientation (3) for volumetric strel
        original = cell2mat(obj.getData3D(BatchOpt.TargetLayer{1}, t, 3, materialIndex, getDataOptions));

        if isnan(restrictSelectionToMaterial)
            dilated = imdilate(original, se);
        else
            model3d = cell2mat(obj.getData3D('labels', t, 3, restrictSelectionToMaterial, getDataOptions));
            dilated  = bitand(imdilate(original, se), model3d);
        end

        if BatchOpt.Difference
            dilated = imabsdiff(dilated, original);
        end

        if BatchOpt.restrictSelectionToMask && ~strcmp(BatchOpt.TargetLayer{1}, 'mask')
            mask3d  = cell2mat(obj.getData3D('mask', t, 3, [], getDataOptions));
            dilated = dilated & mask3d;
        end

        obj.I{BatchOpt.id}.setData3D(dilated, BatchOpt.TargetLayer{1}, t, 3, materialIndex, getDataOptions);
    end

    if BatchOpt.showWaitbar; delete(wb); end

%% ================================================================
%  2D strel dilation (slice-by-slice)
%% ================================================================
else

    % Auto-enable parallel if a pool is already running (non-batch)
    if ~batchModeSwitch
        if ~isempty(gcp('nocreate')); BatchOpt.Use2DParallelComputing = true; end
    end

    if BatchOpt.Use2DParallelComputing
        parforArg = obj.cpuParallelLimitMax;
        if isempty(gcp('nocreate')); parpool(parforArg); end
    else
        parforArg = 0;
    end

    % Disk-like 2D strel via distance transform
    se = zeros([se_size(1)*2+1, se_size(2)*2+1], 'uint8');
    se(se_size(1)+1, se_size(2)+1) = 1;
    se = bwdist(se);
    se = uint8(se <= max(se_size));

    if strcmp(BatchOpt.DatasetType{1}, '2D, Slice')
        % ---- Single slice ----------------------------------------
        sliceIn = cell2mat(obj.getData2D(BatchOpt.TargetLayer{1}, [], [], materialIndex, getDataOptions));
        model2d = []; mask2d = [];
        if ~isnan(restrictSelectionToMaterial)
            model2d = cell2mat(obj.getData2D('labels', [], [], restrictSelectionToMaterial, getDataOptions));
        end
        if BatchOpt.restrictSelectionToMask && ~strcmp(BatchOpt.TargetLayer{1}, 'mask')
            mask2d = cell2mat(obj.getData2D('mask', [], [], [], getDataOptions));
        end
        sliceOut = do_dilate(sliceIn, model2d, mask2d, BatchOpt.Difference, se);
        obj.I{BatchOpt.id}.setData2D(sliceOut, BatchOpt.TargetLayer{1}, [], [], materialIndex, getDataOptions);

    else
        % ---- Stack / dataset: loop through slices ----------------
        orient    = obj.I{BatchOpt.id}.orientation;
        max_size  = obj.I{BatchOpt.id}.dim_yxzct(orient);
        max_size2 = max_size * (t2 - t1 + 1);
        restrictToMask = BatchOpt.restrictSelectionToMask && ~strcmp(BatchOpt.TargetLayer{1}, 'mask');

        if BatchOpt.Use2DParallelComputing
            % Parallel: use core.PoolWaitbar for thread-safe progress
            if BatchOpt.showWaitbar
                pwb = core.PoolWaitbar(max_size2, ...
                    sprintf('Dilating %s...\nStrel: %dx%d px', ...
                        BatchOpt.TargetLayer{1}, se_size(1), se_size(2)), ...
                    obj.mibGUI, 'Dilating (2D parallel)...');
                pwb.setIncrement(10);
            end

            take_difference = BatchOpt.Difference;
            showWaitbar     = BatchOpt.showWaitbar;

            for t = t1:t2
                getDataOptions.t = [t, t];
                stack   = cell2mat(obj.getData3D(BatchOpt.TargetLayer{1}, t, orient, materialIndex, getDataOptions));
                model3d = []; mask3d = [];
                if ~isnan(restrictSelectionToMaterial)
                    model3d = cell2mat(obj.getData3D('labels', t, orient, restrictSelectionToMaterial, getDataOptions));
                end
                if restrictToMask
                    mask3d = cell2mat(obj.getData3D('mask', t, orient, [], getDataOptions));
                end

                parfor (layer_id = 1:max_size, parforArg) %#ok<PFBNS>
                    if showWaitbar && mod(layer_id, 10) == 0; pwb.increment(); end %#ok<PFBNS>
                    sliceIn = stack(:, :, layer_id);
                    if max(sliceIn(:)) < 1; continue; end
                    modelSlice = []; maskSlice = [];
                    if ~isempty(model3d); modelSlice = model3d(:,:,layer_id); end %#ok<PFBNS>
                    if ~isempty(mask3d);  maskSlice  = mask3d(:,:,layer_id);  end %#ok<PFBNS>
                    stack(:, :, layer_id) = do_dilate(sliceIn, modelSlice, maskSlice, take_difference, se); %#ok<PFBNS>
                end

                obj.I{BatchOpt.id}.setData3D(stack, BatchOpt.TargetLayer{1}, t, orient, materialIndex, getDataOptions);
            end

            if BatchOpt.showWaitbar; pwb.deletePoolWaitbar(); end

        else
            % Sequential: plain uiprogressdlg updated per slice
            if BatchOpt.showWaitbar
                wb = uiprogressdlg(obj.mibGUI, 'Value', 0, ...
                    'Message', sprintf('Dilating %s...\nStrel: %dx%d px', ...
                        BatchOpt.TargetLayer{1}, se_size(1), se_size(2)), ...
                    'Title', 'Dilating (2D)...');
            end

            for t = t1:t2
                getDataOptions.t = [t, t];
                for layer_id = 1:max_size
                    if BatchOpt.showWaitbar
                        wb.Value = ((t - t1) * max_size + layer_id) / max_size2;
                    end
                    sliceIn = cell2mat(obj.getData2D(BatchOpt.TargetLayer{1}, layer_id, orient, materialIndex, getDataOptions));
                    if max(sliceIn(:)) < 1; continue; end
                    model2d = []; mask2d = [];
                    if ~isnan(restrictSelectionToMaterial)
                        model2d = cell2mat(obj.getData2D('labels', layer_id, orient, restrictSelectionToMaterial, getDataOptions));
                    end
                    if restrictToMask
                        mask2d = cell2mat(obj.getData2D('mask', layer_id, orient, [], getDataOptions));
                    end
                    sliceOut = do_dilate(sliceIn, model2d, mask2d, BatchOpt.Difference, se);
                    obj.I{BatchOpt.id}.setData2D(sliceOut, BatchOpt.TargetLayer{1}, layer_id, orient, materialIndex, getDataOptions);
                end
            end

            if BatchOpt.showWaitbar; delete(wb); end
        end
    end
end

if ~strcmp(BatchOpt.DatasetType{1}, '2D, Slice'); toc; end

%% Notify batch system and redraw
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);
notify(obj, 'ShowImage');
end


%% ================================================================
%  Local helper: perform dilation on a single 2D slice
%% ================================================================
function sliceOut = do_dilate(sliceIn, model, mask, take_difference, se)
% function sliceOut = do_dilate(sliceIn, model, mask, take_difference, se)
% Perform dilation on a single 2D binary slice with optional material
% restriction, mask clipping, and difference mode.
% Designed to be called from both sequential and parfor loops.
%
% Parameters:
% sliceIn:        [uint8, height×width] binary slice to dilate
% model:          [uint8, height×width] or [] — restrict dilation to these pixels
% mask:           [uint8, height×width] or [] — clip result to masked area
% take_difference: logical, return only the newly added pixels
% se:             [uint8, height×width] pre-built structuring element
%
% Return values:
% sliceOut: [uint8, height×width] dilated binary slice

if take_difference
    if isempty(model)
        sliceOut = imdilate(sliceIn, se) - sliceIn;
    else
        % When material-restricted, 'difference' clips to model rather than
        % computing a true set-difference (MIB2 behaviour preserved)
        sliceOut = imdilate(sliceIn, se) & model;
    end
else
    if isempty(model)
        sliceOut = imdilate(sliceIn, se);
    else
        if isa(model, 'uint8')
            sliceOut = imdilate(sliceIn, se) & bitor(model, sliceIn);
        elseif isa(model, 'uint16')
            sliceOut = imdilate(sliceIn, se) & bitor(model, uint16(sliceIn));
        else
            sliceOut = imdilate(sliceIn, se) & bitor(model, uint32(sliceIn));
        end
    end
end

% Clip to mask
if ~isempty(mask)
    sliceOut = sliceOut & mask;
end
end
