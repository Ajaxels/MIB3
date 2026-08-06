function colorChannelActions(obj, mode, channel1, BatchOptIn)
% COLORCHANNELACTIONS - Handle various color channel operations.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.colorChannelActions()
%       obj.colorChannelActions(mode)
%       obj.colorChannelActions(mode, channel1)
%       obj.colorChannelActions(mode, channel1, BatchOptIn)
%
% Batch-compatible dispatcher.  When called with only ``mode``, shows an
% interactive dialog pre-set to that action.  When called with no
% arguments, shows the full action-selection dialog.
%
% Input Arguments:
%   - **mode** - *(optional)* char, pre-selects the action; pass ``[]`` or
%     omit to start with the action-selection step.  One of:
%     ``'Insert empty channel'``, ``'Copy channel'``, ``'Invert channel'``,
%     ``'Rotate channel'``, ``'Shift channel'``, ``'Swap channels'``,
%     ``'Delete channel'``.  Pass ``NaN`` to return default options via the
%     ``SyncBatch`` event.
%   - **channel1** - *(optional)* numeric scalar, pre-sets
%     ``BatchOpt.Channel1{1}`` (the primary / source channel index).
%     Pass ``[]`` to use the currently selected channel.
%   - **BatchOptIn** - *(optional)* struct for batch processing mode
%
%     - ``.Action`` - [cell] action to perform
%       (default: ``{'Insert empty channel'}``).
%       Allowed values: ``{'Insert empty channel', 'Copy channel',
%       'Invert channel', 'Rotate channel', 'Shift channel',
%       'Swap channels', 'Delete channel'}``
%     - ``.Channel1`` - [numeric cell] ``{value, [minLim maxLim], 'on'}``
%       source / primary channel index
%       (default: currently selected channel)
%     - ``.Channel2`` - [numeric cell] ``{value, [minLim maxLim], 'on'}``
%       target / secondary channel index; used by Copy and Swap.
%       For Copy: ``0`` appends source as a new channel at the end.
%       (default: currently selected channel)
%     - ``.RotationAngle`` - [cell] rotation angle for Rotate action
%       (default: ``{'90'}``). Allowed: ``{'90', '180', '-90'}``
%     - ``.dx`` - [numeric cell] ``{value, [minLim maxLim], 'on'}``
%       X-shift in pixels for Shift action
%       (default: ``{0, [-maxDim maxDim], 'on'}``)
%     - ``.dy`` - [numeric cell] ``{value, [minLim maxLim], 'on'}``
%       Y-shift in pixels for Shift action
%       (default: ``{0, [-maxDim maxDim], 'on'}``)
%     - ``.FillValue`` - [numeric cell] ``{value, [minLim maxLim], 'on'}``
%       Fill intensity for Shift action border
%       (default: ``{0, [0 maxInt], 'on'}``)
%     - ``.showWaitbar`` - [logical] show the progress dialog
%       (default: ``true``)
%     - ``.id`` - *(optional)* dataset index 1-9,
%       default = ``obj.getActiveId()``
%
% Usage:
%   **Example 1** - open Insert empty channel dialog
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.colorChannelActions('Insert empty channel');
%
%   **Example 2** - batch: delete color channel 2
%
%   .. code-block:: matlab
%
%
%     BatchOpt.Action   = {'Delete channel'};
%     BatchOpt.Channel1 = {2, [1 9], 'on'};
%     obj.mibModel.colorChannelActions('Delete channel', [], BatchOpt);
%
%   **Example 3** - batch: shift channel 1 by dx=10, dy=-5
%
%   .. code-block:: matlab
%
%
%     BatchOpt.Action    = {'Shift channel'};
%     BatchOpt.dx        = {10,  [-512 512], 'on'};
%     BatchOpt.dy        = {-5,  [-512 512], 'on'};
%     BatchOpt.FillValue = {0,   [0 255],    'on'};
%     obj.mibModel.colorChannelActions('Shift channel', 1, BatchOpt);
%

% Updates
%

if nargin < 2; mode     = []; end
if nargin < 3; channel1 = []; end

activeId    = obj.getActiveId();
imageColors = obj.I{activeId}.image.colors;
maxIntValue = double(obj.I{activeId}.image.maxInt);
maxDim      = max(obj.I{activeId}.image.height, obj.I{activeId}.image.width);

selCh = max([1, obj.I{activeId}.selectedColorChannel]);
if selCh > imageColors; selCh = 1; end

%% populate BatchOpt with default values
BatchOpt = struct();
if ~isempty(mode) && ischar(mode)
    BatchOpt.Action = {mode};
