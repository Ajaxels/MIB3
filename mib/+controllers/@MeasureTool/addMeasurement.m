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
obj.mibModel.disableSegmentation = 1;

try
    % read options from view
    colChItems    = obj.view.handles.imageColChPopup.Items;
    colChSelected = obj.view.handles.imageColChPopup.Value;
    colChIndex    = find(strcmp(colChItems, colChSelected), 1);
    colCh         = colChIndex - 1;   % 0 = all channels; 1+ = specific channel

    finetuneCheck    = obj.view.handles.finetuneCheck.Value;
    calcIntensity    = obj.view.handles.calcIntensityCheck.Value;
    showInfoDlg      = obj.view.handles.showEditInfoDlg.Value;
    integrationWidth = str2double(obj.view.handles.integrationWidth.Value);
    noPoints         = str2double(obj.view.handles.noPointsEdit.Value);
    measureType      = obj.view.handles.measureTypePopup.Value;

    switch measureType
        case 'Angle'
            obj.measureAngle(datasetId, colCh, finetuneCheck, calcIntensity, showInfoDlg);
        case 'Caliper'
            obj.measureCaliper(datasetId, colCh, finetuneCheck, calcIntensity, showInfoDlg);
        case 'Circle (R)'
            obj.measureCircle(datasetId, colCh, finetuneCheck, calcIntensity, showInfoDlg);
        case 'Distance (linear)'
            obj.measureDistance(datasetId, colCh, finetuneCheck, integrationWidth, calcIntensity);
        case 'Distance (polyline)'
            obj.measureDistancePoly(datasetId, colCh, noPoints, finetuneCheck, calcIntensity);
        case 'Distance (freehand)'
            obj.measureDistanceFree(datasetId, colCh, finetuneCheck, calcIntensity);
        case 'Point'
            obj.measurePoint(datasetId, colCh, finetuneCheck, calcIntensity, showInfoDlg);
    end
catch measureError
    if ~strcmp(measureError.identifier, 'MeasureTool:Cancelled')
        utils.dlgs.showErrorDialog(obj.view.gui, measureError.message, 'Measurement error');
    end
end

obj.mibModel.disableSegmentation = 0;
obj.updateTable();
notify(obj.mibModel, 'ShowImage');
end
