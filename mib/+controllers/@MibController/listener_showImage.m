function listener_showImage(obj, src, evtData)
% LISTENER_SHOWIMAGE - Call for render image in the Image View panel.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.listener_showImage(src, evtData)
%
% executed upon catch of MibModel->"ShowImage" event, MIB2 is using 'plotImage' event
%
% Input Arguments:
%   - **src** — handle to MibModel
%   - **evtData** — event data, an instance of ``core.ToggleEventData``; ``evtData.Parameters``
%     is a structure with the following fields:
%
%     - ``.resizeToMagnification`` — logical; ``false`` (default) keeps current view settings,
%       ``true`` resizes the image to fit the screen
%     - ``.setOfDatasetsIndex`` — *(optional)* numerical id of the set to display;
%       ``[]`` uses the currently selected set
%
% Output Arguments:
%   (none)
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
