function updateWidgets(obj)
% UPDATEWIDGETS - Refresh all GUI widget state from the current dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.updateWidgets()
%
% Called on construction and whenever ``UpdateGuiWidgets`` or
% ``NewDataset`` fires.  Rebuilds the colour-channel dropdown, updates
% the pixel-size label, syncs the interpolation method and marker/line/text
% checkboxes, and refreshes the measurements table.
%
% Input Arguments:
%   - **obj** - :class:`controllers.MeasureTool`
%

datasetId = obj.mibModel.getActiveId();
hMeasure  = obj.mibModel.I{datasetId}.measure;
pixSize   = obj.mibModel.I{datasetId}.image.pixSize;
nChannels = obj.mibModel.I{datasetId}.dim_yxzct(4);

% Populate colour-channel dropdown
channelItems = [{'All'}, arrayfun(@(channelIdx) sprintf('Ch %d', channelIdx), ...
    1:nChannels, 'UniformOutput', false)];
obj.view.handles.imageColChDropdown.Items = channelItems;

% Sync interpolation method dropdown
if ismember(hMeasure.Options.splinemethod, obj.view.handles.interpolationModePopup.Items)
    obj.view.handles.interpolationModePopup.Value = hMeasure.Options.splinemethod;
end

% Pixel size text
obj.view.handles.voxelSizeTxt.Text = sprintf('X: %.4f / Y: %.4f / Z: %.4f %s', ...
    pixSize.x, pixSize.y, pixSize.z, pixSize.units);

% Marker / line / text toggles
obj.view.handles.markersCheck.Value = logical(hMeasure.Options.showMarkers);
obj.view.handles.linesCheck.Value   = logical(hMeasure.Options.showLines);
obj.view.handles.textCheck.Value    = logical(hMeasure.Options.showText);

obj.updateTable();
end
