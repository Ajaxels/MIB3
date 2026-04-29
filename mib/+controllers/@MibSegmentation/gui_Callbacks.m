function gui_Callbacks(obj, hWidget, hData)
% GUI_CALLBACKS - callbacks for widgets of some the Segmentation panel obj.handles.panels.segmentation.
%
% Syntax:
%   function gui_Callbacks(obj, hWidget, hData)
%
% Input Arguments:
%   - **hWidget** — handle to the pressed widget
%     hWidget.Tag, char, identifier the widget, used when the same operation
%     'createModel' create a new segmentation model
%     'loadModel' load model from a file
%     'addMaterial' add material to the model
%     'removeMaterial' remove material from the model
%     'colorWheel' restore default color scheme or generate random colors for 65535+ models
%     'viewSettings' view visualization settings for model/mask visualization
%

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

utils.unFocus(hWidget);

switch mode
    case 'createModel'
        obj.mibModel.createModel();
    case 'loadModel'
        obj.mibModel.loadModel();
    case 'addMaterial'
        if ~obj.mibModel.I{obj.mibModel.getActiveId()}.modelExist
            obj.mibModel.createModel();
        end
        obj.mibModel.addMaterial();
    case 'removeMaterial'
        obj.mibModel.removeMaterial();
    case 'colorWheel'

    case 'viewSettings'
        prompts = {'Show Labels using contours:'; 'Show Mask using contours:'};
        defAns = {
            obj.mibModel.preferences.Styles.Labels.ShowAsContours;
            obj.mibModel.preferences.Styles.Masks.ShowAsContours;
            };
        dlgTitle = 'Visualization options';
        header        = sprintf('Update visualization settings');
        options.HeaderLines   = 1;
        options.WindowStyle  = 'normal';
        options.WindowWidth = 350;
        %options.WindowHeight = 180;
        options.IconWidth    = 64;
        options.LabelPosition = 'left';
        options.Icon         = 'question';
        options.mibPath = obj.mibController.mibPath;
        [answer, selIndex, dontShow] = utils.dlgs.inputUniversalDlg(obj.view.gui, header, prompts, defAns, dlgTitle, options);
        if isempty(answer); return; end

        obj.mibModel.preferences.Styles.Labels.ShowAsContours = answer{1};  % show labels as contours, when false as filled shapes
        obj.mibModel.preferences.Styles.Masks.ShowAsContours = answer{2};  % show masks as contours, when false as filled shapes
        notify(obj.mibModel, 'ShowImage');
end

end
