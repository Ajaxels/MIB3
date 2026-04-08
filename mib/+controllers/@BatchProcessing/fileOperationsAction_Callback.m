function fileOperationsAction_Callback(obj, BatchOptInput)
% function fileOperationsAction_Callback(obj, BatchOptInput)
% build or apply the BatchOpt structure for a File Operations protocol step
%
% When called with no second argument (interactive mode) the function
% constructs a default BatchOpt and returns.  When called with
% BatchOptInput == NaN it fires a SyncBatch event so the Batch Processing
% controller populates its parameter table.  When called with a struct it
% merges supplied fields over the defaults via updateBatchOptCombineFields_Shared.
%
% Supported file operations (Operation field):
% @li 'Copy'   - copy files matching FilenameMask from CurrentDirectory to TargetDirectory
% @li 'Delete' - delete files matching FilenameMask in CurrentDirectory
% @li 'Move'   - move files matching FilenameMask from CurrentDirectory to TargetDirectory
%
% Directory resolution is controlled independently for source and target via
% CurrentDirectoryMode / TargetDirectoryMode (Absolute, Relative to current
% MIB path, Inherit from Directory loop).
%
% Parameters:
% BatchOptInput: [optional]
%   @li NaN    - send default BatchOpt to BatchProcessing via SyncBatch event
%   @li struct - override defaults with supplied fields and apply
%
%|
% @b Examples:
% @code obj.fileOperationsAction_Callback(NaN); // populate parameter table @endcode
% @code obj.fileOperationsAction_Callback(BatchOpt); // apply saved settings @endcode
%
% Updates
%

BatchOpt.Operation = {'Delete'};   % specify the operation
BatchOpt.Operation{2} = {'Copy', 'Delete', 'Move'};
BatchOpt.CurrentDirectoryMode = {'Relative to current MIB path'};
BatchOpt.CurrentDirectoryMode{2} = {'Absolute', 'Relative to current MIB path', 'Inherit from Directory loop'};
BatchOpt.CurrentDirectory = '';
BatchOpt.TargetDirectoryMode = {'Relative to current MIB path'};
BatchOpt.TargetDirectoryMode{2} = {'Absolute', 'Relative to current MIB path', 'Inherit from Directory loop'};
BatchOpt.TargetDirectory = '';
BatchOpt.FilenameMask = '*.extension';
% add section name and action name for the batch tool
BatchOpt.mibBatchSectionName = 'Ribbon -> Home';
BatchOpt.mibBatchActionName = 'File operations';
% tooltips that will accompany the BatchOpt
BatchOpt.mibBatchTooltip.Operation = 'File operation to perform';
BatchOpt.mibBatchTooltip.CurrentDirectoryMode = 'Strategy to acquire source directory with files';
BatchOpt.mibBatchTooltip.CurrentDirectory = 'List here the full path to directory (Absolute) or relative. Use the right mouse click to select directory';
BatchOpt.mibBatchTooltip.TargetDirectoryMode = 'Strategy to acquire directory for files, not used for Delete operation';
BatchOpt.mibBatchTooltip.TargetDirectory = 'List here the full path to directory (Absolute) or relative. Use the right mouse click to select directory';
BatchOpt.mibBatchTooltip.FilenameMask = 'Filter file names using this mask, put "*.*" to take all files';

if nargin == 2
    if isstruct(BatchOptInput) == 0
        if isnan(BatchOptInput)
            % trigger syncBatch event to send BatchOptOut to BatchProcessing controller
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        else
            errOpts.MsgBoxOnly = true; errOpts.Icon = 'puffin_error';
            header = 'A structure as the 1st parameter is required!';
            utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'FileOperationsAction_Callback error', errOpts);
        end
        return;
    end
    % combine fields from input and default structures
    BatchOpt = updateBatchOptCombineFields_Shared(BatchOpt, BatchOptInput);
end
end
