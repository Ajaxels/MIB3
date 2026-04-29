function imageVisualization_Callbacks(obj, hWidget, hData)
% IMAGEVISUALIZATION_CALLBACKS - callback on press of the Visualization buttons in the Image ribbon.
%
% Syntax:
%   function imageVisualization_Callbacks(obj, hWidget, hData)
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
    fprintf('controllers.MibRibbon.imageVisualization_Callbacks: Image ribbon-> %s\n', mode);
end

switch mode
    case 'Visualization'        % obj.handles.ribbonImage.visualization
        obj.mibController.updateVisualizationMode();
    case 'Bicubic'              % obj.handles.ribbonImage.visBicubic
        obj.mibController.updateVisualizationMode('bicubic');
    case 'Nearest'              % obj.handles.ribbonImage.visNearest
        obj.mibController.updateVisualizationMode('nearest');
    case 'Automatic'            % obj.handles.ribbonImage.visAuto
        obj.mibController.updateVisualizationMode('auto');
end

end
