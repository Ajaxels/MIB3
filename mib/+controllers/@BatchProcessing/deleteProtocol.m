function deleteProtocol(obj)
% DELETEPROTOCOL - delete the current protocol (stores an undo snapshot first).
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.deleteProtocol()
%
% Usage:
%   Example 1::
%
%     obj.deleteProtocol();
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.BatchProcessing.deleteProtocol: triggered\n');
end

obj.backupProtocol();   % store the current protocol

obj.Protocol = [];
obj.protocolListIndex = 0;
obj.updateProtocolList();
obj.protocolList_SelectionCallback();
end
