function replaceMaskedArea(obj, target, BatchOptIn)
% REPLACEMASKEDAREA - Replace image intensities in the Masked or Selected area.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.replaceMaskedArea()
%       obj.replaceMaskedArea(target)
%       obj.replaceMaskedArea(target, BatchOptIn)
%       obj.replaceMaskedArea(NaN)
%
% In GUI mode (no ``BatchOptIn``) shows a dialog to collect parameters.
% In batch mode accepts a ``BatchOptIn`` structure.  Pass ``NaN`` to return
% default options via the ``SyncBatch`` event.
%
% Input Arguments:
%   - **target** — *(optional)* char, pre-sets ``BatchOpt.Target{1}``;
%     pass ``[]`` or omit to use the BatchOptIn value or the default ``'mask'``.
%     One of: ``'mask'``, ``'selection'``.
%     Pass ``NaN`` to return default options via the ``SyncBatch`` event.
%   - **BatchOptIn** — *(optional)* structure for batch processing mode
%
%     - ``.Target`` — cell string, layer containing the mask:
%       ``{'mask'}`` *(default)* or ``{'selection'}``
%     - ``.ColorChannel`` — cell string, channel(s) to replace:
%       ``{'All'}`` *(default)* or ``{'Ch N'}`` for a specific channel
%     - ``.ColorIntensity`` — 3-cell numeric ``{value, [0 maxInt], 'on'}``;
%       intensity written into every masked pixel (default ``{0, [0 Inf], 'on'}``)
%     - ``.showWaitbar`` — logical, show the progress dialog (default ``true``)
%     - ``.id`` — *(optional)* dataset index 1–9, default = ``obj.getActiveId()``
%     - ``.t`` — *(optional)* ``[t1 t2]`` time range; ``0`` = all time points
%     - ``.z`` — *(optional)* ``[z1 z2]`` z-slice range; ``0`` = all slices
%
% Output Arguments:
%   (none)
%
% Usage:
%   **Example 1** — interactive dialog for mask layer
%
%   .. code-block:: matlab
%
%      obj.mibModel.replaceMaskedArea('mask');
%
%   **Example 2** — interactive dialog for selection layer
%
%   .. code-block:: matlab
%
%      obj.mibModel.replaceMaskedArea('selection');
%
%   **Example 3** — batch mode: set selection area on channel 1 to 128
%
%   .. code-block:: matlab
%
%      BatchOpt.Target         = {'selection'};
%      BatchOpt.ColorChannel   = {'Ch 1'};
%      BatchOpt.ColorIntensity = {128, [0 255], 'on'};
%      obj.mibModel.replaceMaskedArea('selection', BatchOpt);
%
%   **Example 4** — return default BatchOpt to the Batch Processing editor
%
%   .. code-block:: matlab
%
%      obj.mibModel.replaceMaskedArea(NaN);
%

% Updates
% 2025 — ported from MIB2 mibController.menuMaskImageReplace_Callback

if nargin < 2; target = []; end
if nargin < 3; BatchOptIn = struct(); end

% Handle replaceMaskedArea(NaN) — NaN as target means SyncBatch probe
if ~ischar(target) && ~isempty(target) && isscalar(target) && isnan(target)
    BatchOptIn = NaN;
    target = [];
end

%% Default BatchOpt
id = obj.getActiveId();
maxInt    = obj.I{id}.image.maxInt;
colorCount = obj.I{id}.image.colors;
colorChannelList = arrayfun(@(x) sprintf('Ch %d', x), 1:colorCount, 'UniformOutput', false);

BatchOpt = struct();
BatchOpt.Target          = {'mask'};
BatchOpt.Target{2}       = {'mask', 'selection'};
BatchOpt.ColorChannel    = {'All'};
BatchOpt.ColorChannel{2} = [{'All'}, colorChannelList];
BatchOpt.ColorIntensity  = {0, [0, maxInt], 'on'};
BatchOpt.showWaitbar = true;
BatchOpt.id          = id;

