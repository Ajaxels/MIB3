function listener_updateStatusBar(obj, src, evtData)
% LISTENER_UPDATESTATUSBAR - Update status bar widgets on directory change or UpdateStatusBar event.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.listener_updateStatusBar(src, evtData)
%
% Listener triggered by ``MibModel`` ``'UpdateStatusBar'`` event (e.g., during Batch Processing directory changes).
%
% Input Arguments:
%   - **obj** - [MibStatusBar] controller instance
%   - **src** - [MibModel] source object
%   - **evtData** - [ToggleEventData] event data with properties:
%
%     - ``.Parameters`` - [struct] optional parameters structure
%     - ``.Source`` - [MibModel] handle to MibModel
%     - ``.EventName`` - [char] event name that triggered callback
%
%

% if ~isprop(evtData, 'Parameters')
%     settings = struct('resizeToMagnification', true, 'setOfDatasetsIndex', []);
% else
%     settings = evtData.Parameters;
%     if ~isfield(settings, 'resizeToMagnification'); settings.resizeToMagnification = true; end
%     if ~isfield(settings, 'setOfDatasetsIndex'); settings.setOfDatasetsIndex = []; end
% end

obj.handles.currentDirectory.Value = obj.mibModel.currentDirectory; % update path in MIB status bar

end
