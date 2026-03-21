function updateFrameNumber(obj, BatchOptIn)
% function updateFrameNumber(obj, BatchOptIn)
% Change the currently displayed time frame in the active image document
%
% Wrapper that exposes time-frame navigation to the MIB batch processing
% system. Validates the requested frame number (clamping it to the valid
% range) and then delegates to the active MibImageDocument's
% frameNumber_Callback, which updates the slider and redraws the image.
%
% Parameters:
% BatchOptIn: [@em optional] structure for batch processing mode; when NaN,
%   returns default options via the "SyncBatch" event
% @li .FrameNumber - [char, {'1'}] frame/time number to display as a string;
%   use '0' to jump to the last time point of the dataset
%
% Return values:
%   none
%
%|
% @b Examples:
% @code obj.updateFrameNumber();                                          % interactive: reads value from the frame-number widget @endcode
% @code
% BatchOpt.FrameNumber = '3';
% obj.updateFrameNumber(BatchOpt);                                        % batch/scripted call: jump to frame 3
% @endcode
% @code
% BatchOpt.FrameNumber = '0';
% obj.updateFrameNumber(BatchOpt);                                        % batch/scripted call: jump to the last frame
% @endcode

% Updates

if nargin < 2; BatchOptIn = struct; end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
BatchOpt.FrameNumber = '1';

BatchOpt.mibBatchSectionName = 'Panel -> Image view';
BatchOpt.mibBatchActionName = 'Change frame/time number';

% tooltips that will accompany the BatchOpt
BatchOpt.mibBatchTooltip.FrameNumber = 'Enter a new frame number; use 0 to show the last time point of the dataset';

%%
if isstruct(BatchOptIn) == 0
    if isnan(BatchOptIn)     % when BatchOptIn == NaN return possible settings
        % trigger syncBatch event to send BatchOpt to mibBatchController
        eventdata = core.ToggleEventData(BatchOpt);
        notify(obj.mibModel, 'SyncBatch', eventdata);
    else
        errorOpts.mibPath = obj.mibModel.mibPath;
        errorOpts.WindowHeight = 150;
        utils.dlgs.showErrorDialog(obj.view.gui, 'A structure as the 2nd parameter is required!', 'Error', ...
            'Error in MibController.updateFrameNumber', '', errorOpts);
    end
    return;
else
    % add/update BatchOpt with the provided fields in BatchOptIn
    % combine fields from input and default structures
    BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
end

selectedSet = obj.mibModel.Sets.selectedSet;
obj.cImageDoc{selectedSet}.frameNumber_Callback(str2double(BatchOpt.FrameNumber), struct());
end
