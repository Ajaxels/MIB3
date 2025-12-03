function gui_Callbacks(obj, hWidget, hData)
% function gui_Callbacks(obj, hWidget, hData)
% callbacks for widgets of some the Segmentation panel obj.handles.panels.segmentation
%
% Parameters:
% hWidget: handle to the pressed widget
% hWidget.Tag, char, identifier the widget, used when the same operation
% 'createModel' -> create a new segmentation model
% 'loadModel' -> load model from a file
% 'addMaterial' -> add material to the model
% 'removeMaterial' -> remove material from the model
% 'colorWheel' -> restore default color scheme or generate random colors for 65535+ models
% 'viewSettings' -> view visualization settings for model/mask visualization

% hData: handle to supporting data class

arguments (Input)
    obj controllers.MibSegmentation
    hWidget {mustBeA(hWidget, {'matlab.ui.control.Button', 'matlab.ui.control.CheckBox'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData'})}
end

mode = hWidget.Tag;

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSegmentation.gui_Callbacks: clicked on "obj.view.handles.panels.segmentation.handles.%s"\n', mode);
end

switch mode
    case 'createModel'

    case 'loadModel'

    case 'addMaterial'

    case 'removeMaterial'

    case 'colorWheel'

    case 'viewSettings'
        prompts = {
            'Show Mask using contours:'
            };
        defAns = {
            obj.mibModel.preferences.Styles.Masks.ShowAsContours
            };
        dlgTitle = 'Visualization options';
        options.Header        = sprintf('Update visualization settings');
        options.HeaderLines   = 1;
        options.WindowStyle  = 'normal';
        options.WindowWidth = 300;
        options.WindowHeight = 110;
        options.IconWidth    = 64;
        options.Icon         = 'question';
        options.ParentFigure = obj.view.gui;
        [answer, selIndex, dontShow] = utils.dlgs.mibInputUniversalDlg(obj.mibController.mibPath, prompts, defAns, dlgTitle, options);
        if isempty(answer); return; end

        obj.mibModel.preferences.Styles.Masks.ShowAsContours = answer{1};  % show masks as contours, when false as filled shapes
        notify(obj.mibModel, 'RenderImage');
end

end
