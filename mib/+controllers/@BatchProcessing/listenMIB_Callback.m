function listenMIB_Callback(obj)
% LISTENMIB_CALLBACK - enable or disable the SyncBatch listener based on the listenMIB checkbox state.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.listenMIB_Callback()
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
