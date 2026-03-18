function protocolActions_Callback(obj, options)
% function protocolActions_Callback(obj, options)
% add, remove, reorder or update steps in the protocol list
%
% Parameters:
% options: a string specifying the operation:
%   'add'       - append current action as a new last step
%   'duplicate' - duplicate the selected step (inserts copy after it)
%   'insert'    - insert current action before the selected step
%   'insertstop'- insert a STOP EXECUTION step before the selected step
%   'update'    - overwrite the selected step with current action settings
%   'show'      - display settings of the selected step (read-only)
%   'delete'    - remove the selected step
%   'moveup'    - swap the selected step with the one above it
%   'movedown'  - swap the selected step with the one below it
%
%|
% @b Examples:
% @code obj.protocolActions_Callback('add'); @endcode
% @code obj.protocolActions_Callback('delete'); @endcode
% @code obj.protocolActions_Callback('moveup'); @endcode
%
% Updates
%

switch options
    case {'add', 'insert', 'update', 'duplicate'}      % add, insert or update selected action to the protocol
        if isempty(obj.CurrentBatch)
            warnOpts.MsgBoxOnly = true; warnOpts.Icon = 'puffin_warning';
            warnOpts.Header = 'Please select an action to perform from the list of available actions and try again!';
            utils.dlgs.inputUniversalDlg(obj.view.gui, {}, {}, 'Action not selected', warnOpts);
            return;
        end
        obj.backupProtocol();   % store the current protocol
        switch options
            case 'add'
                obj.protocolListIndex = numel(obj.Protocol)+1;
            case 'duplicate'
                obj.protocolListIndex = max([1 obj.protocolListIndex]);
                obj.Protocol(obj.protocolListIndex+1:numel(obj.Protocol)+1) = obj.Protocol(obj.protocolListIndex:numel(obj.Protocol));
                obj.protocolListIndex = obj.protocolListIndex + 1;
            case 'insert'
                obj.protocolListIndex = max([1 obj.protocolListIndex]);
                obj.Protocol(obj.protocolListIndex+1:numel(obj.Protocol)+1) = obj.Protocol(obj.protocolListIndex:numel(obj.Protocol));
            case 'update'
                if obj.protocolListIndex==0; obj.protocolListIndex=1; end
        end
        obj.Protocol(obj.protocolListIndex).mibBatchSectionName = obj.CurrentBatch.mibBatchSectionName;
        obj.Protocol(obj.protocolListIndex).mibBatchActionName = obj.CurrentBatch.mibBatchActionName;
        obj.Protocol(obj.protocolListIndex).Command = obj.Sections(obj.selectedSection).Actions(obj.selectedAction).Command;
        obj.Protocol(obj.protocolListIndex).Batch = rmfield(obj.CurrentBatch, {'mibBatchSectionName','mibBatchActionName'});
    case 'insertstop'
        obj.backupProtocol();   % store the current protocol
        obj.protocolListIndex = max([1 obj.protocolListIndex]);
        obj.Protocol(obj.protocolListIndex+1:numel(obj.Protocol)+1) = obj.Protocol(obj.protocolListIndex:numel(obj.Protocol));

        obj.Protocol(obj.protocolListIndex).mibBatchSectionName = 'Service steps';
        obj.Protocol(obj.protocolListIndex).mibBatchActionName = 'STOP EXECUTION';
        obj.Protocol(obj.protocolListIndex).Command = [];
        obj.Protocol(obj.protocolListIndex).Batch = struct();
        obj.Protocol(obj.protocolListIndex).Batch.Description = 'Wait for a user';
    case 'show'
        if obj.protocolListIndex == 0; return; end
        BatchOpt = obj.Protocol(obj.protocolListIndex).Batch;
        BatchOpt.mibBatchSectionName = obj.Protocol(obj.protocolListIndex).mibBatchSectionName;
        BatchOpt.mibBatchActionName  = obj.Protocol(obj.protocolListIndex).mibBatchActionName;
        obj.updateSelectedActionTable(BatchOpt);
        obj.selectedActionTableIndex = 1;
        obj.displaySelectedActionTableItems();
    case 'moveup'
        if obj.protocolListIndex < 2; return; end
        obj.backupProtocol();   % store the current protocol
        currAction = obj.Protocol(obj.protocolListIndex);
        obj.Protocol(obj.protocolListIndex) = obj.Protocol(obj.protocolListIndex-1);
        obj.Protocol(obj.protocolListIndex-1) = currAction;
        obj.protocolListIndex = obj.protocolListIndex - 1;
    case 'movedown'
        if obj.protocolListIndex == numel(obj.Protocol); return; end
        obj.backupProtocol();   % store the current protocol
        currAction = obj.Protocol(obj.protocolListIndex);
        obj.Protocol(obj.protocolListIndex) = obj.Protocol(obj.protocolListIndex+1);
        obj.Protocol(obj.protocolListIndex+1) = currAction;
        obj.protocolListIndex = obj.protocolListIndex + 1;
    case 'delete'
        if obj.protocolListIndex == 0; return; end
        obj.backupProtocol();   % store the current protocol
        obj.Protocol(obj.protocolListIndex) = [];
        obj.protocolListIndex = obj.protocolListIndex - 1;
        if numel(obj.Protocol)>0 && obj.protocolListIndex == 0
            obj.protocolListIndex = 1;
        end
end
obj.updateProtocolList();
obj.protocolList_SelectionCallback();
end
