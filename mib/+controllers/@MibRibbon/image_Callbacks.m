function image_Callbacks(obj, hWidget, hData)
% IMAGE_CALLBACKS - callback on press of buttons in the Image ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.image_Callbacks(hWidget, hData)
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
    case {'Grayscale', 'Multi-channel', 'HSV color', 'Indexed', '8 bit', '16 bit', '32 bit'}
        BatchOpt.Target = {mode};
        obj.mibModel.changeImageMode(BatchOpt);
    case sprintf('Adjust\ndisplay')               % obj.handles.ribbonImage.display
        obj.mibController.startController('controllers.DisplayAdjust');
    case 'Contrast-limited adaptive histogram equalization'     % obj.handles.ribbonImage.contrastCLAHE
        obj.mibController.startController('controllers.ContrastClahe');

    case 'Normalize layers'                                     % obj.handles.ribbonImage.contrastNorm
        obj.mibController.startController('controllers.ContrastNormalization');
    case 'Image filters'                % obj.handles.ribbonImage.filters
        obj.mibController.startController('controllers.ImageFilters');
    case 'Line intensity profile'       % obj.handles.ribbonImage.profileLine
    case 'Arbitrary intensity profile'  % obj.handles.ribbonImage.profileArbitrary

end


end
