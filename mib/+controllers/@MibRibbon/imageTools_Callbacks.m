function imageTools_Callbacks(obj, hWidget, hData)
% function imageTools_Callbacks(obj, hWidget, hData)
% callback on press of Image tools buttons in the Image ribbon
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
    fprintf('controllers.MibRibbon.imageTools_Callbacks: Image ribbon-> Image tools -> %s\n', mode);
end

switch mode
    case 'Content-aware fill'               % obj.handles.ribbonImage.contentAware
    case 'Debris removal'                % obj.handles.ribbonImage.debrisRemoval
    case 'Image arithmetics'       % obj.handles.ribbonImage.imageMath
    case 'Intensity projection'  % obj.handles.ribbonImage.intProjection
    case 'Select image frame'               % obj.handles.ribbonImage.imgFrame
    case 'White balance correction'                % obj.handles.ribbonImage.whiteBalance

end

end