else
    BatchOpt.Action = {'Insert empty channel'};
end
BatchOpt.Action{2} = {'Insert empty channel', 'Copy channel', 'Invert channel', ...
                      'Rotate channel', 'Shift channel', 'Swap channels', 'Delete channel'};

BatchOpt.Channel1 = {selCh, [0, imageColors+1], 'on'};
BatchOpt.Channel2 = {selCh, [0, imageColors+1], 'on'};
if ~isempty(channel1); BatchOpt.Channel1{1} = channel1; end

BatchOpt.RotationAngle    = {'90'};
BatchOpt.RotationAngle{2} = {'90', '180', '-90'};

BatchOpt.dx        = {0, [-maxDim, maxDim], 'on'};
BatchOpt.dy        = {0, [-maxDim, maxDim], 'on'};
BatchOpt.FillValue = {0, [0, maxIntValue], 'on'};

BatchOpt.showWaitbar = true;
BatchOpt.id          = activeId;

BatchOpt.mibBatchSectionName = 'Ribbon -> Image';
BatchOpt.mibBatchActionName  = 'Color channel actions';

BatchOpt.mibBatchTooltip.Action        = 'Select the color-channel operation to perform';
BatchOpt.mibBatchTooltip.Channel1      = 'Primary (source) color channel index (1-based); for Insert: 0 or colors+1 = append at end';
BatchOpt.mibBatchTooltip.Channel2      = '[Copy] Target channel index; 0 = append source as new channel at end. [Swap] Target channel index';
BatchOpt.mibBatchTooltip.RotationAngle = '[Rotate] Rotation angle; must be 90, 180, or -90';
BatchOpt.mibBatchTooltip.dx            = '[Shift] X-shift in pixels (positive = right)';
BatchOpt.mibBatchTooltip.dy            = '[Shift] Y-shift in pixels (positive = down)';
BatchOpt.mibBatchTooltip.FillValue     = '[Shift] Intensity value used to fill the vacated border';
BatchOpt.mibBatchTooltip.showWaitbar   = 'Show or not the progress bar during execution';

%% batch mode check
if nargin == 4  % batch mode
    if isstruct(BatchOptIn) == 0
        if isscalar(BatchOptIn) && isnan(BatchOptIn)
            BatchOpt = rmfield(BatchOpt, 'id');
            notify(obj, 'SyncBatch', core.ToggleEventData(BatchOpt));
        else
            ErrorDlgOpt.winTitle       = 'BatchOpt Error';
            ErrorDlgOpt.optionalPrefix = 'Error in MibModel.colorChannelActions';
            ErrorDlgOpt.err            = 'A structure as the 2nd parameter is required!';
            notify(obj, 'ShowErrorDialog', core.ToggleEventData(ErrorDlgOpt));
        end
        return;
    else
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end
elseif nargin <= 3 && ~ischar(mode) && ~isempty(mode) && isscalar(mode) && isnan(mode)
    % colorChannelActions(NaN) - SyncBatch request
    BatchOpt = rmfield(BatchOpt, 'id');
    notify(obj, 'SyncBatch', core.ToggleEventData(BatchOpt));
    return;
end

% %% refresh limits to match the actual dataset after batch-merge
% imageColors = obj.I{BatchOpt.id}.image.colors;
% maxIntValue = double(obj.I{BatchOpt.id}.image.maxInt);
% maxDim      = max(obj.I{BatchOpt.id}.image.height, obj.I{BatchOpt.id}.image.width);
% 
% BatchOpt.dx{2}        = [-maxDim, maxDim];
% BatchOpt.dy{2}        = [-maxDim, maxDim];
% BatchOpt.FillValue{2} = [0, maxIntValue];
% BatchOpt.Channel1{2}  = [1, imageColors];
% BatchOpt.Channel2{2}  = [0, imageColors];
% BatchOpt.Channel1{1}  = max(1, min(BatchOpt.Channel1{1}, imageColors));
% BatchOpt.Channel2{1}  = max(0, min(BatchOpt.Channel2{1}, imageColors));

