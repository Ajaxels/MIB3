function gui_Callbacks(obj, hWidget, hData)
% GUI_CALLBACKS - Callback for general segmentation panel widgets.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.gui_Callbacks(hWidget, hData)
%
% Handles callbacks for general segmentation panel widgets including model creation/loading,
% material management, color scheme control, and visualization settings.
%
% Input Arguments:
%   - **hWidget** - [matlab.ui.control.Button | matlab.ui.control.CheckBox] pressed widget; operation identified via ``hWidget.Tag``:
%
%     - ``'createModel'`` - create a new segmentation model
%     - ``'loadModel'`` - load model from file
%     - ``'addMaterial'`` - add material to model
%     - ``'removeMaterial'`` - remove material from model
%     - ``'colorWheel'`` - generate random colors for materials; the random seed is
%       requested in a dialog, unless the button was clicked with Ctrl held down, in
%       which case the generator is seeded from the system clock without a dialog
%     - ``'viewSettings'`` - open visualization settings dialog for model/mask
%
%   - **hData** - [matlab.ui.eventdata.ButtonPushedData | matlab.ui.eventdata.ValueChangedData] event data from widget
%
% Output Arguments:
%   None

arguments (Input)
    obj controllers.MibSegmentation
    hWidget {mustBeA(hWidget, {'matlab.ui.control.Button', 'matlab.ui.control.CheckBox'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData'})}
end

mode = hWidget.Tag;

% read the modifier before utils.unFocus below: its drawnow yields to the event
% queue, after which the key release may already have cleared CurrentModifier
modifier = obj.UIFigure.CurrentModifier;
ctrlPressed = any(strcmp(modifier, 'control'));

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSegmentation.gui_Callbacks: clicked on "obj.view.handles.panels.segmentation.handles.%s"\n', mode);
end

% Ctrl+click on a widget that owns a context menu also raises that menu; toggling
% Enable of the widget (as utils.unFocus does) while the menu is up leaves it
% unresponsive to any further right clicks, so skip unfocusing in that case
if ~(ctrlPressed && ~isempty(hWidget.ContextMenu))
    utils.unFocus(hWidget);
end

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
        if ctrlPressed
            % Ctrl+click: regenerate the random colors right away, seeding the
            % generator from the system clock instead of asking for a seed
            obj.mibModel.setDefaultColorPalette('Random Colors', [], 'shuffle');
        else
            obj.mibModel.setDefaultColorPalette('Random Colors');
        end
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
