function segmToolsLassoPanel_Callback(obj, hWidget, hData, mode)
% segmToolsLassoPanel_Callback(obj, hWidget, hData, mode)
% Callbacks for widgets in the Segmentation panel->Lasso/Object picker tools
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting data class
% mode: char, optional identifier the widget, used when the same operation
% is called from menu, when empty or missing hWidget.Tag is used as an identifier
% 'lassoType' -> define type of the lasso selection tool 
% 'lassoMode' -> set the mode add/remove lasso-selection to/from the selection layer
% 'lassoManually' -> specify the lasso area manually
% 'lassoSelect' -> select the specified area
% 'lassoX1' -> define min-X value for the manual lasso placement
% 'lassoY1' -> define min-Y value for the manual lasso placement
% 'lassoWidth' -> define width value for the manual lasso placement
% 'lassoHeight' -> define height value for the manual lasso placement
% 'objectRecalculate' -> recalculate object properties for 3D selection
% 'objectBrush' -> select objects with the brush tool
%

arguments (Input)
obj controllers.MibController
hWidget {mustBeA(hWidget, {'matlab.ui.control.Button', 'matlab.ui.control.CheckBox', 'matlab.ui.control.NumericEditField' 'matlab.ui.control.DropDown'})}
hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData'})}
mode char = ''
end

if isempty(mode); mode = hWidget.Tag; end

switch mode
    case 'lassoType' % define type of the lasso selection tool 
        fprintf('Clicked on a widget of the segmentation panel->Lasso/Object picker tool (obj.handles.panels.segmentation): %s -> %s\n', mode, hWidget.Value);
    case 'lassoMode' % set the mode add/remove lasso-selection to/from the selection layer
        fprintf('Clicked on a widget of the segmentation panel->Lasso/Object picker tool (obj.handles.panels.segmentation): %s -> %s\n', mode, hWidget.Value);
    case 'lassoManually' % specify the lasso area manually
        fprintf('Clicked on a widget of the segmentation panel->Lasso/Object picker tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'lassoSelect' % select the specified area
        fprintf('Clicked on a widget of the segmentation panel->Lasso/Object picker tool (obj.handles.panels.segmentation): %s\n', mode);
    case 'lassoX1' % define min-X value for the manual lasso placement
        fprintf('Clicked on a widget of the segmentation panel->Lasso/Object picker tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'lassoY1' % define min-X value for the manual lasso placement
        fprintf('Clicked on a widget of the segmentation panel->Lasso/Object picker tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'lassoWidth' % define width value for the manual lasso placement
        fprintf('Clicked on a widget of the segmentation panel->Lasso/Object picker tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'lassoHeight' % define height value for the manual lasso placement
        fprintf('Clicked on a widget of the segmentation panel->Lasso/Object picker tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'objectRecalculate' % recalculate object properties for 3D selection
        fprintf('Clicked on a widget of the segmentation panel->Lasso/Object picker tool (obj.handles.panels.segmentation): %s\n', mode);
    case 'objectBrush' % select objects with the brush tool
        fprintf('Clicked on a widget of the segmentation panel->Lasso/Object picker tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
end

end
