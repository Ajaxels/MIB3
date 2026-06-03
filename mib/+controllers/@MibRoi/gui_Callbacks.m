function gui_Callbacks(obj, hWidget, hData)
% GUI_CALLBACKS - callbacks for widgets of some the ROI panel obj.view.handles.panels.roi (obj.cRoi.gui).
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.gui_Callbacks(hWidget, hData)
%
% Input Arguments:
%   - **hWidget** — handle to the pressed widget
%   - **hData** — handle to supporting data class
%

% mode: char, optional identifier the widget, used when the same operation
% is called from menu, when empty or missing hWidget.Tag is used as an
% identifier
% 'roiOptions' -> define ROI visualization options
% 'roiList' -> list of active ROI
% 'roiLoad' -> load ROI from a file
% 'roiSave' -> save ROI to a file
% 'roiAdd' -> add ROI
% 'roiModify' -> modify ROI
% 'roiRemove' -> remove ROI from the list
% 'roiType' -> select type of ROI to add
% 'roiFixAspect' -> fix aspect ration when adding a ROI
% 'roiShowLabel' -> show the label with ROI name next to the ROI
% 'roiShowROI' -> show ROI in the Image View panel
% 'roiManually' -> enable manual ROI addition mode based on provided coordinates
% 'roiX1' -> define min-X value for addition of ROI
% 'roiY1' -> define min-Y value for addition of ROI
% 'roiWidth' -> define width of the added ROI
% 'roiHeight -> define height of the added ROI
% 'roiToSelection' -> highlight the ROI area using the selection layer

arguments (Input)
    obj controllers.MibRoi
    hWidget {mustBeA(hWidget, {'matlab.ui.control.Button', 'matlab.ui.control.CheckBox', 'matlab.ui.control.DropDown', 'matlab.ui.control.EditField', 'matlab.ui.control.ListBox', 'matlab.ui.control.Spinner'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData'})}
    %mode char = ''
end

% mode = '';
% if isempty(mode); mode = hWidget.Tag; end

mode = hWidget.Tag;

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRoi.gui_Callbacks: "obj.handles.%s"-> pressed/changed\n', mode);
end

dataset = obj.mibModel.I{obj.mibModel.id};
switch mode
    case 'roiOptions' % define ROI visualization options
        dataset.hROI.updateOptions(obj.mibController.view.gui);
        obj.mibController.showImage();
    case 'roiList' % list of active ROI
        % index into hROI.Data of the ROI to highlight; 0 -> show all ROIs
        % hWidget.ValueIndex==1 is the 'All' entry at the top of the list,
        % subtract 1 so that entry maps to selectedROI=0 (show all) and
        % entry 2 maps to selectedROI=1 (first ROI in Data), etc.
        dataset.selectedROI = hWidget.ValueIndex - 1;
        obj.mibController.showImage();
    case 'roiLoad' % load ROI from a file
        obj.roiLoad();
    case 'roiSave' % save ROI to a file
        obj.roiSave();
    case 'roiAdd' % add ROI
        obj.addROI();
    case 'roiModify' % modify the selected ROI
        obj.roiModify();
    case 'roiRemove' % remove ROI from the list
        obj.removeROI();
    case 'roiType' % select type of ROI to add
        %fprintf('controller.roiPanel_Callbacks: Clicked on a widget of the ROI panel (obj.handles.panels.roi): %s -> %s\n', mode, hWidget.Value);
    case 'roiFixAspect' % fix aspect ration when adding a ROI
        %fprintf('controller.roiPanel_Callbacks: Clicked on a widget of the ROI panel (obj.handles.panels.roi): %s -> %d\n', mode, hWidget.Value);
    case 'roiShowLabel' % show the label with ROI name next to the ROI
        obj.mibController.showImage();
    case 'roiShowROI' % show ROI in the Image View panel
        % see also obj.mibController.cQuickAccessBar.gui_Callbacks
        obj.mibModel.I{obj.mibModel.id}.roiShow = hWidget.Value;
        obj.mibController.cQuickAccessBar.handles.roiMode.Value = logical(hWidget.Value);
        obj.mibController.showImage();
    case 'roiManually' % enable manual ROI addition mode based on provided coordinates
        if obj.handles.roiManually.Value
            obj.handles.roiX1.Enable = 'on';
            obj.handles.roiY1.Enable = 'on';
            obj.handles.roiWidth.Enable = 'on';
            obj.handles.roiHeight.Enable = 'on';
        else
            obj.handles.roiX1.Enable = 'off';
            obj.handles.roiY1.Enable = 'off';
            obj.handles.roiWidth.Enable = 'off';
            obj.handles.roiHeight.Enable = 'off';
        end
        
        %fprintf('controller.roiPanel_Callbacks: Clicked on a widget of the ROI panel (obj.handles.panels.roi): %s -> %d\n', mode, hWidget.Value);
    case 'roiX1' % define min-X value for addition of ROI
        %fprintf('controller.roiPanel_Callbacks: Clicked on a widget of the ROI panel (obj.handles.panels.roi): %s -> %f\n', mode, hWidget.Value);
    case 'roiY1' % define min-Y value for addition of ROI
        %fprintf('controller.roiPanel_Callbacks: Clicked on a widget of the ROI panel (obj.handles.panels.roi): %s -> %f\n', mode, hWidget.Value);
    case 'roiWidth' % define width of the added ROI
        %fprintf('controller.roiPanel_Callbacks: Clicked on a widget of the ROI panel (obj.handles.panels.roi): %s -> %f\n', mode, hWidget.Value);
    case 'roiHeight' % define height of the added ROI
        %fprintf('controller.roiPanel_Callbacks: Clicked on a widget of the ROI panel (obj.handles.panels.roi): %s -> %f\n', mode, hWidget.Value);
    case 'roiToSelection' % highlight the ROI area using the selection layer
        obj.roiToSelection();
end

end
