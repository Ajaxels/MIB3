function deleteProtocol(obj)
% function deleteProtocol(obj)
% delete the current protocol (stores an undo snapshot first)
%
%|
% @b Examples:
% @code obj.deleteProtocol(); @endcode
%
% Updates
%

obj.backupProtocol();   % store the current protocol

obj.Protocol = [];
obj.protocolListIndex = 0;
obj.updateProtocolList();
obj.protocolList_SelectionCallback();
end
