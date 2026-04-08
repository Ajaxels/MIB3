function directoryLoopAction_Callback(obj, BatchOptInput)
% function directoryLoopAction_Callback(obj, BatchOptInput)
% build or apply the BatchOpt structure for a Directory Loop protocol step
%
% When called with no second argument (interactive mode) the function
% constructs a default BatchOpt and returns without doing anything further.
% When called with BatchOptInput == NaN it fires a SyncBatch event so that
% the Batch Processing controller can populate its parameter table with the
% defaults.  When called with a struct it merges the supplied fields over the
% defaults via updateBatchOptCombineFields_Shared.
%
% The resulting BatchOpt specifies:
% @li DirectoriesList - initially set to obj.mibModel.currentDirectory; the
%     user expands the list via the context menu in the Batch Processing GUI
% @li DirLoopWaitbar  - [logical] whether to show a per-directory waitbar
%
% Parameters:
% BatchOptInput: [optional]
%   @li NaN    - send default BatchOpt to BatchProcessing via SyncBatch event
%   @li struct - override defaults with supplied fields and apply
%
%|
% @b Examples:
% @code obj.directoryLoopAction_Callback(NaN); // populate parameter table @endcode
% @code obj.directoryLoopAction_Callback(BatchOpt); // apply saved settings @endcode
%
% Updates
%

BatchOpt.DirectoriesList = {obj.mibModel.currentDirectory};   % cell with the selected directory
BatchOpt.DirectoriesList{2} = {obj.mibModel.currentDirectory};    %  cell array with list of directories
BatchOpt.DirLoopWaitbar = true;   % when true show waitbar for the directory loop

% add section name and action name for the batch tool
BatchOpt.mibBatchSectionName = 'Service steps';
BatchOpt.mibBatchActionName = 'DIRECTORY LOOP START';
% tooltips that will accompany the BatchOpt
BatchOpt.mibBatchTooltip.DirectoriesList = sprintf('List of directories that are going to be processed in the loop; use the right mouse click over the Parameters table to add/remove directory');
BatchOpt.mibBatchTooltip.DirLoopWaitbar = 'when checked the waitbar for the dirloop is displayed';

if nargin == 2
    if isstruct(BatchOptInput) == 0
        if isnan(BatchOptInput)
            % trigger syncBatch event to send BatchOptOut to BatchProcessing controller
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        else
            errOpts.MsgBoxOnly = true; 
            utils.dlgs.inputUniversalDlg(obj.view.gui, 'A structure as the 1st parameter is required!', {}, {}, 'DirectoryLoopAction_Callback error', errOpts);
        end
        return;
    end
    % combine fields from input and default structures
    BatchOpt = updateBatchOptCombineFields_Shared(BatchOpt, BatchOptInput);
end
end