if strcmp(BatchOpt.Target, 'mask')
    BatchOpt.mibBatchSectionName = 'Ribbon -> Mask';
else
    BatchOpt.mibBatchSectionName = 'Ribbon -> Selection';
end
BatchOpt.mibBatchActionName  = 'Replace masked area in the image';

BatchOpt.mibBatchTooltip.Target         = 'Layer containing the areas to replace: mask or selection';
BatchOpt.mibBatchTooltip.ColorChannel   = 'Color channel(s) to replace; All = every channel';
BatchOpt.mibBatchTooltip.ColorIntensity = 'New intensity value written into masked pixels (0 = black, maxInt = white)';
BatchOpt.mibBatchTooltip.showWaitbar    = 'Show or not the progress dialog during execution';

%% Apply target shortcut
if ~isempty(target) && ischar(target)
    BatchOpt.Target{1} = target;
end

%% Batch dispatch
batchModeSwitch = 0;
if isstruct(BatchOptIn) == 0
    if isnan(BatchOptIn)
        BatchOpt = rmfield(BatchOpt, 'id');
        notify(obj, 'SyncBatch', core.ToggleEventData(BatchOpt));
    else
        ErrorDlgOpt.winTitle       = 'Error in MibModel.replaceMaskedArea';
        ErrorDlgOpt.optionalPrefix = 'Wrong input parameter!';
        ErrorDlgOpt.err            = 'A structure as the 2nd parameter is required!';
        ErrorDlgOpt.WindowHeight   = 150;
        notify(obj, 'ShowErrorDialog', core.ToggleEventData(ErrorDlgOpt));
    end
    return;
else
    BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    if isfield(BatchOptIn, 'mibBatchTooltip'); batchModeSwitch = 1; end
end

%% Guards
if strcmp(obj.I{BatchOpt.id}.datasetType, 'Virtual')
    dlgOpt.MsgBoxOnly   = true;
    dlgOpt.Icon         = 'puffin_warning';
    dlgOpt.WindowHeight = 170;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), '', {''}, ...
        {'Replace masked area is not available in virtual stacking mode. Please switch to the memory-resident mode and try again.'}, ...
        'Not implemented', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

if strcmp(obj.I{BatchOpt.id}.image.colorType, 'indexed')
    utils.dlgs.showErrorDialog(obj.getProgressBarParent(), ...
        'Replace masked area is not compatible with indexed images!', ...
        'Wrong image type');
    notify(obj, 'StopProtocol');
    return;
end

%% Resolve dataset dimensions
[~, ~, depthCount] = obj.I{BatchOpt.id}.getDatasetDimensions('image', 3);
maxTime    = obj.I{BatchOpt.id}.image.time;
currentSlice = obj.I{BatchOpt.id}.getCurrentSliceNumber();
currentTime  = obj.I{BatchOpt.id}.getCurrentTimePoint();

