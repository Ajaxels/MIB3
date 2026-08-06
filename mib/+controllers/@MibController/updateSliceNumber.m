function updateSliceNumber(obj, BatchOptIn)
% UPDATESLICENUMBER - Change the currently displayed slice number in the active image document.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.updateSliceNumber()
%      obj.updateSliceNumber(BatchOpt)
%
% Wrapper that exposes slice navigation to the MIB batch processing
% system. Validates the requested slice number (clamping it to the valid
% range) and then delegates to the active MibImageDocument's
% sliceNumber_Callback, which updates the slider and redraws the image.
%
% Input Arguments:
%   - **BatchOptIn** - *(optional)* structure for batch processing mode; when NaN,
%     returns default options via the "SyncBatch" event
%
%     - ``.SliceNumber`` - [char, default ``'1'``] slice number to display as a string;
%       use ``'0'`` to jump to the last slice of the dataset
%
% Output Arguments:
%   (none)
%
% **Example 1** - interactive call (reads from the slice-number widget):
%
%   .. code-block:: matlab
%
%      obj.updateSliceNumber();
%
% **Example 2** - batch call: jump to slice 5:
%
%   .. code-block:: matlab
%
%      BatchOpt.SliceNumber = '5';
%      obj.updateSliceNumber(BatchOpt);
%
% **Example 3** - batch call: jump to the last slice:
%
%   .. code-block:: matlab
%
%      BatchOpt.SliceNumber = '0';
%      obj.updateSliceNumber(BatchOpt);
%

% Updates

if nargin < 2; BatchOptIn = struct; end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
BatchOpt.SliceNumber = '1';

BatchOpt.mibBatchSectionName = 'Panel -> Image view';
BatchOpt.mibBatchActionName = 'Change slice number';

% tooltips that will accompany the BatchOpt
BatchOpt.mibBatchTooltip.SliceNumber = 'Enter a new slice number; use 0 to show the last slice of the dataset';

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
            'Error in MibController.updateSliceNumber', '', errorOpts);
    end
    return;
else
    % add/update BatchOpt with the provided fields in BatchOptIn
    % combine fields from input and default structures
    BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
end

selectedSet = obj.mibModel.Sets.selectedSet;
obj.cImageDoc{selectedSet}.sliceNumber_Callback(str2double(BatchOpt.SliceNumber), struct());
end
