function listener_showImage(obj, src, evtData)
% LISTENER_SHOWIMAGE - Call for render image in the Image View panel.
%
% Syntax:
%   function listener_showImage(obj, src, evtData)
%
% executed upon catch of MibModel->"ShowImage" event, MIB2 is using 'plotImage' event
%
% Input Arguments:
%   - **src** — handle to MibModel
%   - **evtData** — event data, an instance of core.ToggleEventData class with the following fields:
%     .Parameters field containing a structure with the
%     .evtData.Parameters.resizeToMagnification - logical switch to resize the image in the view
%     - false [*default]*  keep the current vieweing settings
%     - true resize image to fit the screen
%   .evtData.Parameters.setOfDatasetsIndex [numerical] - id of the set use for show image, when empty use the current one
%   .Source handle to MibModel
%   .EventName string with the event name that triggered the callback
%
% Output Arguments:
%

if ~isprop(evtData, 'Parameters')
    settings = struct('resizeToMagnification', true, 'setOfDatasetsIndex', []);
else
    settings = evtData.Parameters;
    if ~isfield(settings, 'resizeToMagnification'); settings.resizeToMagnification = true; end
    if ~isfield(settings, 'setOfDatasetsIndex'); settings.setOfDatasetsIndex = []; end
end

obj.showImage(settings.resizeToMagnification, settings.setOfDatasetsIndex);
end
