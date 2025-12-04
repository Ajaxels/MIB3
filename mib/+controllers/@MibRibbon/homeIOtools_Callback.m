function homeIOtools_Callback(obj, hWidget, hData)
% function homeIOtools_Callback(obj, hWidget, hData)
% callback on press of the I/O tools buttons in the Home ribbon
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
    fprintf('controllers.MibRibbon.homeIOtools_Callback: I/O Tools pressed -> %s\n', mode);
end

switch mode
    case sprintf('Batch\nprocessing')   % obj.handles.ribbonHome.batch
    case 'Chunk dataset'                % obj.handles.ribbonHome.chunk
    case 'Stitch dataset'               % obj.handles.ribbonHome.stitch
    case 'Shuffle images'               % obj.handles.ribbonHome.shuffle
    case 'Restore order'                % obj.handles.ribbonHome.reshuffle
end
end
