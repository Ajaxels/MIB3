function loadMeasurements(obj)
% LOADMEASUREMENTS - Load measurements from a ``.measure`` file.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.loadMeasurements()
%
% Opens a file dialog, deserialises the ``measureData`` struct array from
% the selected MAT-file, and replaces the current measurements.
%
% Input Arguments:
%   - **obj** — :class:`controllers.MeasureTool`
%

[filename, pathname] = uigetfile( ...
    {'*.measure', 'Measurements (*.measure)'}, ...
    'Load measurements', obj.mibModel.myPath);
if isequal(filename, 0); return; end

loadedStruct = load(fullfile(pathname, filename), '-mat');
if ~isfield(loadedStruct, 'measureData')
    utils.dlgs.showErrorDialog(obj.view.gui, ...
        'The selected file does not contain a ''measureData'' variable.', ...
        'Load measurements');
    return;
end

datasetId = obj.mibModel.getActiveId();
hMeasure  = obj.mibModel.I{datasetId}.measure;

obj.mibModel.backup('measurements');
hMeasure.clearData();

for recordIdx = 1:numel(loadedStruct.measureData)
    hMeasure.storeMeasurement(loadedStruct.measureData(recordIdx));
end

obj.updateTable();
notify(obj.mibModel, 'ShowImage');
end
