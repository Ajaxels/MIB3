function homeExamples_Callback(obj, hWidget, hData)
% function homeExamples_Callback(obj, hWidget, hData)
% callback on press of the Examples buttons in the Home ribbon
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
    fprintf('controllers.MibRibbon.homeExamples_Callback: example dataset pressed -> %s\n', mode);
end

switch mode
    case '2D large spots synthetic (62 Mb)'     % obj.handles.ribbonHome.deepmib2dLargeSpots
    case '2D small spots synthetic (8 Mb)'      % obj.handles.ribbonHome.deepmib2dSmallSpots
    case '2.5D large spots synthetic (121 Mb)'  % obj.handles.ribbonHome.deepmib25dLargeSpots
    case '2D patch-wise synthetic (42 Mb)'      % obj.handles.ribbonHome.deepmib2dPatchWise
    case '2D EM Membranes (219 Mb)'             % obj.handles.ribbonHome.deepmib2dMembranesEM
    case '2D LM Nuclei (174 Mb)'                % obj.handles.ribbonHome.deepmib2dNucleiLM
    case '3D EM Mitochondria (256 Mb)'          % obj.handles.ribbonHome.deepmib3dMitoEM
    case '3D LM hair cells (138 Mb)'            % obj.handles.ribbonHome.deepmib3dHairCellsLM
    case '3D SIM ER (21 Mb)'                    % obj.handles.ribbonHome.lm3dsimER
    case '3D STED (27 Mb)'                      % obj.handles.ribbonHome.lm3dsted
    case 'Widefield ER Photobleaching (21 Mb)'  % obj.handles.ribbonHome.lmWFbleaching
    case 'Huh-7 and model (29 Mb)'              % obj.handles.ribbonHome.sbfsemHuh7
    case 'Trypanosoma and model (247 Mb)'       % obj.handles.ribbonHome.sbfsemTrypanosoma
    case 'MATLAB Brain and model (3 Mb)'        % obj.handles.ribbonHome.mriBrain
end

end