function smoothImage(obj, type, BatchOptIn)
% SMOOTHIMAGE - Smooth 'Mask', 'Selection', or 'Labels' layer with a Gaussian kernel.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.smoothImage(type)
%       obj.smoothImage(type, BatchOptIn)
%
% Applies a Gaussian blur to the binary content of a selection, mask, or labels
% layer.  The blurred result is stored back (MATLAB's ``imfilter`` clips to the
% uint8 range, so edge pixels below the threshold become 0, effectively
% rounding the corners of the selection).  Supports 2D (slice-by-slice) and
% 3D (separable Gaussian) modes, and can operate on a single material or a
% range of materials of the labels layer.
%
% Input Arguments:
%   - **type** — char, layer to smooth: ``'selection'``, ``'mask'``, or ``'labels'``;
%     pass ``''`` to default to ``'selection'``
%   - **BatchOptIn** — *(optional)* structure for batch processing mode; when NaN,
%     returns default options via the ``SyncBatch`` event
%
%     - ``.Target`` — cell string, ``{'selection','mask','labels'}``
%     - ``.SmoothingMode`` — cell string, ``{'2D','3D'}``
%     - ``.KernelSizeX`` — numeric ``{val, [min max], 'on'}``, X kernel size in pixels
%     - ``.KernelSizeY`` — numeric ``{val, [min max], 'on'}``, Y kernel size in pixels;
%       ``0`` = auto (square, same size as X)
%     - ``.KernelSizeZ`` — numeric ``{val, [min max], 'on'}``, Z kernel size in pixels (3D only)
%     - ``.Sigma`` — numeric ``{val, [min max], 'off'}``, Gaussian sigma
%     - ``.MaterialIndex`` — string, index or range of labels materials, e.g. ``'1'`` or ``'1,3'`` or ``'2:4'``
%     - ``.showWaitbar`` — logical, show or not the progress dialog
%     - ``.id`` — *(optional)* dataset index 1–9, default = ``obj.getActiveId()``
%
% Output Arguments:
%   (none)
%
% Usage:
%   **Example 1** — smooth selection on the current dataset with interactive dialog
%
%   .. code-block:: matlab
%
%      obj.mibModel.smoothImage('selection');
%
%   **Example 2** — 3D Gaussian smoothing of the mask layer, sigma=2, 7-pixel kernel
%
%   .. code-block:: matlab
%
%      BatchOpt.Target        = {'mask'};
%      BatchOpt.SmoothingMode = {'3D'};
%      BatchOpt.KernelSizeX   = {7, [1 100], 'on'};
%      BatchOpt.KernelSizeZ   = {7, [1 100], 'on'};
%      BatchOpt.Sigma         = {2, [0.01 100], 'off'};
%      BatchOpt.showWaitbar   = true;
%      obj.mibModel.smoothImage('mask', BatchOpt);
%
%   **Example 3** — smooth material 2 of the labels layer
%
%   .. code-block:: matlab
%
%      BatchOpt.Target        = {'labels'};
%      BatchOpt.MaterialIndex = '2';
%      obj.mibModel.smoothImage('labels', BatchOpt);
%
%   **Example 4** — return default BatchOpt to the Batch Processing editor
%
%   .. code-block:: matlab
%
%      obj.mibModel.smoothImage('', NaN);
%

% Updates
% 01.06.2026 - ported from MIB2 mibModel.smoothImage; converted string BatchOpt
%              fields to numeric spinners; replaced waitbar with uiprogressdlg;
%              replaced mibDoImageFiltering with inline separable Gaussian;
%              layer 'model' -> 'labels'; orient NaN -> []; obj.Id -> obj.getActiveId();
%              mibBatchSectionName 'Menu ->' -> 'Ribbon ->'

if nargin < 3; BatchOptIn = struct(); end
showDialog = isstruct(BatchOptIn) && ~isfield(BatchOptIn, 'Target');

%% Default BatchOpt
BatchOpt = struct();
if ~isempty(type)
    BatchOpt.Target = {type};
else
    BatchOpt.Target = {'selection'};
end
BatchOpt.Target{2} = {'mask', 'selection', 'labels'};
BatchOpt.SmoothingMode = {'2D'};
BatchOpt.SmoothingMode{2} = {'2D', '3D'};
BatchOpt.KernelSizeX = {5, [1 100], 'on'};
BatchOpt.KernelSizeY = {0, [0 100], 'on'};   % 0 = auto (square, same as X)
BatchOpt.KernelSizeZ = {5, [1 100], 'on'};
BatchOpt.Sigma = {3, [0.01 100], 'off'};
BatchOpt.MaterialIndex = '1';
BatchOpt.showWaitbar = true;
BatchOpt.id = obj.getActiveId();

