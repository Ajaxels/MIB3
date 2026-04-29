function listener_updateStatusBar(obj, src, evtData)
% LISTENER_UPDATESTATUSBAR - Call for update of the status bar widgets, used upon change of directory.
%
% Syntax:
%   function listener_updateStatusBar(obj, src, evtData)
%
% in Batch Processing
% executed upon catch of MibModel->"UpdateStatusBar" event
%
% Input Arguments:
%   - **src** — handle to MibModel
%   - **evtData** — event data, an instance of core.ToggleEventData class with the following fields:
%     .Parameters field containing a structure with the
%     .evtData.Parameters.
%     .Source handle to MibModel
%     .EventName string with the event name that triggered the callback
%
% Output Arguments:
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
