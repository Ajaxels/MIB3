function modelAnnotations_Callback(obj, hWidget, hData)
% function modelAnnotations_Callback(obj, hWidget, hData)
% callback on press of buttons in the List of annotations button of the Model ribbon
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
    fprintf('controllers.MibRibbon.modelAnnotations_Callback: Model ribbon->Annotations -> %s\n', mode);
end

switch mode
    case {sprintf('List of\nannotations'), 'List of annotations'}      % obj.handles.ribbonModel.annotations or obj.handles.ribbonModel.annotationsList
    case 'Export to Imaris as Spots'    % obj.handles.ribbonModel.annotationsImaris
    case 'Remove all annotations'    % obj.handles.ribbonModel.annotationsRemove
end

end