switch BatchOpt.Target{1}
    case 'mask'
        BatchOpt.mibBatchSectionName = 'Ribbon -> Mask';
        BatchOpt.mibBatchActionName  = 'Smooth mask';
    case 'selection'
        BatchOpt.mibBatchSectionName = 'Ribbon -> Selection';
        BatchOpt.mibBatchActionName  = 'Smooth selection';
    case 'labels'
        BatchOpt.mibBatchSectionName = 'Ribbon -> Model';
        BatchOpt.mibBatchActionName  = 'Smooth labels';
end

BatchOpt.mibBatchTooltip.Target        = 'Layer to be smoothed';
BatchOpt.mibBatchTooltip.SmoothingMode = 'Use 2D (slice-by-slice) or 3D (volumetric separable) Gaussian smoothing';
BatchOpt.mibBatchTooltip.KernelSizeX   = 'X kernel size in pixels';
BatchOpt.mibBatchTooltip.KernelSizeY   = 'Y kernel size in pixels; 0 = auto (square, same as X)';
BatchOpt.mibBatchTooltip.KernelSizeZ   = '[3D mode only] Z kernel size in pixels';
BatchOpt.mibBatchTooltip.Sigma         = 'Gaussian sigma (standard deviation)';
BatchOpt.mibBatchTooltip.MaterialIndex = 'Index or range of labels materials to smooth, e.g. "1" or "1,3" or "2:4"';
BatchOpt.mibBatchTooltip.showWaitbar   = 'Show or not the progress dialog during execution';

%% Batch mode check
batchModeSwitch = 0;
if isstruct(BatchOptIn) == 0
    if isscalar(BatchOptIn) && isnan(BatchOptIn)
        BatchOpt = rmfield(BatchOpt, 'id');
        eventdata = core.ToggleEventData(BatchOpt);
        notify(obj, 'SyncBatch', eventdata);
    else
        ErrorDlgOpt.winTitle       = 'BatchOpt Error';
        ErrorDlgOpt.optionalPrefix = 'A structure as the 2nd parameter is required!';
        ErrorDlgOpt.err            = 'A structure as the 2nd parameter is required!';
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

%% Guard: virtual stacking mode not supported
if strcmp(obj.I{BatchOpt.id}.datasetType, 'Virtual')
    dlgOpt.MsgBoxOnly  = true;
    dlgOpt.Icon        = 'puffin_warning';
    dlgOpt.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), ...
        '!!! Warning !!!', ...
        {''}, {'Smoothing is not yet available in the virtual stacking mode. Please switch to the memory-resident mode and try again.'}, ...
        'Not Implemented', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

%% Interactive dialog
if showDialog && ~batchModeSwitch
    matIndex = obj.I{BatchOpt.id}.getSelectedMaterialIndex();
    note = sprintf(['Note!\nYou can also smooth selection and mask with an interactive preview.\n' ...
        'Use: Ribbon -> Image -> Image filters -> Basic Image Filtering -> Gaussian']);

    dlgOpt.WindowHeight = 380;
    dlgOpt.HeaderLines = 2;
    modeChoices = [BatchOpt.SmoothingMode{2}, find(strcmp(BatchOpt.SmoothingMode{2}, BatchOpt.SmoothingMode{1}))];
    defAns = {modeChoices, ...
              struct('Spinner', true, 'Value', BatchOpt.KernelSizeX{1}, 'Limits', BatchOpt.KernelSizeX{2}, 'Step', 1, 'Round', true), ...
              struct('Spinner', true, 'Value', BatchOpt.KernelSizeY{1}, 'Limits', BatchOpt.KernelSizeY{2}, 'Step', 1, 'Round', true), ...
              struct('Spinner', true, 'Value', BatchOpt.KernelSizeZ{1}, 'Limits', BatchOpt.KernelSizeZ{2}, 'Step', 1, 'Round', true), ...
              struct('Spinner', true, 'Value', BatchOpt.Sigma{1},       'Limits', BatchOpt.Sigma{2},       'Step', 0.1, 'Round', false), ...
              num2str(matIndex)};
    prompt = {'Mode:', ...
              'X kernel size (pixels):', ...
              'Y kernel size (pixels; 0 = square):', ...
              'Z kernel size (pixels; 3D only):', ...
              'Sigma:', ...
              '[Labels only] Material index(es):'};

    answer = utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), note, prompt, defAns, ...
        sprintf('Smooth %s', BatchOpt.Target{1}), dlgOpt);
    if isempty(answer); return; end

    BatchOpt.SmoothingMode{1} = answer{1};
    BatchOpt.KernelSizeX{1}   = answer{2};
    BatchOpt.KernelSizeY{1}   = answer{3};
    BatchOpt.KernelSizeZ{1}   = answer{4};
    BatchOpt.Sigma{1}         = answer{5};
    BatchOpt.MaterialIndex    = answer{6};
