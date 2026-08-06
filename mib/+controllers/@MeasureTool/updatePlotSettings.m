function updatePlotSettings(obj)
% UPDATEPLOTSETTINGS - Sync marker/line/text checkboxes to Options and repaint.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.updatePlotSettings()
%
% Input Arguments:
%   - **obj** - :class:`controllers.MeasureTool`
%

datasetId = obj.mibModel.getActiveId();
hMeasure  = obj.mibModel.I{datasetId}.measure;

hMeasure.Options.showMarkers = double(obj.view.handles.markersCheck.Value);
hMeasure.Options.showLines   = double(obj.view.handles.linesCheck.Value);
hMeasure.Options.showText    = double(obj.view.handles.textCheck.Value);

notify(obj.mibModel, 'ShowImage');
end
