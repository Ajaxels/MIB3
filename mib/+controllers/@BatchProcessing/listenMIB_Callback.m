function listenMIB_Callback(obj)
% LISTENMIB_CALLBACK - enable or disable the SyncBatch listener based on the listenMIB checkbox state.
%
% Syntax:
%   function listenMIB_Callback(obj)
%
% Usage:
%   Example 1::
%
%     obj.listenMIB_Callback();
%

if obj.view.handles.listenMIB.Value == true
    obj.listener{2}.Enabled = true;
else
    obj.listener{2}.Enabled = false;
end
end
