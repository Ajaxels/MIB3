function erodeImage(obj, BatchOptIn)
% ERODEIMAGE - Erode the selection, mask, or labels layer.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.erodeImage(BatchOptIn)
%
% Shrinks the binary content of the chosen layer using either a 2D
% disk-like structuring element (applied slice-by-slice) or a 3D ball
% structuring element (applied across the full volume).  An optional
% Difference mode retains only the pixels that were removed by erosion
% (i.e. the eroded ring), useful for creating boundary/outline selections.
%
% Parallel 2D erosion is supported via parfor when the Parallel Computing
% Toolbox is available; use core.PoolWaitbar for thread-safe progress.
%
% **Cancel.** The progress dialog is cancelable. Each time point is computed
% into a local array and written only when it is complete, so Cancel discards
% the time point in progress and a 3D stack is left unchanged. 2D slice-by-slice
% erosion polls Cancel between batches of slices (one slice sequentially, 4 per
% worker in parallel - workers cannot see the dialog); 3D erosion is one
% operation per time point, so Cancel acts before and after it. When earlier
% time points of a 4D dataset were already written, a dialog says which; the
% Undo backup holds only the current time point and cannot revert them. In
% batch mode a Cancel also stops the protocol (``StopProtocol``).
%
% **Memory.** 2D slice-by-slice erosion holds one time point of the layer in a
% local array, in the sequential mode too.
%
% Performance: for a radius above ``bwdistRadiusThreshold`` (5 px) with a
% spherical/circular element (equal XY and Z / X and Y radii) the operation is
% computed as ``bwdist(~BW) > R`` (see utils.morphBallOp), which is O(N)
% regardless of radius instead of the O(R^2)/O(R^3) brute-force cost of a raw
% structuring element. Large anisotropic 3D elements keep the accurate (slow)
% ellipsoidal imerode unless ``AnisotropicMethod`` requests ``'Fast (bwdist)'``
% (the Selection panel offers this choice through a single dialog; batch/API
% callers set the field directly). This method itself never opens a dialog.
%
% Input Arguments:
%   - **BatchOptIn** - *(optional)* structure for batch processing mode; when NaN,
%     returns default options via the "SyncBatch" event
%
%     - ``.TargetLayer`` - cell string, ``{'selection','mask','labels'}`` layer to erode
%     - ``.DatasetType`` - cell string, ``{'2D, Slice','3D, Stack','4D, Dataset'}`` scope
%     - ``.ErodeMode`` - cell string, ``{'2D','3D'}`` strel dimensionality
%     - ``.StrelSize`` - string, strel radius in pixels; one value (isotropic)
%       or two values separated by a space (first = XY radius, second = Z radius
%       for 3D mode or X radius for 2D mode)
%     - ``.Difference`` - logical, keep only the eroded ring (original minus eroded)
%     - ``.MaterialIndex`` - string, material index for TargetLayer= ``'labels'``; use
%       ``NaN`` to erode all materials (not yet implemented - pass a valid index)
%     - ``.Use2DParallelComputing`` - logical, use parfor for 2D slice-by-slice erosion
%     - ``.AnisotropicMethod`` - cell string, ``{'Accurate (slow)','Fast (bwdist)'}``;
%       only consulted for large-radius 3D erosion on anisotropic voxels - see
%       the performance note below
%     - ``.showWaitbar`` - logical, show or not the progress dialog
%     - ``.id`` - *(optional)* dataset index 1-9, default = obj.id
%
%
% Output Arguments:
%   (none)
%
% Usage:
%   **Example 1** - erode selection on current slice with defaults
%
%   .. code-block:: matlab
%
%      obj.mibModel.erodeImage();
%
%   **Example 2** - erode the mask layer across the full z-stack with a 5-px radius
%
%   .. code-block:: matlab
%
%      BatchOpt.TargetLayer = {'mask'};
%      BatchOpt.DatasetType = {'3D, Stack'};
%      BatchOpt.ErodeMode   = {'2D'};
%      BatchOpt.StrelSize   = '5';
%      BatchOpt.Difference  = false;
%      BatchOpt.showWaitbar = true;
%      obj.mibModel.erodeImage(BatchOpt);
%
%   **Example 3** - 3D ball erosion of labels material 2 across whole dataset
%
%   .. code-block:: matlab
%
%      BatchOpt.TargetLayer   = {'labels'};
%      BatchOpt.DatasetType   = {'4D, Dataset'};
%      BatchOpt.ErodeMode     = {'3D'};
%      BatchOpt.StrelSize     = '3';
%      BatchOpt.MaterialIndex = '2';
%      BatchOpt.showWaitbar   = false;
%      obj.mibModel.erodeImage(BatchOpt);
%
%   **Example 4** - return default BatchOpt to the Batch Processing editor
%
%   .. code-block:: matlab
%
%      obj.mibModel.erodeImage(NaN);
%

