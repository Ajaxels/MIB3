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

obj.backupProtocol();   % store the current protocol

obj.Protocol = [];
obj.protocolListIndex = 0;
obj.updateProtocolList();
obj.protocolList_SelectionCallback();
end
