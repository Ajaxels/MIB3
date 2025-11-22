function gui_Callbacks(obj, hWidget, hData)
% function gui_Callbacks(obj, hWidget, hData)
% callbacks for widgets of some the ROI panel obj.view.handles.panels.roi (obj.cRoi.gui)
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting data class

% mode: char, optional identifier the widget, used when the same operation
% is called from menu, when empty or missing hWidget.Tag is used as an
% identifier
% 'roiOptions' -> define ROI visualization options
% 'roiList' -> list of active ROI
% 'roiLoad' -> load ROI from a file
% 'roiSave' -> save ROI to a file
% 'roiAdd' -> add ROI
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
    obj controllers.MibRoiController
    hWidget {mustBeA(hWidget, {'matlab.ui.control.Button', 'matlab.ui.control.CheckBox', 'matlab.ui.control.DropDown', 'matlab.ui.control.EditField', 'matlab.ui.control.ListBox', 'matlab.ui.control.Spinner'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData'})}
    %mode char = ''
end

mode = '';
if isempty(mode); mode = hWidget.Tag; end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRoiController.gui_Callbacks: "obj.handles.%s"-> pressed/changed\n', mode);
end


switch mode
    case 'roiOptions' % define ROI visualization options
        %fprintf('controller.roiPanel_Callbacks: Clicked on a widget of the ROI panel (obj.handles.panels.roi): %s\n', mode);
    case 'roiList' % list of active ROI
        %fprintf('controller.roiPanel_Callbacks: Clicked on a widget of the ROI panel (obj.handles.panels.roi): %s -> %s\n', mode, hWidget.Value);
    case 'roiLoad' % load ROI from a file
        %fprintf('controller.roiPanel_Callbacks: Clicked on a widget of the ROI panel (obj.handles.panels.roi): %s\n', mode);
    case 'roiSave' % save ROI to a file
        %fprintf('controller.roiPanel_Callbacks: Clicked on a widget of the ROI panel (obj.handles.panels.roi): %s\n', mode);
    case 'roiAdd' % add ROI
        %fprintf('controller.roiPanel_Callbacks: Clicked on a widget of the ROI panel (obj.handles.panels.roi): %s\n', mode);
    case 'roiRemove' % remove ROI from the list
        %fprintf('controller.roiPanel_Callbacks: Clicked on a widget of the ROI panel (obj.handles.panels.roi): %s\n', mode);
    case 'roiType' % select type of ROI to add
        %fprintf('controller.roiPanel_Callbacks: Clicked on a widget of the ROI panel (obj.handles.panels.roi): %s -> %s\n', mode, hWidget.Value);
    case 'roiFixAspect' % fix aspect ration when adding a ROI
        %fprintf('controller.roiPanel_Callbacks: Clicked on a widget of the ROI panel (obj.handles.panels.roi): %s -> %d\n', mode, hWidget.Value);
    case 'roiShowLabel' % show the label with ROI name next to the ROI
        %fprintf('controller.roiPanel_Callbacks: Clicked on a widget of the ROI panel (obj.handles.panels.roi): %s -> %d\n', mode, hWidget.Value);
    case 'roiShowROI' % show ROI in the Image View panel
        %fprintf('controller.roiPanel_Callbacks: Clicked on a widget of the ROI panel (obj.handles.panels.roi): %s -> %d\n', mode, hWidget.Value);
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
        %fprintf('controller.roiPanel_Callbacks: Clicked on a widget of the ROI panel (obj.handles.panels.roi): %s\n', mode);
end

end