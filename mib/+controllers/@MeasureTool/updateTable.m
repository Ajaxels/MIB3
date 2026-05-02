function updateTable(obj)
% UPDATETABLE - Rebuild the measurements table from the current dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.updateTable()
%
% Reads ``hMeasure.Data`` for the active dataset, applies the type filter
% selected in ``filterPopup``, and writes a 6-column cell array into
% ``measureTable.Data`` (columns: n, type, value, info, Z, T).
%
% Input Arguments:
%   - **obj** — :class:`controllers.MeasureTool`
%

datasetId   = obj.mibModel.getActiveId();
hMeasure    = obj.mibModel.I{datasetId}.measure;
filterValue = obj.view.handles.filterPopup.Value;

% keep the data-class filter in sync
hMeasure.typeToShow = filterValue;

totalMeasurements = hMeasure.getNumberOfMeasurements();
if totalMeasurements == 0
    obj.view.handles.measureTable.Data = {};
    return;
end

% Build full 6-column table then filter rows
tableData = cell(totalMeasurements, 6);
for rowIdx = 1:totalMeasurements
    tableData{rowIdx, 1} = hMeasure.Data(rowIdx).n;
    tableData{rowIdx, 2} = hMeasure.Data(rowIdx).type;
    tableData{rowIdx, 3} = hMeasure.Data(rowIdx).value;
    tableData{rowIdx, 4} = hMeasure.Data(rowIdx).info;
    tableData{rowIdx, 5} = hMeasure.Data(rowIdx).Z;
    tableData{rowIdx, 6} = hMeasure.Data(rowIdx).T;
end

if ~strcmp(filterValue, 'All')
    typeFlags = strcmp({hMeasure.Data(1:totalMeasurements).type}, filterValue);
    tableData = tableData(typeFlags, :);
end

obj.view.handles.measureTable.Data = tableData;
end
