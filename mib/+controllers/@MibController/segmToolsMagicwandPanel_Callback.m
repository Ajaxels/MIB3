function segmToolsMagicwandPanel_Callback(obj, hWidget, hData, mode)
% segmToolsMagicwandPanel_Callback(obj, hWidget, hData, mode)
% Callbacks for widgets in the Segmentation panel->Magicwand tool
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting data class
% mode: char, optional identifier the widget, used when the same operation
% is called from menu, when empty or missing hWidget.Tag is used as an identifier
% 'magicMethod' -> select the MagicWand or RegionGrowing mode
% 'magicRange1' -> define the range 1 parameter
% 'magicRange2' -> define the range 2 parameter
% 'magicRadius' -> define effective radius for the MagicWand tool
% 'magicConnect' -> object connections for making magic wand mask
%


arguments (Input)
    obj controllers.MibController
    hWidget {mustBeA(hWidget, {'matlab.ui.control.Spinner', 'matlab.ui.container.ButtonGroup', 'matlab.ui.control.NumericEditField', 'matlab.ui.control.DropDown'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData', 'matlab.ui.eventdata.SelectionChangedData'})}
    mode char = ''
end

if isempty(mode); mode = hWidget.Tag; end

switch mode
    case 'magicMethod' % select the MagicWand or RegionGrowing mode 
        fprintf('Clicked on a widget of the segmentation panel->Magicwand tool (obj.handles.panels.segmentation): %s -> %s\n', mode, hWidget.Value);
    case 'magicRange1' % define the range 1 parameter
        fprintf('Clicked on a widget of the segmentation panel->Magicwand tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'magicRange2' % define the range 2 parameter
        fprintf('Clicked on a widget of the segmentation panel->Magicwand tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'magicRadius' % define effective radius for the MagicWand tool
        fprintf('Clicked on a widget of the segmentation panel->Magicwand tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'magicConnect' % object connections for making magic wand mask
        fprintf('Clicked on a widget of the segmentation panel->Magicwand tool (obj.handles.panels.segmentation): %s -> %s\n', mode, hWidget.SelectedObject.Text);
end

end


