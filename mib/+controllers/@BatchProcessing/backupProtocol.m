function backupProtocol(obj)
% function backupProtocol(obj)
% save a snapshot of the current protocol into the undo history
%
% The history depth is limited to obj.protocolBackupsMaxNumber entries.
% Any redo snapshots ahead of the current position are discarded.
%
%|
% @b Examples:
% @code obj.backupProtocol(); @endcode
%
% Updates
%

obj.protocolBackupsCurrNumber = obj.protocolBackupsCurrNumber + 1;
obj.protocolBackups(obj.protocolBackupsCurrNumber:end) = [];
if obj.protocolBackupsCurrNumber > obj.protocolBackupsMaxNumber     % limit of backup steps reached
    obj.protocolBackupsCurrNumber = obj.protocolBackupsCurrNumber - 1;
    obj.protocolBackups = obj.protocolBackups(2:obj.protocolBackupsCurrNumber);
end
obj.protocolBackups{obj.protocolBackupsCurrNumber} = obj.Protocol;
end
