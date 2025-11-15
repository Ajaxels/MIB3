function segmToolsAnnotationsPanel_Callback(obj, hWidget, hData, mode)
% segmToolsAnnotationsPanel_Callback(obj, hWidget, hData, mode)
% Callbacks for widgets in the Segmentation panel->Annotations tool
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting data class
% mode: char, optional identifier the widget, used when the same operation
% is called from menu, when empty or missing hWidget.Tag is used as an identifier
% 'annAnnotationList' -> open another window with the annotation list 
% 'annShowPrompt' -> show the annotation prompt when adding a new annotation
% 'annFocusOnValue' -> when showing the prompt focus on the value field
% 'annPrecision' -> define floating value precision for the annotation value  
% 'annDeleteAll' -> delete all annotations
% 'annDisplayAs' -> define how annotations should be visualized

arguments (Input)
    obj controllers.MibController
    hWidget {mustBeA(hWidget, {'matlab.ui.control.Button', 'matlab.ui.control.CheckBox', 'matlab.ui.control.Spinner', 'matlab.ui.control.DropDown'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData'})}
    mode char = ''
end

if isempty(mode); mode = hWidget.Tag; end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibController.segmToolsAnnotationsPanel_Callback: "obj.view.handles.panels.segmentation.handles.%s" -> changed/pressed\n', mode);
end

switch mode
    case 'annAnnotationList' % open another window with the annotation list 
        
    case 'annShowPrompt' % show the annotation prompt when adding a new annotation
        
    case 'annFocusOnValue' % when showing the prompt focus on the value field
        
    case 'annPrecision' % define floating value precision for the annotation value
        
    case 'annDeleteAll' % delete all annotations
        
    case 'annDisplayAs' % define how annotations should be visualized
        
end

end
