function magicwandPanel_Callback(obj, hWidget, hData)
% magicwandPanel_Callback(obj, hWidget, hData)
% Callbacks for widgets in the Segmentation panel->Magicwand tool
%
% Parameters:
% hWidget: handle to the pressed widget
% hWidget.Tag - identifier the widget, used when the same operation is called from menu
% 'magicMethod' -> select the MagicWand or RegionGrowing mode
% 'magicRange1' -> define the range 1 parameter
% 'magicRange2' -> define the range 2 parameter
% 'magicRadius' -> define effective radius for the MagicWand tool
% 'magicConnect' -> object connections for making magic wand mask
%
% hData: handle to supporting data class

arguments (Input)
    obj controllers.MibSegmentation
    hWidget {mustBeA(hWidget, {'matlab.ui.control.Spinner', 'matlab.ui.container.ButtonGroup', 'matlab.ui.control.NumericEditField', 'matlab.ui.control.DropDown'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData', 'matlab.ui.eventdata.SelectionChangedData'})}
end

mode = hWidget.Tag;

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSegmentation.magicwandPanel_Callback: "obj.view.handles.panels.segmentation.handles.%s" -> changed/pressed\n', mode);
end

switch mode
    case 'magicMethod' % select the MagicWand or RegionGrowing mode
        %fprintf('Clicked on a widget of the segmentation panel->Magicwand tool (obj.handles.panels.segmentation): %s -> %s\n', mode, hWidget.Value);
        if strcmp(hWidget.Value, 'Magic Wand')
            obj.handles.magicRange2.Enable = true;
        else
            obj.handles.magicRange2.Enable = false;
        end
    case 'magicRange1' % define the range 1 parameter
        %fprintf('Clicked on a widget of the segmentation panel->Magicwand tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'magicRange2' % define the range 2 parameter
        %fprintf('Clicked on a widget of the segmentation panel->Magicwand tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'magicRadius' % define effective radius for the MagicWand tool
        %fprintf('Clicked on a widget of the segmentation panel->Magicwand tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'magicConnect' % object connections for making magic wand mask
        %fprintf('Clicked on a widget of the segmentation panel->Magicwand tool (obj.handles.panels.segmentation): %s -> %s\n', mode, hWidget.SelectedObject.Text);
end

end