end

%% Resolve kernel sizes
kernelX = BatchOpt.KernelSizeX{1};
kernelY = BatchOpt.KernelSizeY{1};
if kernelY == 0; kernelY = kernelX; end
kernelZ = BatchOpt.KernelSizeZ{1};
sigma   = BatchOpt.Sigma{1};

%% Build Gaussian filter(s)
is3D = strcmp(BatchOpt.SmoothingMode{1}, '3D');
if is3D
    gaussXY = fspecial('gaussian', [kernelX 1], sigma);
    gaussZ  = fspecial('gaussian', [kernelZ 1], sigma);
    Hx = reshape(gaussXY, [length(gaussXY) 1 1 1]);
    Hy = reshape(gaussXY, [1 length(gaussXY) 1 1]);
    Hz = reshape(gaussZ,  [1 1 1 length(gaussZ)]);
else
    filter2d = fspecial('gaussian', [kernelX kernelY], sigma);
end

%% Time range and backup
getDataOptions.id = BatchOpt.id;
t1 = 1;
t2 = obj.I{BatchOpt.id}.image.time;

if ~batchModeSwitch
    obj.backup(BatchOpt.Target{1}, 1, getDataOptions);
end

%% Waitbar
if BatchOpt.showWaitbar
    wb = uiprogressdlg(obj.getProgressBarParent(), 'Value', 0, ...
        'Message', sprintf('Smoothing the %s layer\nPlease wait...', BatchOpt.Target{1}), ...
        'Title', 'Smoothing');
end

%% Apply Gaussian smoothing
switch BatchOpt.Target{1}
    case {'mask', 'selection'}
        for t = t1:t2
            layerData = cell2mat(obj.getData3D(BatchOpt.Target{1}, t, [], [], getDataOptions));
            if is3D
                layerData = reshape(layerData, [size(layerData,1), size(layerData,2), 1, size(layerData,3)]);
                layerData = imfilter(imfilter(imfilter(layerData, Hx, 'replicate'), Hy, 'replicate'), Hz, 'replicate');
                layerData = squeeze(layerData);
            else
                for z = 1:size(layerData, 3)
                    layerData(:,:,z) = imfilter(layerData(:,:,z), filter2d, 'replicate');
                end
            end
            obj.setData3D(layerData, BatchOpt.Target{1}, t, [], [], getDataOptions);
            if BatchOpt.showWaitbar; wb.Value = t / t2; end
        end

    case 'labels'
        materialIndices = str2num(BatchOpt.MaterialIndex); %#ok<ST2NM>
        if isempty(materialIndices) || min(materialIndices) < 1
            if BatchOpt.showWaitbar; delete(wb); end
            return;
        end
        maxIterations = numel(materialIndices) * (t2 - t1 + 1);
        iteration = 0;
        for t = t1:t2
            for materialIdx = materialIndices
                labelData = cell2mat(obj.getData3D('labels', t, [], materialIdx, getDataOptions));
                if is3D
                    labelData = reshape(labelData, [size(labelData,1), size(labelData,2), 1, size(labelData,3)]);
                    labelData = imfilter(imfilter(imfilter(labelData, Hx, 'replicate'), Hy, 'replicate'), Hz, 'replicate');
                    labelData = squeeze(labelData);
                else
                    for z = 1:size(labelData, 3)
                        labelData(:,:,z) = imfilter(labelData(:,:,z), filter2d, 'replicate');
                    end
                end
                obj.setData3D(labelData, 'labels', t, [], materialIdx, getDataOptions);
                iteration = iteration + 1;
                if BatchOpt.showWaitbar; wb.Value = iteration / maxIterations; end
            end
        end
end

if BatchOpt.showWaitbar; delete(wb); end

%% Notify batch system and redraw
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);
notify(obj, 'ShowImage');
end
