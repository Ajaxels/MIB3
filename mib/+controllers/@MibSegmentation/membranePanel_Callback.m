function membranePanel_Callback(obj, hWidget, hData)
% membranePanel_Callback(obj, hWidget, hData)
% Callbacks for widgets in the Segmentation panel->Membrane click tracker tool
%
% Parameters:
% hWidget: handle to the pressed widget
% hWidget.Tag - identifier the widget, used when the same operation is called from menu
% 'membraneScale' -> scale parameter for membrane tracking
% 'membraneWidth' -> width of the membrane
% 'membraneStraightLine' -> generate straight line instead of tracking
% 'membraneBlackSignal' -> signal type: black-on-white / white-on-black signal
% 'membraneRecenterView' -> recenter the view after placing a point
%
% hData: handle to supporting data class

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
