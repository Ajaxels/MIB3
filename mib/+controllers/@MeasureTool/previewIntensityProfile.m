function previewIntensityProfile(obj)
% PREVIEWINTENSITYPROFILE - Update profileAxes on table row selection.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.previewIntensityProfile()
%
% Called when the user selects a row in ``measureTable`` and
% ``previewIntensityCheck`` is on.  Plots the stored intensity profile in
% the ``profileAxes`` widget.  If ``autoJumpCheck`` is on, also navigates
% to the measurement's Z/T slice.
%
% Input Arguments:
%   - **obj** — :class:`controllers.MeasureTool`
%

datasetId = obj.mibModel.getActiveId();
hMeasure  = obj.mibModel.I{datasetId}.measure;
plotAxes  = obj.view.handles.profileAxes;

if isempty(obj.indices) || hMeasure.getNumberOfMeasurements() == 0
    cla(plotAxes);
    return;
end

% resolve table row → data index (same mapping as contextMenu)
filterValue = obj.view.handles.filterPopup.Value;
selectedTableRow = obj.indices(1, 1);
if strcmp(filterValue, 'All')
    dataIndex = selectedTableRow;
else
    typeFlags = strcmp({hMeasure.Data(1:hMeasure.getNumberOfMeasurements()).type}, filterValue);
    filteredIndices = find(typeFlags);
    if selectedTableRow > numel(filteredIndices); cla(plotAxes); return; end
    dataIndex = filteredIndices(selectedTableRow);
end

if dataIndex > hMeasure.getNumberOfMeasurements(); cla(plotAxes); return; end

profileData = hMeasure.Data(dataIndex).profile;
if isequal(profileData, NaN) || isempty(profileData) || ~isnumeric(profileData)
    cla(plotAxes);
    return;
end

cla(plotAxes);
distanceVec = profileData(1, :);
nChannels   = size(profileData, 1) - 1;

hold(plotAxes, 'on');
for channelIdx = 1:nChannels
    plot(plotAxes, distanceVec, profileData(channelIdx + 1, :));
end
hold(plotAxes, 'off');

xlabel(plotAxes, 'Distance (px)');
ylabel(plotAxes, 'Intensity');

if obj.view.handles.autoJumpCheck.Value
    obj.mibModel.I{datasetId}.slices{3} = repmat(hMeasure.Data(dataIndex).Z, 1, 2);
    obj.mibModel.I{datasetId}.slices{5} = repmat(hMeasure.Data(dataIndex).T, 1, 2);
    notify(obj.mibModel, 'SliceChanged');
end
end
