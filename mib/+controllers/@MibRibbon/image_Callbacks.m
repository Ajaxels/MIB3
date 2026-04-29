function image_Callbacks(obj, hWidget, hData)
% IMAGE_CALLBACKS - callback on press of buttons in the Image ribbon.
%
% Syntax:
%   function image_Callbacks(obj, hWidget, hData)
%
% Input Arguments:
%   - **hWidget** — handle to the pressed widget
%   - **hData** — handle to supporting EventData class
%

arguments (Input)
    obj controllers.MibRibbon
    hWidget matlab.ui.internal.toolstrip.base.Action
    hData matlab.ui.internal.toolstrip.base.ToolstripEventData
end

mode = hWidget.Text;
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRibbon.image_Callbacks: Image ribbon-> %s\n', mode);
end

switch mode
    case 'Adjust display'               % obj.handles.ribbonImage.display
        obj.mibController.startController('controllers.DisplayAdjust');
    case 'Image filters'                % obj.handles.ribbonImage.filters
    case 'Line intensity profile'       % obj.handles.ribbonImage.profileLine
    case 'Arbitrary intensity profile'  % obj.handles.ribbonImage.profileArbitrary

end


end
