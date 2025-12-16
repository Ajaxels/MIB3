function imageVisualization_Callbacks(obj, hWidget, hData)
% function imageVisualization_Callbacks(obj, hWidget, hData)
% callback on press of the Visualization buttons in the Image ribbon
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
    fprintf('controllers.MibRibbon.imageVisualization_Callbacks: Image ribbon-> %s\n', mode);
end



end