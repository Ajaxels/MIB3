function toolsSegmentation_Callbacks(obj, hWidget, hData)
% TOOLSSEGMENTATION_CALLBACKS - callback on press of buttons in the Segmentation section of the Tools ribbon.
%
% Syntax:
%   function toolsSegmentation_Callbacks(obj, hWidget, hData)
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
    fprintf('controllers.MibRibbon.toolsSegmentation_Callbacks: Tools ribbon-> Segmentation section pressed -> %s\n', mode);
end

switch mode
    case sprintf('Deep learning\nsegmentation')        % obj.handles.ribbonTools.deepmib
        obj.mibController.startController('controllers.MibDeep', obj.mibController);
    case 'Membrane detector'        % obj.handles.ribbonTools.membrane
    case 'Supervoxels classifier'        % obj.handles.ribbonTools.supervoxels
    case sprintf('Global\nthresholding')        % obj.handles.ribbonTools.globalthres
    case 'Graphcut'        % obj.handles.ribbonTools.graphcut
    case 'Watershed'        % obj.handles.ribbonTools.watershed

end

end
