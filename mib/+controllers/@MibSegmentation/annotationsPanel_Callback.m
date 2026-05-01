function annotationsPanel_Callback(obj, hWidget, hData)
% ANNOTATIONSPANEL_CALLBACK - Callback for annotations tool widgets.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.annotationsPanel_Callback(hWidget, hData)
%
% Handles callbacks for annotations segmentation tool widgets in the Segmentation panel.
% Supports annotation list management, visualization options, and precision control.
%
% Input Arguments:
%   - **hWidget** — [matlab.ui.control.Button | matlab.ui.control.CheckBox | matlab.ui.control.Spinner | matlab.ui.control.DropDown] pressed widget; operation identified via ``hWidget.Tag``:
%
%     - ``'annAnnotationList'`` — open annotation list management window
%     - ``'annShowPrompt'`` — show/hide prompt when adding new annotations
%     - ``'annFocusOnValue'`` — focus on value field when showing prompt
%     - ``'annPrecision'`` — set floating-point precision for annotation values
%     - ``'annDeleteAll'`` — delete all annotations from dataset
%     - ``'annDisplayAs'`` — select annotation visualization mode
%
%   - **hData** — [matlab.ui.eventdata.ButtonPushedData | matlab.ui.eventdata.ValueChangedData] event data from widget
%
% Output Arguments:
%   None
%

arguments (Input)
    obj controllers.MibSegmentation
    hWidget {mustBeA(hWidget, {'matlab.ui.control.Button', 'matlab.ui.control.CheckBox', 'matlab.ui.control.Spinner', 'matlab.ui.control.DropDown'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData'})}
end

mode = hWidget.Tag;

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSegmentation.annotationsPanel_Callback: "obj.view.handles.panels.segmentation.handles.%s" -> changed/pressed\n', mode);
end

switch mode
    case 'annAnnotationList' % open another window with the annotation list
        obj.mibController.startController('controllers.Annotations');
    case 'annShowPrompt' % show the annotation prompt when adding a new annotation

    case 'annFocusOnValue' % when showing the prompt focus on the value field
        obj.mibModel.preferences.SegmTools.Annotations.FocusOnValue = obj.view.handles.panels.segmentation.handles.annFocusOnValue.Value;
        notify(obj.mibModel, 'ShowImage');
    case 'annPrecision' % define floating value precision for the annotation value
        obj.mibModel.preferences.SegmTools.Annotations.Precision = obj.view.handles.panels.segmentation.handles.annPrecision.Value;
        notify(obj.mibModel, 'ShowImage');
    case 'annDeleteAll' % delete all annotations
        obj.mibModel.deleteAnnotations();

    case 'annDisplayAs' % define how annotations should be visualized
        obj.mibModel.preferences.SegmTools.Annotations.DisplayAs = obj.view.handles.panels.segmentation.handles.annDisplayAs.Value;
        notify(obj.mibModel, 'ShowImage');
end

end
