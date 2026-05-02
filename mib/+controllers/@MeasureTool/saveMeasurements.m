function saveMeasurements(obj)
% SAVEMEASUREMENTS - Save current measurements to a ``.measure`` file.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.saveMeasurements()
%
% Opens a save-file dialog and serialises ``hMeasure.Data`` into a
% MAT-file with the variable name ``measureData``.
%
% Input Arguments:
%   - **obj** — :class:`controllers.MeasureTool`
%

datasetId = obj.mibModel.getActiveId();
hMeasure  = obj.mibModel.I{datasetId}.measure;

if hMeasure.getNumberOfMeasurements() == 0
    utils.dlgs.showErrorDialog(obj.view.gui, 'No measurements to save.', 'Save measurements');
    return;
end

[filename, pathname] = uiputfile( ...
    {'*.measure', 'Measurements (*.measure)'}, ...
    'Save measurements', obj.mibModel.myPath);
if isequal(filename, 0); return; end

measureData = hMeasure.Data;
save(fullfile(pathname, filename), 'measureData', '-mat');
end