% Updates
% 24.03.2026 - ported from MIB2 mibModel.erodeImage; replaced waitbar/
%              PoolWaitbar with uiprogressdlg/core.PoolWaitbar; changed
%              layer name 'model' -> 'labels'; orientation 4 -> 3 for XY;
%              fixed obj.id -> obj.I{BatchOpt.id} throughout
% 22.07.2026 - added bwdist fast path for large isotropic elements (radius > 5)
%              via utils.morphBallOp; added AnisotropicMethod option + warning
%              dialog (utils.morphAnisotropicMethod) for large anisotropic 3D
% 15.10.2026 - cancelable progress dialogs; 2D stack erosion runs in batches
%              that write each time point once (sequential path merged into it)

if nargin < 2; BatchOptIn = struct(); end

%% Default BatchOpt
BatchOpt = struct();
BatchOpt.TargetLayer = {'selection'};
BatchOpt.TargetLayer{2} = {'selection', 'mask', 'labels'};
BatchOpt.DatasetType = {'2D, Slice'};
BatchOpt.DatasetType{2} = {'2D, Slice', '3D, Stack', '4D, Dataset'};
BatchOpt.ErodeMode = {'2D'};
BatchOpt.ErodeMode{2} = {'2D', '3D'};
BatchOpt.StrelSize = '3';
BatchOpt.MaterialIndex = '1';
BatchOpt.Difference = obj.differenceSelection;
BatchOpt.Use2DParallelComputing = false;
BatchOpt.AnisotropicMethod = {'Accurate (slow)'};
BatchOpt.AnisotropicMethod{2} = {'Accurate (slow)', 'Fast (bwdist)'};
BatchOpt.id = obj.getActiveId();
BatchOpt.showWaitbar = true;

BatchOpt.mibBatchSectionName = 'Panel -> Selection and View Settings';
BatchOpt.mibBatchActionName  = 'Erode';

BatchOpt.mibBatchTooltip.TargetLayer  = 'Layer to be eroded';
BatchOpt.mibBatchTooltip.DatasetType  = 'Specify whether to erode the current slice (2D, Slice), the stack (3D, Stack) or complete dataset (4D, Dataset)';
BatchOpt.mibBatchTooltip.ErodeMode    = 'Type of the strel element for erosion';
BatchOpt.mibBatchTooltip.StrelSize    = 'Radius of the strel element in pixels; one or two numbers - when two values are given the second defines Z radius (3D) or X radius (2D)';
BatchOpt.mibBatchTooltip.MaterialIndex = 'Index of the material to erode; only for TargetLayer="labels"';
BatchOpt.mibBatchTooltip.Difference   = 'Obtain the difference between eroded and original (eroded ring only)';
BatchOpt.mibBatchTooltip.Use2DParallelComputing = 'Use parallel processing for 2D slice-by-slice erosion';
BatchOpt.mibBatchTooltip.AnisotropicMethod = 'For 3D erosion on anisotropic voxels with a large radius: keep the accurate ellipsoid (slow) or use the fast distance-transform approximation (bwdist, treats the element as a sphere)';
BatchOpt.mibBatchTooltip.showWaitbar  = 'Show or not the progress dialog during execution';

%% Batch mode check
batchModeSwitch = 0;
if isstruct(BatchOptIn) == 0
    if isscalar(BatchOptIn) && isnan(BatchOptIn)
        BatchOpt = rmfield(BatchOpt, 'id');
        eventdata = core.ToggleEventData(BatchOpt);
        notify(obj, 'SyncBatch', eventdata);
    else
        ErrorDlgOpt.winTitle       = 'BatchOpt Error';
        ErrorDlgOpt.optionalPrefix = 'Error in MibModel.erodeImage';
        ErrorDlgOpt.err            = 'A structure as the 1st parameter is required!';
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
    do3Dbackup = strcmp(BatchOpt.ErodeMode{1}, '3D') || ...
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
cancelledAt = [];   % time point at which Cancel was pressed

%% Parse StrelSize
se_size = utils.parseStrelSize(BatchOpt.StrelSize, strcmp(BatchOpt.ErodeMode{1}, '3D'), ...
    obj.I{BatchOpt.id}.image.pixSize.x, obj.I{BatchOpt.id}.image.pixSize.z);

