function imageContrast_Callbacks(obj, hWidget, hData)
% function imageContrast_Callbacks(obj, hWidget, hData)
% callback on press of the contrast buttons in the Image ribbon
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting EventData class

arguments (Input)
    obj controllers.MibRibbon
    hWidget matlab.ui.internal.toolstrip.base.Action
    hData matlab.ui.internal.toolstrip.base.ToolstripEventData
end

mode = hWidget.Text;
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRibbon.imageContrast_Callbacks: Image ribbon-> %s\n', mode);
end

switch mode
    case 'Contrast-limited adaptive histogram equalization'     % obj.handles.ribbonImage.contrastCLAHE
    case 'Normalize layers'                                     % obj.handles.ribbonImage.contrastNormZ
    case 'Normalize layers based on mask'                       % obj.handles.ribbonImage.contrastNormZmask
    case 'Normalize layers based on masked background'          % obj.handles.ribbonImage.contrastNormZmaskBg
    case 'Normalize time series'                                % obj.handles.ribbonImage.contrastNormT

end

end