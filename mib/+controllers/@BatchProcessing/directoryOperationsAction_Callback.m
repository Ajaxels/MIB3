function directoryOperationsAction_Callback(obj, BatchOptInput)
% function directoryOperationsAction_Callback(obj, BatchOptInput)
% build or apply the BatchOpt structure for a Directory Operations protocol step
%
% When called with no second argument (interactive mode) the function
% constructs a default BatchOpt and returns.  When called with
% BatchOptInput == NaN it fires a SyncBatch event so the Batch Processing
% controller populates its parameter table.  When called with a struct it
% merges supplied fields over the defaults via updateBatchOptCombineFields_Shared.
%
% Supported operations (Operation field):
% @li 'Change current MIB directory' - set obj.mibModel.currentDirectory
% @li 'Create new'                   - create the resolved directory if absent
% @li 'Delete directory'             - remove the resolved (empty) directory
%
% Directory resolution mode (Mode field):
% @li 'Absolute'                    - use DirectoryName verbatim
% @li 'Relative to current MIB path'- resolve relative to currentDirectory
% @li 'Inherit from Directory loop' - use directory from the enclosing loop
% @li 'Inherit dirs +Dirname'       - append DirectoryName to the loop directory
%
% Parameters:
% BatchOptInput: [optional]
%   @li NaN    - send default BatchOpt to BatchProcessing via SyncBatch event
%   @li struct - override defaults with supplied fields and apply
%
%|
% @b Examples:
% @code obj.directoryOperationsAction_Callback(NaN); // populate parameter table @endcode
% @code obj.directoryOperationsAction_Callback(BatchOpt); // apply saved settings @endcode
%
% Updates
%

BatchOpt.Operation = {'Change current MIB directory'};   % specify the operation
BatchOpt.Operation{2} = {'Change current MIB directory', 'Create new', 'Delete directory'};
BatchOpt.Mode = {'Relative to current MIB path'};   % directory resolution mode
BatchOpt.Mode{2} = {'Absolute', 'Inherit from Directory loop', 'Inherit dirs +Dirname', 'Relative to current MIB path'};
BatchOpt.DirectoryName = 'subFolder';
% add section name and action name for the batch tool
BatchOpt.mibBatchSectionName = 'Menu -> File';
BatchOpt.mibBatchActionName = 'Directory operations';
% tooltips that will accompany the BatchOpt
BatchOpt.mibBatchTooltip.Operation = 'A directory operation to perform, directories that have files can not be removed';
BatchOpt.mibBatchTooltip.Mode = 'Relative: directory name will be added to the current MIB path; Inherit: path will be acquired from DIR LOOP; +Dirname: adds dirname to dir loop directory; Absolute: the full provided dirname will be used';
BatchOpt.mibBatchTooltip.DirectoryName = 'Provide full directory name, relative to current or use "../" to go to parent directory. Use the right mouse click to modify';

if nargin == 2
    if isstruct(BatchOptInput) == 0
        if isnan(BatchOptInput)
            % trigger syncBatch event to send BatchOptOut to BatchProcessing controller
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        else
            errordlg(sprintf('A structure as the 1st parameter is required!'));
        end
        return;
    end
    % combine fields from input and default structures
    BatchOpt = updateBatchOptCombineFields_Shared(BatchOpt, BatchOptInput);
end
end
