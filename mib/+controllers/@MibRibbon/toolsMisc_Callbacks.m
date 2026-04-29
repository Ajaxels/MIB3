function toolsMisc_Callbacks(obj, hWidget, hData)
% TOOLSMISC_CALLBACKS - callback on press of buttons in the Misc section of the Tools ribbon.
%
% Syntax:
%   function toolsMisc_Callbacks(obj, hWidget, hData)
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
    fprintf('controllers.MibRibbon.toolsMisc_Callbacks: Tools ribbon-> Misc section pressed -> %s\n', mode);
end

switch mode
    case {sprintf('Measure\nlength'), 'Line measure'}   % obj.handles.ribbonTools.measure or obj.handles.ribbonTools.measureLine
        obj.mibController.measureLength('line');
    case 'Measure tool'                                 % obj.handles.ribbonTools.measureTool
        obj.mibController.measureLength('tool');
    case 'Free hand measure'                            % measureFreehand
        obj.mibController.measureLength('freehand');
    case sprintf('Object\nseparation')                  % obj.handles.ribbonTools.objects
    case 'Stereology'                                   % obj.handles.ribbonTools.stereology
    case sprintf('Wound healing\nassey')                % obj.handles.ribbonTools.wound
end

end
