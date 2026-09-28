function closeWindow(obj)
% CLOSEWINDOW - Close the inspector window and free its resources.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.closeWindow()
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.StitchingInspector.closeWindow: triggered\n');
end

% Reopen on the same settings later in this session (restoreSessionSettings).
obj.storeSessionSettings();

if ~isempty(obj.view) && isvalid(obj.view.gui)
    delete(obj.view.gui);
end
for listenerIdx = 1:numel(obj.listener)
    if ~isempty(obj.listener{listenerIdx}) && isvalid(obj.listener{listenerIdx})
        delete(obj.listener{listenerIdx});
    end
end
notify(obj, 'CloseEvent');
end
