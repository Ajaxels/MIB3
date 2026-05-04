function gui_Callbacks(obj, source, event)
% GUI_CALLBACKS - Dispatcher for all MeasureTool widget callbacks.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.gui_Callbacks(source, event)
%
% Routes by ``source.Tag`` to the appropriate action.
%
% Input Arguments:
%   - **obj** — :class:`controllers.MeasureTool`
%   - **source** — widget handle that fired the event
%   - **event** — event data (ignored for most widgets; used for table selection)
%

datasetId = obj.mibModel.getActiveId();
hMeasure  = obj.mibModel.I{datasetId}.measure;
hHandles = obj.view.handles;

switch source.Tag
    case 'addBtn'
        obj.addMeasurement();

    case 'measureTypeDropdown'
        typeString = hHandles.measureTypeDropdown.Value;
        hHandles.interpolationModePopup.Enable = 'off';
        hHandles.integrateCheck.Enable = 'off';
        hHandles.integrateCheck.Value = false;
        hHandles.previewIntensityCheck.Enable = 'off';
        hHandles.autoPointSpacing.Enable = 'off';

        switch typeString
            case 'Distance (linear)'
                hHandles.integrateCheck.Enable = 'on';
                hHandles.previewIntensityCheck.Enable = 'on';
            case 'Distance (polyline)'
                hHandles.interpolationModePopup.Enable = 'on';
            case 'Distance (freehand)'
                hHandles.interpolationModePopup.Enable = 'on';
                hHandles.autoPointSpacing.Enable = 'on';
        end
        if hHandles.integrateCheck.Value == 1
            hHandles.handles.integrationWidth.Enable = 'on';
        else
            hHandles.handles.integrationWidth.Enable = 'off';
        end

    case 'integrateCheck'
        if hHandles.integrateCheck.Value == 1
            hHandles.integrationWidth.Enable = 'on';
        else
            hHandles.integrationWidth.Enable = 'off';
        end

    case 'interpolationModePopup'
        hMeasure.Options.splinemethod = source.Value;

    case {'markersCheck', 'linesCheck', 'textCheck'}
        obj.updatePlotSettings();

    case 'optionsBtn'
        hMeasure.updateOptions(obj.view.gui);
        hHandles.markersCheck.Value = logical(hMeasure.Options.showMarkers);
        hHandles.linesCheck.Value   = logical(hMeasure.Options.showLines);
        hHandles.textCheck.Value    = logical(hMeasure.Options.showText);
        notify(obj.mibModel, 'ShowImage');

    case 'deleteAllBtn'
        if hMeasure.getNumberOfMeasurements() == 0; return; end
        dlgOpt.Icon = 'puffin_warning';
        answer = utils.dlgs.inputQuestDlg(obj.view.gui, ...
            sprintf('Delete all measurements?\n\nTip: you can undo this operation with Ctrl+Z'), 'Delete all', 'Delete', 'Cancel', 'Cancel', dlgOpt);
        if ~strcmp(answer, 'Delete'); return; end
        obj.mibModel.backup('measurements');
        hMeasure.removeMeasurement([]);
        obj.updateTable();
        notify(obj.mibModel, 'ShowImage');


    case 'loadBtn'
        obj.loadMeasurements();

    case 'saveBtn'
        obj.saveMeasurements();

    case 'refreshTableBtn'
        obj.updateTable();

    case 'helpBtn'
        web('https://mib.helsinki.fi/help/user-guide/tools/measure-tool.html', '-browser');

    case 'updateVoxelsButton'
        pixSize = obj.mibModel.I{datasetId}.image.pixSize;
        hHandles.voxelSizeTxt.Text = sprintf('X: %.4f / Y: %.4f / Z: %.4f %s', ...
            pixSize.x, pixSize.y, pixSize.z, pixSize.units);

    case 'measureTable'
        if ~isempty(event) && isprop(event, 'Indices') && ~isempty(event.Indices)
            obj.indices = event.Indices;
        end
        obj.previewIntensityProfile();
        if hHandles.autoJumpCheck.Value && ~isempty(obj.indices) && hMeasure.getNumberOfMeasurements() > 0
            % resolve table row → data index (same mapping as contextMenu / previewIntensityProfile)
            selectedRow = obj.indices(1, 1);
            filterValue = hHandles.filterPopup.Value;
            if strcmp(filterValue, 'All')
                dataIndex = selectedRow;
            else
                typeFlags = strcmp({hMeasure.Data(1:hMeasure.getNumberOfMeasurements()).type}, filterValue);
                filteredIndices = find(typeFlags);
                if selectedRow > numel(filteredIndices); return; end
                dataIndex = filteredIndices(selectedRow);
            end
            if dataIndex > hMeasure.getNumberOfMeasurements(); return; end

            dataset  = obj.mibModel.I{datasetId};
            centerX  = mean(hMeasure.Data(dataIndex).X);
            centerY  = mean(hMeasure.Data(dataIndex).Y);
            dataset.moveView(centerX, centerY);

            newZ = round(hMeasure.Data(dataIndex).Z);
            newT = round(hMeasure.Data(dataIndex).T);
            if dataset.image.time > 1
                dataset.slices{5} = [newT, newT];
                notify(obj.mibModel, 'FrameChanged');
            end
            if dataset.image.depth > 1
                dataset.slices{3} = [newZ, newZ];
                notify(obj.mibModel, 'SliceChanged');
            else
                notify(obj.mibModel, 'ShowImage');
            end
        end

    case 'filterPopup'
        hMeasure.typeToShow = source.Value;
        obj.updateTable();

    case 'closeBtn'
        obj.closeWindow();
end
end
