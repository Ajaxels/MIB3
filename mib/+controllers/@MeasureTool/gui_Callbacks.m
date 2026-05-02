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

switch source.Tag
    case 'addBtn'
        obj.addMeasurement();

    case 'closeBtn'
        obj.closeWindow();

    case 'deleteAllBtn'
        if hMeasure.getNumberOfMeasurements() == 0; return; end
        obj.mibModel.backup('measurements');
        hMeasure.removeMeasurement([]);
        obj.updateTable();
        notify(obj.mibModel, 'ShowImage');

    case 'optionsBtn'
        hMeasure.updateOptions(obj.view.gui);
        obj.view.handles.markersCheck.Value = logical(hMeasure.Options.showMarkers);
        obj.view.handles.linesCheck.Value   = logical(hMeasure.Options.showLines);
        obj.view.handles.textCheck.Value    = logical(hMeasure.Options.showText);
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
        obj.view.handles.voxelSizeTxt.Text = sprintf('X: %.4f / Y: %.4f / Z: %.4f %s', ...
            pixSize.x, pixSize.y, pixSize.z, pixSize.units);

    case 'measureTable'
        if ~isempty(event) && isfield(event, 'Indices') && ~isempty(event.Indices)
            obj.indices = event.Indices;
        end
        if obj.view.handles.previewIntensityCheck.Value
            obj.previewIntensityProfile();
        end

    case 'filterPopup'
        hMeasure.typeToShow = source.Value;
        obj.updateTable();

    case 'interpolationModePopup'
        hMeasure.Options.splinemethod = source.Value;

    case {'markersCheck', 'linesCheck', 'textCheck'}
        obj.updatePlotSettings();
end
end
