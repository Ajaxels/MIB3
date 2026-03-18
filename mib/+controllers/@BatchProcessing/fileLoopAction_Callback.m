function fileLoopAction_Callback(obj, BatchOptInput)
% function fileLoopAction_Callback(obj, BatchOptInput)
% build or apply the BatchOpt structure for a File Loop protocol step
%
% When called with no second argument (interactive mode) the function
% constructs a default BatchOpt and returns.  When called with
% BatchOptInput == NaN it fires a SyncBatch event so that the Batch
% Processing controller populates its parameter table with the defaults.
% When called with a struct it merges supplied fields over the defaults via
% updateBatchOptCombineFields_Shared.
%
% The resulting BatchOpt specifies:
% @li DirectoryName   - source directory; choices include 'Current MIB path',
%     'Inherit from Directory loop', or an absolute path
% @li FilenameFilter  - wildcard applied inside the directory (default '*.*')
% @li FileLoopWaitbar - [logical] when true only the file-level waitbar is
%     displayed; all per-step waitbars are suppressed
%
% Parameters:
% BatchOptInput: [optional]
%   @li NaN    - send default BatchOpt to BatchProcessing via SyncBatch event
%   @li struct - override defaults with supplied fields and apply
%
%|
% @b Examples:
% @code obj.fileLoopAction_Callback(NaN); // populate parameter table @endcode
% @code obj.fileLoopAction_Callback(BatchOpt); // apply saved settings @endcode
%
% Updates
%

BatchOpt.DirectoryName = {'Current MIB path'};   % specify the target directory
BatchOpt.DirectoryName{2} = {'Current MIB path', 'Inherit from Directory loop', obj.mibModel.currentDirectory};
BatchOpt.FilenameFilter = '*.*';   % use the filename filter to select files
BatchOpt.FileLoopWaitbar = true;   % when true only the waitbar for the fileloop is displayed, waitbars in all substeps are disabled
% add section name and action name for the batch tool
BatchOpt.mibBatchSectionName = 'Service steps';
BatchOpt.mibBatchActionName = 'FILE LOOP START';
% tooltips that will accompany the BatchOpt
BatchOpt.mibBatchTooltip.DirectoryName = 'Directory name, where the files are located, use the right mouse click over the Parameters table to modify the directory';
BatchOpt.mibBatchTooltip.FilenameFilter = 'Filter for filenames: *.* - process all files in the directory; *.tif - process only the TIF files';
BatchOpt.mibBatchTooltip.FileLoopWaitbar = 'when checked only the waitbar for the fileloop is displayed, waitbars in all substeps are turned off';

if nargin == 2
    if isstruct(BatchOptInput) == 0
        if isnan(BatchOptInput)
            % trigger syncBatch event to send BatchOptOut to BatchProcessing controller
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        else
            errOpts.MsgBoxOnly = true; errOpts.Icon = 'puffin_error';
            errOpts.Header = 'A structure as the 1st parameter is required!';
            utils.dlgs.inputUniversalDlg(obj.view.gui, {}, {}, 'FileLoopAction_Callback error', errOpts);
        end
        return;
    end
    % combine fields from input and default structures
    BatchOpt = updateBatchOptCombineFields_Shared(BatchOpt, BatchOptInput);
end
end