%% GUI dialog (interactive mode only)
if ~batchModeSwitch
    dlgTitle = sprintf('Replace %s area in the image', BatchOpt.Target{1});

    prompts = { ...
        sprintf('New color intensity [0 - %d]:', maxInt); ...
        sprintf('Color channel (0 = all channels, 1-%d = specific):', colorCount); ...
        sprintf('Time point (0 = all, 1-%d; current = %d):', maxTime, currentTime); ...
        sprintf('Slice number (0 = all, 1-%d; current = %d):', depthCount, currentSlice)};

    defAns = { ...
        struct('Spinner', true, 'Value', BatchOpt.ColorIntensity{1}, 'Limits', [0, maxInt], 'Step', 1, 'Round', true); ...
        struct('Spinner', true, 'Value', 0, 'Limits', [0, colorCount], 'Step', 1, 'Round', true); ...
        struct('Spinner', true, 'Value', currentTime, 'Limits', [0, maxTime], 'Step', 1, 'Round', true); ...
        struct('Spinner', true, 'Value', currentSlice, 'Limits', [0, depthCount], 'Step', 1, 'Round', true)};

    dlgOpt.Icon        = 'puffin_question';
    dlgOpt.WindowHeight = 280;
    dlgOpt.Focus = 1;
    %dlgOpt.LabelPosition = 'left';
    answer = utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), ...
        sprintf('You are replacing the *%s* layer in the image.', BatchOpt.Target{1}), ...
        prompts, defAns, dlgTitle, dlgOpt);
    if isempty(answer); return; end

    BatchOpt.ColorIntensity{1} = answer{1};

    channelAnswer = answer{2};
    if channelAnswer == 0
        BatchOpt.ColorChannel{1} = 'All';
    else
        BatchOpt.ColorChannel{1} = sprintf('Ch %d', channelAnswer);
    end

    timePntAnswer = answer{3};
    if timePntAnswer == 0
        tRange = [1, maxTime];
    else
        tRange = [timePntAnswer, timePntAnswer];
    end

    sliceAnswer = answer{4};
    if sliceAnswer == 0
        zRange = [1, depthCount];
    else
        zRange = [sliceAnswer, sliceAnswer];
    end
else
    %% Resolve z / t ranges for batch mode
    zRange = [1, depthCount];
    tRange = [1, maxTime];
    if isfield(BatchOpt, 'z') && numel(BatchOpt.z) == 2 && BatchOpt.z(1) ~= 0
        zRange = BatchOpt.z;
    end
    if isfield(BatchOpt, 't') && numel(BatchOpt.t) == 2 && BatchOpt.t(1) ~= 0
        tRange = BatchOpt.t;
    end
end

%% Resolve channel indices
if strcmp(BatchOpt.ColorChannel{1}, 'All')
    colorChannels = 1:obj.I{BatchOpt.id}.image.colors;
else
    colorChannels = sscanf(BatchOpt.ColorChannel{1}, 'Ch %d');
end

%% Backup
getDataOptions.id = BatchOpt.id;
if ~batchModeSwitch
    if diff(zRange) == 0 && diff(tRange) == 0
        obj.backup('image', 0, getDataOptions);
    else
        obj.backup('image', 1, getDataOptions);
    end
end

%% Progress dialog
colorValues  = BatchOpt.ColorIntensity{1};
nTimePoints  = diff(tRange) + 1;

if BatchOpt.showWaitbar
    wb = uiprogressdlg(obj.getProgressBarParent(), ...
        'Title',      'Replace masked area', ...
        'Message',    sprintf('Replacing %s area\nPlease wait...', BatchOpt.Target{1}), ...
        'Value',      0, ...
        'Cancelable', 'on');
end

%% Main loop (one getData3D call per time point)
imOptions.zRange = zRange;

for timePoint = tRange(1):tRange(2)
    getDataOptions.t = [timePoint, timePoint];

    maskVolume3D = cell2mat(obj.getData3D(BatchOpt.Target{1}, timePoint, 3, NaN, getDataOptions));
    maskVolumeZ  = maskVolume3D(:,:,zRange(1):zRange(2));

    if any(maskVolumeZ(:))
        imOptions.timePoint = timePoint;
        obj.I{BatchOpt.id}.image.replaceMaskedArea(maskVolumeZ, colorValues, colorChannels, imOptions);
    end

    if BatchOpt.showWaitbar
        wb.Value = (timePoint - tRange(1) + 1) / nTimePoints;
        if wb.CancelRequested
            delete(wb);
            notify(obj, 'ShowImage');
            return;
        end
    end
end

if BatchOpt.showWaitbar; delete(wb); end

%% Log and notify
logText = sprintf('Replace %s area: ch [%s] → %g', BatchOpt.Target{1}, num2str(colorChannels), colorValues);
obj.I{BatchOpt.id}.image.updateActionLog(logText);

BatchOpt = rmfield(BatchOpt, 'id');
notify(obj, 'SyncBatch', core.ToggleEventData(BatchOpt));
notify(obj, 'ShowImage');

end
