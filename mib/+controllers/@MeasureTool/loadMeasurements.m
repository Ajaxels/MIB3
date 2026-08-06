function loadMeasurements(obj)
% LOADMEASUREMENTS - Load measurements from a ``.measure`` file.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.loadMeasurements()
%
% Opens a file dialog, deserialises the ``Data`` struct array from
% the selected MAT-file, and replaces the current measurements.
%
% Input Arguments:
%   - **obj** - :class:`controllers.MeasureTool`
%

datasetId = obj.mibModel.getActiveId();
[path, ~] = fileparts(obj.mibModel.I{datasetId}.image.filename);
[filename, pathname] = uigetfile( ...
    {'*.measure', 'Measurements (*.measure)'}, ...
    'Load measurements', path);
if isequal(filename, 0); return; end

loadedStruct = load(fullfile(pathname, filename), '-mat');
if ~isfield(loadedStruct, 'Data')
    utils.dlgs.showErrorDialog(obj.view.gui, ...
        'The selected file does not contain a ''Data'' variable.', ...
        'Load measurements');
    return;
end

hMeasure  = obj.mibModel.I{datasetId}.measure;
obj.mibModel.backup('measurements');
hMeasure.clearData();

for recordIdx = 1:numel(loadedStruct.Data)
    hMeasure.storeMeasurement(loadedStruct.Data(recordIdx));
end

obj.updateTable();
notify(obj.mibModel, 'ShowImage');
end
