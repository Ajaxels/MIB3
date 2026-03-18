function listenMIB_Callback(obj)
% function listenMIB_Callback(obj)
% enable or disable the SyncBatch listener based on the listenMIB checkbox state
%
%|
% @b Examples:
% @code obj.listenMIB_Callback(); @endcode
%
% Updates
%

if obj.view.handles.listenMIB.Value == true
    obj.listener{2}.Enabled = true;
else
    obj.listener{2}.Enabled = false;
end
end
