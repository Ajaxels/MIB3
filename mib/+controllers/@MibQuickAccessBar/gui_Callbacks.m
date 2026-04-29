function gui_Callbacks(obj, hWidget, hData)
% GUI_CALLBACKS - callbacks for widgets of the quick access bar of MIB.
%
% Syntax:
%   function gui_Callbacks(obj, hWidget, hData)
%
% Input Arguments:
%   - **hWidget** — handle to the pressed widget
%     hWidget.tag char, identifier the widget, used when the same operation
%     is called from menu
%     '' ->
%
%   - **hData** — handle to supporting data class
%

arguments (Input)
    obj controllers.MibQuickAccessBar
    hWidget matlab.ui.internal.toolstrip.base.Action
    hData {mustBeA(hData, {'matlab.ui.internal.toolstrip.base.ToolstripEventData'})}
end

mode = hWidget.Description;

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibQuickAccessBar.gui_Callbacks: "obj.view.handles.qab.handles->%s" -> changed/pressed\n', mode);
end

switch mode
    case 'Open MIB documentation'
    case 'Make a snapshot'
    case 'Save model to a file'
    case 'Enable the blocked mode to process only visible portion of the dataset'
         obj.mibModel.I{obj.mibModel.id}.blockModeSwitch = hWidget.Selected;
    case 'Enable the ROI mode'
        % see also obj.mibController.cRoi.gui_Callbacks
        obj.mibModel.I{obj.mibModel.id}.roiShow = hWidget.Selected;
        obj.mibController.cRoi.handles.roiShowROI.Value = hWidget.Selected;
        obj.mibController.showImage();
    case 'Enable the center marker'  % obj.view.handles.qab.target
        % Create or show the center marker
        axesHandle = obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.handles.imViewAxes;
        if isempty(obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.centralMarker) || ...
                ~isvalid(obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.centralMarker)
            centerX = mean(axesHandle.XLim);
            centerY = mean(axesHandle.YLim);
            obj.createCentralMarker(centerX, centerY);
        end
        if hWidget.Selected
            obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.centralMarker.Visible = true;
        else
            obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.centralMarker.Visible = false;
        end
    case 'Perform a quick measurement'
        obj.mibController.measureLength('line');
    case 'Switch dataset to the XZ orientation'
        obj.orientationChange(hWidget);
    case 'Switch dataset to the YZ orientation'
        obj.orientationChange(hWidget);
    case 'Switch dataset to the YX orientation'
        obj.orientationChange(hWidget);
    case 'Enable the fast-panning mode for quicker image navigation'
        obj.mibController.fastPanningMode = hWidget.Selected;
    case 'Zoom out'
        BatchOpt.Mode = 'Zoom out';
        obj.mibController.cStatus.zoomEdit_Callback([], BatchOpt);
    case 'Fit the dataset into the viewing window'
        BatchOpt.Mode = 'Fit to screen';
        obj.mibController.cStatus.zoomEdit_Callback([], BatchOpt);
    case 'Scale the image to 100% magnification'
        BatchOpt.Mode = '100%';
        obj.mibController.cStatus.zoomEdit_Callback([], BatchOpt);
    case 'Zoom in'
        BatchOpt.Mode = 'Zoom in';
        obj.mibController.cStatus.zoomEdit_Callback([], BatchOpt);
    case 'Redo the undo operation'
        index = obj.mibModel.Backup.undoIndex + 1;
        if index > numel(obj.mibModel.Backup.undoList); return; end
        obj.mibModel.undo(index);

    case 'Undo the last operation'
        index = obj.mibModel.Backup.undoIndex - 1;
        if index == 0; return; end
        obj.mibModel.undo(index);
end
