function contextMenu(obj, parameter)
% CONTEXTMENU - Handle right-click context menu actions on the measurements table.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.contextMenu(parameter)
%
% Input Arguments:
%   - **obj** - :class:`controllers.MeasureTool`
%   - **parameter** - [char] action key:
%
%     - ``'ModifyInfo'``   - edit the ``.info`` annotation text
%     - ``'Jump'``         - navigate to the measurement's Z/T slice
%     - ``'Modify'``       - re-draw measurement on current slice
%     - ``'Recalculate'``  - re-draw on the stored slice (preserves Z/T)
%     - ``'Duplicate'``    - append a copy of the selected measurement
%     - ``'Kymograph'``    - generate kymograph from this measurement
%     - ``'Plot'``         - plot intensity profile in a standalone figure
%     - ``'Delete'``       - remove this measurement
%

if isempty(obj.indices); return; end

datasetId  = obj.mibModel.getActiveId();
hMeasure   = obj.mibModel.I{datasetId}.measure;

if hMeasure.getNumberOfMeasurements() == 0; return; end

% selectedRow is the table row (may differ from hMeasure index when filter is on)
selectedTableRow = obj.indices(1, 1);

% map table row → actual Data index (accounting for type filter)
filterValue = obj.view.handles.filterPopup.Value;
if strcmp(filterValue, 'All')
    dataIndex = selectedTableRow;
else
    typeFlags  = strcmp({hMeasure.Data(1:hMeasure.getNumberOfMeasurements()).type}, filterValue);
    filteredIndices = find(typeFlags);
    if selectedTableRow > numel(filteredIndices); return; end
    dataIndex = filteredIndices(selectedTableRow);
end

if dataIndex > hMeasure.getNumberOfMeasurements(); return; end

% resolve colour channel from popup
colChItems    = obj.view.handles.imageColChDropdown.Items;
colChSelected = obj.view.handles.imageColChDropdown.Value;
colChIndex    = find(strcmp(colChItems, colChSelected), 1);
colCh         = colChIndex - 1;

integrationWidth = str2double(obj.view.handles.integrationWidth.Value);
calcIntensity    = obj.view.handles.calcIntensityCheck.Value;

switch parameter
    case 'ModifyInfo'
        currentInfo = hMeasure.Data(dataIndex).info;
        dlgAnswer   = utils.dlgs.inputSingleDlg(obj.view.gui, 'Info:', currentInfo, 'Edit annotation');
        if isempty(dlgAnswer); return; end
        hMeasure.Data(dataIndex).info = dlgAnswer;
        obj.updateTable();

    case 'Jump'
        obj.mibModel.I{datasetId}.slices{3} = repmat(hMeasure.Data(dataIndex).Z, 1, 2);
        obj.mibModel.I{datasetId}.slices{5} = repmat(hMeasure.Data(dataIndex).T, 1, 2);
        notify(obj.mibModel, 'SliceChanged');

    case 'Modify'
        obj.editMeasurement(datasetId, dataIndex, colCh, integrationWidth, true, calcIntensity, false);

    case 'Recalculate'
        allSelectedRows = unique(obj.indices(:, 1));
        if strcmp(filterValue, 'All')
            allDataIndices = allSelectedRows;
        else
            typeFlags      = strcmp({hMeasure.Data(1:hMeasure.getNumberOfMeasurements()).type}, filterValue);
            filteredIndices = find(typeFlags);
            validMask      = allSelectedRows <= numel(filteredIndices);
            allDataIndices = filteredIndices(allSelectedRows(validMask));
        end
        allDataIndices = allDataIndices(allDataIndices <= hMeasure.getNumberOfMeasurements());
        if isempty(allDataIndices); return; end
        progressBar = core.PoolWaitbar(numel(allDataIndices), 'Recalculating...', ...
            obj.view.gui, 'Recalculate measurements', true);
        for recalcIdx = 1:numel(allDataIndices)
            if progressBar.getCancelState(); break; end
            obj.editMeasurement(datasetId, allDataIndices(recalcIdx), colCh, integrationWidth, false, calcIntensity, true);
            progressBar.increment();
        end
        progressBar.deletePoolWaitbar();

    case 'Duplicate'
        obj.mibModel.backup('measurements');
        duplicateData = hMeasure.Data(dataIndex);
        hMeasure.storeMeasurement(duplicateData);
        obj.updateTable();
        notify(obj.mibModel, 'ShowImage');

    case 'Kymograph'
        obj.generateKymograph(datasetId, dataIndex);

    case 'Plot'
        obj.plotIntensityProfile(dataIndex);

    case 'Delete'
        obj.mibModel.backup('measurements');
        hMeasure.removeMeasurement(dataIndex);
        obj.indices = [];
        obj.updateTable();
        notify(obj.mibModel, 'ShowImage');
end
end
