function backupProtocolRestore(obj, mode)
% function backupProtocolRestore(obj, mode)
% restore the protocol from the undo/redo history
%
% Parameters:
% mode: a string with direction of restoration
%  'undo' - restore the previous state
%  'redo' - restore the next state
%
%|
% @b Examples:
% @code obj.backupProtocolRestore('undo'); @endcode
% @code obj.backupProtocolRestore('redo'); @endcode
%
% Updates
%

if nargin < 2; mode = 'undo'; end
switch mode
    case 'undo'
        if obj.protocolBackupsCurrNumber == 0; return; end % first history entry is reached
        currProtocol = obj.Protocol;
        obj.Protocol = obj.protocolBackups{obj.protocolBackupsCurrNumber};
        obj.protocolBackups{obj.protocolBackupsCurrNumber} = currProtocol;
        obj.protocolBackupsCurrNumber = obj.protocolBackupsCurrNumber - 1;
        obj.protocolListIndex = obj.protocolListIndex - 1;
    case 'redo'
        if obj.protocolBackupsCurrNumber == obj.protocolBackupsMaxNumber || obj.protocolBackupsCurrNumber == numel(obj.protocolBackups)
            return;
        end % last history entry is reached
        obj.protocolBackupsCurrNumber = min([obj.protocolBackupsCurrNumber + 1, numel(obj.protocolBackups)]);
        currProtocol = obj.Protocol;
        obj.Protocol = obj.protocolBackups{obj.protocolBackupsCurrNumber};
        obj.protocolBackups{obj.protocolBackupsCurrNumber} = currProtocol;
        obj.protocolListIndex = min([obj.protocolListIndex + 1, numel(obj.view.handles.protocolList.Items)]);
end
obj.updateProtocolList();
end