%% Engine selection: raw strel (imerode) vs distance transform (bwdist)
% For radii above the threshold a raw non-decomposed element makes imerode
% brute-force cost explode (~R^2 in 2D, ~R^3 in 3D). The bwdist path is O(N)
% regardless of R but isotropic, so it is only used for a spherical/circular
% element (equal XY and Z / X and Y radii). See utils.morphBallOp.
bwdistRadiusThreshold = 5;   % matches the large-brush switch in segmentationBrush
radius = max(se_size);
isIsotropicElement = (se_size(1) == se_size(2));

%% Material index (only relevant for 'labels' layer)
if strcmp(BatchOpt.TargetLayer{1}, 'labels')
    materialIndex = str2double(BatchOpt.MaterialIndex);
else
    materialIndex = [];
end

%% ================================================================
%  3D strel erosion
%% ================================================================
if strcmp(BatchOpt.ErodeMode{1}, '3D')

    % Decide engine: bwdist fast path for large isotropic elements; for large
    % anisotropic elements BatchOpt.AnisotropicMethod decides (set by the
    % Selection panel dialog, or by the caller in batch mode).
    useBwdist = false;
    if radius > bwdistRadiusThreshold
        if isIsotropicElement
            useBwdist = true;
        else
            useBwdist = contains(lower(BatchOpt.AnisotropicMethod{1}), 'fast');
        end
    end

    % The bwdist fast path applies an isotropic sphere of radius se_size(1), so
    % its Z extent equals XY; only the accurate ellipsoid uses se_size(2).
    if useBwdist; zStrelPx = se_size(1)*2+1; else; zStrelPx = se_size(2)*2+1; end
    if BatchOpt.showWaitbar
        wb = uiprogressdlg(obj.getProgressBarParent(), 'Value', 0, ...
            'Message', sprintf('Eroding %s...\nStrel: XY=%d px  Z=%d px', ...
                BatchOpt.TargetLayer{1}, se_size(1)*2+1, zStrelPx), ...
            'Title', 'Eroding (3D)...', 'Cancelable', 'on');
    end

    % Build ball-shaped 3D structuring element (only needed for the imerode path)
    if useBwdist
        se = [];
    else
        se = zeros(se_size(1)*2+1, se_size(1)*2+1, se_size(2)*2+1);
        [x, y, z] = meshgrid(-se_size(1):se_size(1), ...
                              -se_size(1):se_size(1), ...
                              -se_size(2):se_size(2));
        ball = sqrt((x / max(se_size(1),1)).^2 + ...
                    (y / max(se_size(1),1)).^2 + ...
                    (z / max(se_size(2),1)).^2);
        se(ball <= 1) = 1;
    end

    tMax = t2 - t1 + 1;
    for idx = 1:tMax
        t = t1 + idx - 1;
        if BatchOpt.showWaitbar
            if wb.CancelRequested; cancelledAt = t; break; end
            wb.Value = (idx-1) / tMax;
        end

        % Always use XY orientation (3) for volumetric strel
        original  = cell2mat(obj.getData3D(BatchOpt.TargetLayer{1}, t, 3, materialIndex, getDataOptions));
        eroded    = utils.morphBallOp(original, 'erode', se, useBwdist, se_size(1));
        if BatchOpt.Difference
            eroded = imabsdiff(eroded, original);
        end
        % the volume is one operation: a Cancel pressed meanwhile discards it
        if BatchOpt.showWaitbar && wb.CancelRequested; cancelledAt = t; break; end
        obj.I{BatchOpt.id}.setData3D(eroded, BatchOpt.TargetLayer{1}, t, 3, materialIndex, getDataOptions);
    end

    if BatchOpt.showWaitbar; delete(wb); end

