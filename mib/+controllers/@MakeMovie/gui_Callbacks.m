function gui_Callbacks(obj, source, ~)
% GUI_CALLBACKS - Dispatcher for all MakeMovie widget callbacks.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.gui_Callbacks(source, event)
%
% Routes by ``source.Tag`` to the appropriate action method.
%
% Parameters:
%   - **obj** — :class:`controllers.MakeMovie`
%   - **source** — widget handle that fired the event
%   - **event** — event data (unused)
%

switch source.Tag
    case 'continueBtn'
        obj.continueBtn_Callback();
    case 'closeBtn'
        obj.closeWindow();
    case 'helpButton'
        obj.help();
    case 'selectFileBtn'
        obj.selectFileBtn_Callback();
    case 'outputDir'
        obj.outputDir_Callback();
    case 'Format'
        obj.formatPopup_Callback();
    case 'widthEdit'
        obj.widthEdit_Callback();
    case 'heightEdit'
        obj.heightEdit_Callback();
    case 'directionPopup'
        obj.directionPopup_Callback();
    case 'scalebarCheck'
        obj.scalebarCheck_Callback();
    case 'roiPopup'
        obj.roiPopup_Callback();
    case 'splitChannelsCheck'
        obj.splitChannelsCheck_Callback();
    case {'cropPanel', 'fullImageRadio', 'shownAreaRadio', 'roiRadio'}
        obj.crop_Callback();
end
end
