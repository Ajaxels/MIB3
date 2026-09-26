function editMeasurement(obj, datasetId, measurementIndex, colCh, integrationWidth, finetuneCheck, calcIntensity, useFixedZT)
% EDITMEASUREMENT - Re-edit an existing measurement at a given index.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.editMeasurement(datasetId, measurementIndex, colCh, integrationWidth, finetuneCheck, calcIntensity, useFixedZT)
%
% Backs up, re-runs the interactive drawing for the same measurement type,
% and replaces the old entry at ``measurementIndex`` with the new result.
% When ``useFixedZT`` is true the new record keeps the original Z/T values
% (Recalculate mode); when false the current slice/time is used (Modify mode).
%
% The replace-at-index pattern is: ``removeMeasurement(idx)`` then
% ``storeMeasurement(newData, idx)``.  Each ``measureXxx`` method accepts
% an ``insertIndex`` argument that implements this automatically.
%
% Input Arguments:
%   - **datasetId** - [double] index into ``mibModel.I``
%   - **measurementIndex** - [double] 1-based row in ``hMeasure.Data``
%   - **colCh** - [double] colour channel
%   - **integrationWidth** - [double] integration width for linear distance
%   - **finetuneCheck** - [logical] allow interactive ROI adjustment
%   - **calcIntensity** - [logical] recalculate intensity profile
%   - **useFixedZT** - [logical] preserve original Z/T (true = Recalculate)
%

hMeasure     = obj.mibModel.I{datasetId}.measure;
if measurementIndex > hMeasure.getNumberOfMeasurements(); return; end

measureType = hMeasure.Data(measurementIndex).type;

% when recalculating, navigate to the measurement's slice first
if useFixedZT
    obj.mibModel.I{datasetId}.slices{3} = [hMeasure.Data(measurementIndex).Z, hMeasure.Data(measurementIndex).Z];
    obj.mibModel.I{datasetId}.slices{5} = [hMeasure.Data(measurementIndex).T, hMeasure.Data(measurementIndex).T];
    notify(obj.mibModel, 'SliceChanged');
end

obj.mibModel.backup('measurements');
obj.mibModel.disableSegmentation = true;

try
    switch measureType
        case 'Angle'
            obj.measureAngle(datasetId, colCh, finetuneCheck, calcIntensity, false, measurementIndex);
        case 'Caliper'
            obj.measureCaliper(datasetId, colCh, finetuneCheck, calcIntensity, false, measurementIndex);
        case 'Circle (R)'
            obj.measureCircle(datasetId, colCh, finetuneCheck, calcIntensity, false, measurementIndex);
        case 'Distance (linear)'
            obj.measureDistance(datasetId, colCh, finetuneCheck, integrationWidth, calcIntensity, false, measurementIndex);
        case 'Distance (polyline)'
            obj.measureDistancePoly(datasetId, colCh, finetuneCheck, calcIntensity, false, measurementIndex);
        case 'Distance (freehand)'
            obj.measureDistanceFree(datasetId, colCh, finetuneCheck, calcIntensity, false, measurementIndex);
        case 'Point'
            obj.measurePoint(datasetId, colCh, finetuneCheck, calcIntensity, false, measurementIndex);
    end
catch measureError
    if ~strcmp(measureError.identifier, 'MeasureTool:Cancelled')
        utils.dlgs.showErrorDialog(obj.view.gui, measureError, 'MeasureTool.editMeasurement: Measurement error');
    end
end

obj.mibModel.disableSegmentation = false;
obj.updateTable();
notify(obj.mibModel, 'ShowImage');
end
