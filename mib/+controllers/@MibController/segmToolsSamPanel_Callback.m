function segmToolsSamPanel_Callback(obj, hWidget, hData, mode)
% segmToolsSamPanel_Callback(obj, hWidget, hData, mode)
% Callbacks for widgets in the Segmentation panel->SAM tool
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting data class
% mode: char, optional identifier the widget, used when the same operation
% is called from menu, when empty or missing hWidget.Tag is used as an identifier
% 'samMethod' -> method of SAM usage
% 'samV2' -> use SAM2 instead of SAM1
% 'samDataset' -> select type of dataset to apply SAM
% 'samDestination' -> destination layer for SAM results
% 'samMode' -> SAM mode, add/replace/subtract
% 'samSettings' -> open SAM settings dialog
% 'samList' -> show the list of points (annotations) for the landmark mode
% 'samClear' -> clear the annotation points
% 'samSegment' -> do SAM segmentation
%

arguments (Input)
    obj controllers.MibController
    hWidget {mustBeA(hWidget, {'matlab.ui.control.Button', 'matlab.ui.control.CheckBox', 'matlab.ui.control.DropDown'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData'})}
    mode char = ''
end

if isempty(mode); mode = hWidget.Tag; end

switch mode
    case 'samMethod' % method of SAM usage
        fprintf('Clicked on a widget of the segmentation panel->SAM tool (obj.handles.panels.segmentation): %s -> %s\n', mode, hWidget.Value);
    case 'samV2' % use SAM2 instead of SAM1
        fprintf('Clicked on a widget of the segmentation panel->SAM tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'samDataset' % select type of dataset to apply SAM
        fprintf('Clicked on a widget of the segmentation panel->SAM tool (obj.handles.panels.segmentation): %s -> %s\n', mode, hWidget.Value);
    case 'samDestination' % destination layer for SAM results
        fprintf('Clicked on a widget of the segmentation panel->SAM tool (obj.handles.panels.segmentation): %s -> %s\n', mode, hWidget.Value);
    case 'samMode' % SAM mode, add/replace/subtract
        fprintf('Clicked on a widget of the segmentation panel->SAM tool (obj.handles.panels.segmentation): %s -> %s\n', mode, hWidget.Value);
    case 'samSettings' % open SAM settings dialog
        fprintf('Clicked on a widget of the segmentation panel->SAM tool (obj.handles.panels.segmentation): %s\n', mode);
    case 'samList' % show the list of points (annotations) for the landmark mode
        fprintf('Clicked on a widget of the segmentation panel->SAM tool (obj.handles.panels.segmentation): %s\n', mode);
    case 'samClear' % clear the annotation points
        fprintf('Clicked on a widget of the segmentation panel->SAM tool (obj.handles.panels.segmentation): %s\n', mode);
    case 'samSegment' % do SAM segmentation
        fprintf('Clicked on a widget of the segmentation panel->SAM tool (obj.handles.panels.segmentation): %s\n', mode);
end

end
