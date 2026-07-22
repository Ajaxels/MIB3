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

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.BatchProcessing.listenMIB_Callback: triggered\n');
end
if obj.view.handles.listenMIB.Value == true
    obj.listener{2}.Enabled = true;
else
    obj.listener{2}.Enabled = false;
end
end
