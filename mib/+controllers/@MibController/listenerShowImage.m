function listenerShowImage(obj, src, evtData)
% function listenerShowImage(obj, src, evtData)
% Call for render image in the Image View panel
% executed upon catch of MibModel->"ShowImage" event, MIB2 is using 'plotImage' event
%
% Parameters:
% src: handle to MibModel
% evtData: event data, an instance of core.ToggleEventData class with the following fields:
% .Parameters field containing a structure with the
%    .evtData.Parameters.resize - logical switch to resize the image in the view
%         @li false -> [@em default]  keep the current vieweing settings
%         @li true -> resize image to fit the screen
% .Source -> handle to MibModel
% .EventName -> string with the event name that triggered the callback
%
% Return values:
% 

if ~isprop(evtData, 'Parameters')
    settings = struct('resize', false);
else
    settings = evtData.Parameters;
    if ~isfield(settings, 'resize'); settings.resize = false; end
end

obj.showImage(settings.resize);
end