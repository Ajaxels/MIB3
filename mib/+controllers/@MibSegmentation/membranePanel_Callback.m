function membranePanel_Callback(obj, hWidget, hData)
% MEMBRANEPANEL_CALLBACK - Callback for membrane click tracker tool widgets.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.membranePanel_Callback(hWidget, hData)
%
% Handles callbacks for membrane click tracker segmentation tool widgets in the Segmentation panel.
% Supports tracking parameter configuration, signal type selection, and visualization control.
%
% Input Arguments:
%   - **hWidget** - [matlab.ui.control.CheckBox | matlab.ui.control.Spinner] pressed widget; operation identified via ``hWidget.Tag``:
%
%     - ``'membraneScale'`` - set scale parameter for membrane tracking sensitivity
%     - ``'membraneWidth'`` - set detected membrane thickness/width
%     - ``'membraneStraightLine'`` - enable/disable straight line mode (vs. tracked membrane)
%     - ``'membraneBlackSignal'`` - select signal type (black-on-white vs. white-on-black)
%     - ``'membraneRecenterView'`` - enable/disable automatic view recentering after point placement
%
%   - **hData** - [matlab.ui.eventdata.ValueChangedData] event data from widget
%
% Output Arguments:
%   None
%

arguments (Input)
    obj controllers.MibSegmentation
    hWidget {mustBeA(hWidget, {'matlab.ui.control.CheckBox', 'matlab.ui.control.Spinner'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData'})}
end

mode = hWidget.Tag;

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSegmentation.membranePanel_Callback: "obj.view.handles.panels.segmentation.handles.%s" -> changed/pressed\n', mode);
end

switch mode
    case 'membraneScale' % scale parameter for membrane tracking
        %fprintf('Clicked on a widget of the segmentation panel->Membrane click tracker tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'membraneWidth' % width of the membrane
        %fprintf('Clicked on a widget of the segmentation panel->Membrane click tracker tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'membraneStraightLine' % generate straight line instead of tracking
        %fprintf('Clicked on a widget of the segmentation panel->Membrane click tracker tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'membraneBlackSignal' % signal type: black-on-white / white-on-black signal
        %fprintf('Clicked on a widget of the segmentation panel->Membrane click tracker tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'membraneRecenterView' % recenter the view after placing a point
        %fprintf('Clicked on a widget of the segmentation panel->Membrane click tracker tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
end

end