%% ================================================================
%  2D strel erosion (slice-by-slice)
%% ================================================================
else

    % Auto-enable parallel if a pool is already running (non-batch)
    if ~batchModeSwitch
        if ~isempty(gcp('nocreate')); BatchOpt.Use2DParallelComputing = true; end
    end

    if BatchOpt.Use2DParallelComputing
        parforArg = obj.preferences.System.cpuParallelLimit;
        if isempty(gcp('nocreate')); parpool(parforArg); end
    else
        parforArg = 0;
    end

    % In-plane isotropic elements above the threshold use the bwdist fast path;
    % anisotropic (elliptical) 2D elements fall back to imerode with a prebuilt
    % disk-like strel (no warning - 2D in-plane anisotropy is rare).
    useBwdist = (radius > bwdistRadiusThreshold) && isIsotropicElement;
    if useBwdist
        se = [];
    else
        % Disk-like 2D strel via distance transform
        se = zeros([se_size(1)*2+1, se_size(2)*2+1], 'uint8');
        se(se_size(1)+1, se_size(2)+1) = 1;
        se = bwdist(se);
        se = uint8(se <= max(se_size));
    end

    if strcmp(BatchOpt.DatasetType{1}, '2D, Slice')
        % ---- Single slice ----------------------------------------
        original  = cell2mat(obj.getData2D(BatchOpt.TargetLayer{1}, [], [], materialIndex, getDataOptions));
        eroded    = utils.morphBallOp(original, 'erode', se, useBwdist, se_size(1));
        if BatchOpt.Difference
            eroded = imabsdiff(eroded, original);
        end
        obj.I{BatchOpt.id}.setData2D(eroded, BatchOpt.TargetLayer{1}, [], [], materialIndex, getDataOptions);

    else
        % ---- Stack / dataset: loop through slices ----------------
        orient   = obj.I{BatchOpt.id}.orientation;
        max_size = obj.I{BatchOpt.id}.dim_yxzct(orient);
        max_size2 = max_size * (t2 - t1 + 1);
        take_difference = BatchOpt.Difference;
        showWaitbar     = BatchOpt.showWaitbar;

        % Sequential and parallel alike, the slices of a time point are
        % eroded into a local stack in batches (parfor with parforArg = 0
        % runs on the client) and the stack is written once the time point is
        % complete. Cancel is polled between batches - pool workers cannot
        % see the dialog - so a cancelled time point stays unchanged. A batch
        % is one slice sequentially, 4 per worker in parallel.
        if parforArg > 0; batchSize = 4 * parforArg; else; batchSize = 1; end

        % pwb must exist even without a waitbar: it is a parfor broadcast
        % variable, and on a running pool parfor refuses an undefined one
        pwb = [];
        if showWaitbar
            pwb = core.PoolWaitbar(max_size2, ...
                sprintf('Eroding %s...\nStrel: %dx%d px', ...
                    BatchOpt.TargetLayer{1}, se_size(1), se_size(2)), ...
                obj.getProgressBarParent(), 'Eroding (2D)...', true);
            pwb.setIncrement(10);
        end

        for t = t1:t2
            getDataOptions.t = [t, t];
            stack = cell2mat(obj.getData3D(BatchOpt.TargetLayer{1}, t, orient, materialIndex, getDataOptions));

            for batchStart = 1:batchSize:max_size
                if showWaitbar
                    drawnow limitrate;   % deliver the progress updates and the Cancel click
                    if pwb.getCancelState(); cancelledAt = t; break; end
                end
                batchEnd = min(batchStart + batchSize - 1, max_size);
                parfor (layer_id = batchStart:batchEnd, parforArg)
                    if showWaitbar && mod(layer_id, 10) == 0; pwb.increment(); end %#ok<PFBNS>
                    slice = stack(:, :, layer_id);
                    if max(slice(:)) < 1; continue; end
                    eroded = utils.morphBallOp(slice, 'erode', se, useBwdist, se_size(1)); %#ok<PFBNS>
                    if take_difference
                        eroded = imabsdiff(eroded, slice);
                    end
                    stack(:, :, layer_id) = eroded;
                end
            end
            if ~isempty(cancelledAt); break; end

            obj.I{BatchOpt.id}.setData3D(stack, BatchOpt.TargetLayer{1}, t, orient, materialIndex, getDataOptions);
        end

        if showWaitbar; pwb.deletePoolWaitbar(); end
    end
end

%% Cancelled: the time point in progress was discarded
if ~isempty(cancelledAt)
    if cancelledAt > t1
        % earlier time points of a 4D dataset were already written
        ErrorDlgOpt.winTitle       = 'Erosion cancelled';
        ErrorDlgOpt.optionalPrefix = '';
        ErrorDlgOpt.err            = sprintf(['Erosion was cancelled: time points %d-%d were eroded, ' ...
            'time points %d-%d are unchanged.'], t1, cancelledAt - 1, cancelledAt, t2);
        notify(obj, 'ShowErrorDialog', core.ToggleEventData(ErrorDlgOpt));
        notify(obj, 'ShowImage');
    end
    if batchModeSwitch; notify(obj, 'StopProtocol'); end
    return;
end

if ~strcmp(BatchOpt.DatasetType{1}, '2D, Slice'); toc; end

%% Notify batch system and redraw
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);
notify(obj, 'ShowImage');
end