%% interactive dialog (no BatchOptIn provided)
if nargin < 4
    if isempty(mode)
        % Step 1: pick action and primary channel
        dlgOpt.WindowHeight = 200;
        dlgOpt.Focus = 1;
        answer1 = utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), '', ...
            {'Action:', 'Color channel:'}, ...
            {[BatchOpt.Action{2}, find(ismember(BatchOpt.Action{2}, BatchOpt.Action{1}), 1)], ...
             struct('Spinner', true, 'Value', BatchOpt.Channel1{1}, 'Limits', BatchOpt.Channel1{2}, 'Step', 1, 'Round', true)}, ...
            'Color channel action', dlgOpt);
        if isempty(answer1); return; end
        BatchOpt.Action{1}   = answer1{1};
        BatchOpt.Channel1{1} = answer1{2};
    else
        % Action pre-selected by mode - skip to action-specific dialog directly.
        % Channel1 defaults to currently selected channel (already set above).
    end

    % Step 2: action-specific parameters
    switch BatchOpt.Action{1}
        case 'Copy channel'
            answer2 = utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), '', ...
                {'Source color channel:', ...
                 sprintf('Target color channel\n(0 or %d = copy to new channel at end):', imageColors+1)}, ...
                {struct('Spinner', true, 'Value', BatchOpt.Channel1{1}, 'Limits', BatchOpt.Channel1{2}, 'Step', 1, 'Round', true), ...
                 struct('Spinner', true, 'Value', BatchOpt.Channel2{1}, 'Limits', BatchOpt.Channel2{2}, 'Step', 1, 'Round', true)}, ...
                'Copy channel', struct('WindowHeight', 200, 'Focus', 2));
            if isempty(answer2); return; end
            BatchOpt.Channel1{1} = answer2{1};
            BatchOpt.Channel2{1} = answer2{2};

        case 'Swap channels'
            answer2 = utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), '', ...
                {'Source color channel:', 'Target color channel:'}, ...
                {struct('Spinner', true, 'Value', BatchOpt.Channel1{1}, 'Limits', BatchOpt.Channel1{2}, 'Step', 1, 'Round', true), ...
                 struct('Spinner', true, 'Value', BatchOpt.Channel2{1}, 'Limits', BatchOpt.Channel2{2}, 'Step', 1, 'Round', true)}, ...
                'Swap channels', struct('WindowHeight', 200));
            if isempty(answer2); return; end
            BatchOpt.Channel1{1} = answer2{1};
            BatchOpt.Channel2{1} = answer2{2};

        case 'Rotate channel'
            answer2 = utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), '', ...
                {'Color channel:', 'Rotation angle (90, 180, -90):'}, ...
                {struct('Spinner', true, 'Value', BatchOpt.Channel1{1}, 'Limits', BatchOpt.Channel1{2}, 'Step', 1, 'Round', true), ...
                 [BatchOpt.RotationAngle{2}, find(ismember(BatchOpt.RotationAngle{2}, BatchOpt.RotationAngle{1}), 1)]}, ...
                'Rotate channel', struct('WindowHeight', 200, 'Focus', 2));
            if isempty(answer2); return; end
            BatchOpt.Channel1{1}      = answer2{1};
            BatchOpt.RotationAngle{1} = answer2{2};

        case 'Shift channel'
            dlgOpt2.WindowHeight = 300;
            dlgOpt2.Focus = 1;
            answer2 = utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), '', ...
                {'Color channel:', ...
                 'dx shift in pixels:', ...
                 'dy shift in pixels:', ...
                 sprintf('Fill intensity (0\x2013%g):', maxIntValue)}, ...
                {struct('Spinner', true, 'Value', BatchOpt.Channel1{1},  'Limits', BatchOpt.Channel1{2},  'Step', 1, 'Round', true), ...
                 struct('Spinner', true, 'Value', BatchOpt.dx{1},         'Limits', BatchOpt.dx{2},         'Step', 1, 'Round', true), ...
                 struct('Spinner', true, 'Value', BatchOpt.dy{1},         'Limits', BatchOpt.dy{2},         'Step', 1, 'Round', true), ...
                 struct('Spinner', true, 'Value', BatchOpt.FillValue{1},  'Limits', BatchOpt.FillValue{2},  'Step', 1, 'Round', true)}, ...
                'Shift channel', dlgOpt2);
            if isempty(answer2); return; end
            BatchOpt.Channel1{1}  = answer2{1};
            BatchOpt.dx{1}        = answer2{2};
            BatchOpt.dy{1}        = answer2{3};
            BatchOpt.FillValue{1} = answer2{4};

        case 'Insert empty channel'
            % Ask for the position of the new channel (0 or colors+1 = append at end)
            answer2 = utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), '', ...
                {sprintf('Position for the new channel\n(1 = first, 0 or %d = append to end):', imageColors+1)}, ...
                {struct('Spinner', true, 'Value', min(BatchOpt.Channel1{1}, imageColors+1), ...
                        'Limits', [0, imageColors+1], 'Step', 1, 'Round', true)}, ...
                'Insert empty channel', struct('WindowHeight', 180, 'Focus', 1));
            if isempty(answer2); return; end
            BatchOpt.Channel1{1} = answer2{1};

        otherwise
            % Invert channel, Delete channel: only need Channel1 spinner
            answer2 = utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), '', ...
                {'Color channel:'}, ...
                {struct('Spinner', true, 'Value', BatchOpt.Channel1{1}, 'Limits', BatchOpt.Channel1{2}, 'Step', 1, 'Round', true)}, ...
                BatchOpt.Action{1}, struct('WindowHeight', 160, 'Focus', 1));
            if isempty(answer2); return; end
            BatchOpt.Channel1{1} = answer2{1};
    end
