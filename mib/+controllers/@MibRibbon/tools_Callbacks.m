function tools_Callbacks(obj, hWidget, hData)
% TOOLS_CALLBACKS - callback on press of buttons in the Tools ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.tools_Callbacks(hWidget, hData)
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
    fprintf('controllers.MibRibbon.tools_Callbacks: Tools ribbon -> pressed -> %s\n', mode);
end

switch mode
    case sprintf('Deep learning\nsegmentation')        % obj.handles.ribbonTools.deepmib
        obj.mibController.startController('controllers.MibDeep', obj.mibController);
    case 'Membrane detector'        % obj.handles.ribbonTools.membrane
        obj.mibController.startController('controllers.MembranePixClassifier');
    case 'Supervoxels classifier'        % obj.handles.ribbonTools.supervoxels
    case sprintf('Global\nthresholding')        % obj.handles.ribbonTools.globalthres
        obj.mibController.startController('controllers.GlobalThresholding');
    case 'Graphcut'        % obj.handles.ribbonTools.graphcut
        obj.mibController.startController('controllers.Graphcut');
    case {'Measure tool', sprintf('Measure\ntool')}   % obj.handles.ribbonTools.measureTool
        obj.mibController.measureLength('tool');        % measure tool starts from measureLength
    case 'Line measure'   % obj.handles.ribbonTools.measure or obj.handles.ribbonTools.measureLine
        obj.mibController.measureLength('line');
    case 'Free hand measure'                            % measureFreehand
        obj.mibController.measureLength('freehand');
    case sprintf('Object\nseparation')                  % obj.handles.ribbonTools.objects
        obj.mibController.startController('controllers.ObjectSeparator');
    case 'Stereology'                                   % obj.handles.ribbonTools.stereology
        obj.mibController.startController('controllers.Stereology');
    case sprintf('Wound healing\nassey')                % obj.handles.ribbonTools.wound
        obj.mibController.startController('controllers.WoundHealing');

end

end
