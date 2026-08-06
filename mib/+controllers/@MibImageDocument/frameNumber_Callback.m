function frameNumber_Callback(obj, parameter, BatchOptIn)
% FRAMENUMBER_CALLBACK - Callback for changing the time points by entering a new time value.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.frameNumber_Callback()
%      obj.frameNumber_Callback(parameter)
%      obj.frameNumber_Callback(parameter, BatchOptIn)
%
% Handles input from the frame number edit box in the MIB image document
% view. Validates and clamps the requested frame number, then delegates
% the actual frame update to ``frameNumberSlider_Callback``. Also supports
% MIB batch processing via the BatchOpt mechanism.
%
% Input Arguments:
%   - **parameter** *(optional)* - [numeric] requested frame number (if omitted, reads from ``obj.handles.frameNumber.Value``)
%   - **BatchOptIn** *(optional)* - [struct|NaN] batch processing control:
%
%     - [struct] fields are merged into default BatchOpt, allowing programmatic override of ``FrameNumber``
%     - ``NaN`` triggers ``'SyncBatch'`` event and returns immediately, sending BatchOpt settings to mibBatchController
%     - omitted defaults to empty struct (interactive mode)
%
% Output Arguments:
%   (none)
%
% **Frame Number Clamping Rules:**
%   - value ``== 0`` or ``value > maxTime`` → clamped to ``maxTime`` (last frame)
%   - value ``< 0`` → clamped to ``1`` (first frame)
%   - otherwise → used as-is
%
% **BatchOpt Structure Fields:**
%   - ``.FrameNumber`` - [char] requested frame number as string; use ``'0'`` to jump to last time point
%   - ``.mibBatchSectionName`` - [char] UI section label: ``'Panel -> Image view'``
%   - ``.mibBatchActionName`` - [char] batch action label: ``'Change frame/time number'``
%   - ``.mibBatchTooltip`` - [struct] tooltips for each BatchOpt field
%
% **Example 1** - navigate to frame 5 programmatically:
%
%   .. code-block:: matlab
%
%      obj.cImageDoc{obj.mibModel.Sets.selectedSet}.frameNumber_Callback(5, struct());
%
% **Example 2** - jump to last frame using shorthand value ``0``:
%
%   .. code-block:: matlab
%
%      obj.cImageDoc{obj.mibModel.Sets.selectedSet}.frameNumber_Callback(0, struct());
%
% **Example 3** - query available batch settings:
%
%   .. code-block:: matlab
%
%      obj.cImageDoc{obj.mibModel.Sets.selectedSet}.frameNumber_Callback([], NaN);

if nargin < 3; BatchOptIn = struct; end
if nargin < 2; parameter = []; end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibImageDocument.frameNumber_Callback: "obj.cImageDoc{%d}.handles.frameNumber" ->slices changed (obj.mibModel.Sets.selectedSet)\n', obj.mibModel.Sets.selectedSet);
end

if isempty(parameter); parameter = obj.handles.frameNumber.Value; end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
BatchOpt.FrameNumber = num2str(parameter);

BatchOpt.mibBatchSectionName = 'Panel -> Image view';
BatchOpt.mibBatchActionName = 'Change frame/time number';

% tooltips that will accompany the BatchOpt
BatchOpt.mibBatchTooltip.FrameNumber = sprintf('Enter a new frame number; use 0 to show the last time point of the dataset');

if isstruct(BatchOptIn) == 0
    if isnan(BatchOptIn)     % when varargin{2} == NaN return possible settings
        % trigger syncBatch event to send BatchOptInOut to mibBatchController
        eventdata = core.ToggleEventData(BatchOpt);
        notify(obj.mibModel, 'SyncBatch', eventdata);
    else
        errorOpts.mibPath = obj.mibModel.mibPath;
        errorOpts.WindowHeight = 150;
        utils.dlgs.showErrorDialog(obj.view.gui, sprintf('A structure as the 3rd parameter is required!'), 'Error', 'Error in MibImageDocument.frameNumber_Callback', '', errorOpts);
    end
    return;
else
    % add/update BatchOpt with the provided fields in BatchOptIn
    % combine fields from input and default structures
    BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
end

if nargin > 1
    maxTime = obj.mibModel.I{obj.mibModel.id}.image.time;
    newFrameNumber = str2double(BatchOpt.FrameNumber);
    if newFrameNumber == 0 || newFrameNumber > maxTime
        newFrameNumber = maxTime;
    elseif newFrameNumber < 0
        newFrameNumber = 1;
    end
    BatchOpt.FrameNumber = num2str(newFrameNumber);
    obj.handles.frameNumberSlider.Value = newFrameNumber;
end

obj.handles.frameNumberSlider.Value = str2double(BatchOpt.FrameNumber);
obj.frameNumberSlider_Callback();
end