end

%% validate rotation angle
if strcmp(BatchOpt.Action{1}, 'Rotate channel')
    rotAngle = str2double(BatchOpt.RotationAngle{1});
    if isnan(rotAngle) || mod(rotAngle, 90) ~= 0
        ErrorDlgOpt.winTitle = 'Wrong rotation angle';
        ErrorDlgOpt.err      = 'The rotation angle must be 90, 180, or -90.';
        notify(obj, 'ShowErrorDialog', core.ToggleEventData(ErrorDlgOpt));
        notify(obj, 'StopProtocol');
        return;
    end
end

%% extract channel indices (directly numeric)
channel1 = BatchOpt.Channel1{1};
if strcmp(BatchOpt.Action{1}, 'Insert empty channel') && channel1 == 0
    channel1 = imageColors + 1;
end
channel2 = BatchOpt.Channel2{1};
if strcmp(BatchOpt.Action{1}, 'Copy channel') && channel2 == 0
    channel2 = imageColors + 1;
end

options.showWaitbar  = BatchOpt.showWaitbar;
options.ParentFigure = obj.mibGUI;
id = BatchOpt.id;

%%
switch BatchOpt.Action{1}
    case 'Insert empty channel'
        obj.I{id}.image.insertEmptyColorChannel(channel1, options);
        obj.I{id}.slices{4} = 1:min([obj.I{id}.image.colors, 3]);
        notify(obj, 'NewDataset', core.ToggleEventData(struct('index', id, 'keepBackup', true)));

    case 'Copy channel'
        obj.I{id}.image.copyColorChannel(channel1, channel2, options);
        obj.I{id}.slices{4} = 1:min([obj.I{id}.image.colors, 3]);
        notify(obj, 'NewDataset', core.ToggleEventData(struct('index', id, 'keepBackup', true)));

    case 'Invert channel'
        if obj.I{id}.image.time < 2
            backupOpts.id = id;
            obj.backup('image', 1, backupOpts);
        end
        obj.I{id}.image.invertColorChannel(channel1, options);

    case 'Rotate channel'
        if obj.I{id}.image.time < 2
            backupOpts.id = id;
            obj.backup('image', 1, backupOpts);
        end
        obj.I{id}.image.rotateColorChannel(channel1, str2double(BatchOpt.RotationAngle{1}), options);

    case 'Shift channel'
        if obj.I{id}.image.time < 2
            backupOpts.id = id;
            obj.backup('image', 1, backupOpts);
        end
        obj.I{id}.image.shiftColorChannel(channel1, BatchOpt.dx{1}, BatchOpt.dy{1}, BatchOpt.FillValue{1}, options);

    case 'Swap channels'
        if obj.I{id}.image.time < 2
            backupOpts.id = id;
            obj.backup('image', 1, backupOpts);
        end
        obj.I{id}.image.swapColorChannels(channel1, channel2, options);

    case 'Delete channel'
        obj.I{id}.image.deleteColorChannel(channel1, options);
        % slices{4} tracks the visible channels; update since MibImage has no slices property
        visibleChannels = obj.I{id}.slices{4};
        visibleChannels = visibleChannels(~ismember(visibleChannels, channel1));
        visibleChannels(visibleChannels > channel1) = visibleChannels(visibleChannels > channel1) - 1;
        if isempty(visibleChannels); visibleChannels = 1; end
        obj.I{id}.slices{4} = visibleChannels;
        notify(obj, 'NewDataset', core.ToggleEventData(struct('index', id, 'keepBackup', true)));
end

BatchOpt = rmfield(BatchOpt, 'id');
notify(obj, 'SyncBatch', core.ToggleEventData(BatchOpt));
notify(obj, 'ShowImage');
end
