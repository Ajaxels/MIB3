function addMeasurement(obj)
% ADDMEASUREMENT - Handle the Add button: backup, draw, compute, store.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.addMeasurement()
%
% Reads measurement type and options from the view, calls the appropriate
% ``measureXxx`` method, then restores ``disableSegmentation`` and refreshes
% the table and image regardless of success or cancellation.
%
% Input Arguments:
%   - **obj** — :class:`controllers.MeasureTool`
%

datasetId = obj.mibModel.getActiveId();
obj.mibModel.backup('measurements');
obj.mibModel.disableSegmentation = true;

try
    % read options from view
    colCh         = obj.view.handles.imageColChDropdown.ValueIndex - 1;   % 0 = all channels; 1+ = specific channel
    finetuneCheck    = obj.view.handles.finetuneCheck.Value;
    calcIntensity    = obj.view.handles.calcIntensityCheck.Value;
    showInfoDlg      = obj.view.handles.showEditInfoDlg.Value;
    integrationWidth = obj.view.handles.integrationWidth.Value;
    measureType      = obj.view.handles.measureTypeDropdown.Value;

    measureSettings = obj.mibModel.sessionSettings.measureTool;

    switch measureType
        case 'Angle'
            infoDefault = false;
            if showInfoDlg; infoDefault = measureSettings.Angle.Info; end
            infoText = obj.measureAngle(datasetId, colCh, finetuneCheck, calcIntensity, infoDefault);
            if showInfoDlg && ischar(infoText)
                obj.mibModel.sessionSettings.measureTool.Angle.Info = infoText;
            end
        case 'Caliper'
            infoDefault = false;
            if showInfoDlg; infoDefault = measureSettings.Caliper.Info; end
            infoText = obj.measureCaliper(datasetId, colCh, finetuneCheck, calcIntensity, infoDefault);
            if showInfoDlg && ischar(infoText)
                obj.mibModel.sessionSettings.measureTool.Caliper.Info = infoText;
            end
        case 'Circle (R)'
            infoDefault = false;
            if showInfoDlg; infoDefault = measureSettings.Circle.Info; end
            infoText = obj.measureCircle(datasetId, colCh, finetuneCheck, calcIntensity, infoDefault);
            if showInfoDlg && ischar(infoText)
                obj.mibModel.sessionSettings.measureTool.Circle.Info = infoText;
            end
        case 'Distance (linear)'
            infoDefault = false;
            if showInfoDlg; infoDefault = measureSettings.Distance.Info; end
            infoText = obj.measureDistance(datasetId, colCh, finetuneCheck, integrationWidth, calcIntensity, infoDefault);
            if showInfoDlg && ischar(infoText)
                obj.mibModel.sessionSettings.measureTool.Distance.Info = infoText;
            end
        case 'Distance (polyline)'
            infoDefault = false;
            if showInfoDlg; infoDefault = measureSettings.DistancePoly.Info; end
            infoText = obj.measureDistancePoly(datasetId, colCh, finetuneCheck, calcIntensity, infoDefault);
            if showInfoDlg && ischar(infoText)
                obj.mibModel.sessionSettings.measureTool.DistancePoly.Info = infoText;
            end
        case 'Distance (freehand)'
            infoDefault = false;
            if showInfoDlg; infoDefault = measureSettings.DistanceFree.Info; end
            infoText = obj.measureDistanceFree(datasetId, colCh, finetuneCheck, calcIntensity, infoDefault);
            if showInfoDlg && ischar(infoText)
                obj.mibModel.sessionSettings.measureTool.DistanceFree.Info = infoText;
            end
        case 'Point'
            infoDefault = false;
            if showInfoDlg; infoDefault = measureSettings.Point.Info; end
            infoText = obj.measurePoint(datasetId, colCh, finetuneCheck, calcIntensity, infoDefault);
            if showInfoDlg && ischar(infoText)
                obj.mibModel.sessionSettings.measureTool.Point.Info = infoText;
            end
    end
catch measureError
    if ~strcmp(measureError.identifier, 'MeasureTool:Cancelled')
        utils.dlgs.showErrorDialog(obj.view.gui, measureError, 'MeasureTool.addMeasurement: Measurement error');
    end
end

obj.mibModel.disableSegmentation = false;
obj.updateTable();
nRows = size(obj.view.handles.measureTable.Data, 1);
if nRows > 0
    scroll(obj.view.handles.measureTable, 'row', nRows);
    obj.view.handles.measureTable.Selection = [nRows, 3];
    obj.indices = [nRows, 3];
end
notify(obj.mibModel, 'ShowImage');
end
