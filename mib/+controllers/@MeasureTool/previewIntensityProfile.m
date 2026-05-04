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

% resolve table rows → data indices (same mapping as contextMenu)
filterValue      = obj.view.handles.filterPopup.Value;
selectedTableRows = unique(obj.indices(:, 1));

if strcmp(filterValue, 'All')
    dataIndices = selectedTableRows;
else
    typeFlags = strcmp({hMeasure.Data(1:hMeasure.getNumberOfMeasurements()).type}, filterValue);
    filteredIndices = find(typeFlags);
    validMask   = selectedTableRows <= numel(filteredIndices);
    dataIndices = filteredIndices(selectedTableRows(validMask));
end

dataIndices = dataIndices(dataIndices <= hMeasure.getNumberOfMeasurements());
if isempty(dataIndices)
    cla(plotAxes);
    return;
end

cla(plotAxes);
hold(plotAxes, 'on');
for selIdx = 1:numel(dataIndices)
    profileData = hMeasure.Data(dataIndices(selIdx)).profile;
    if isequal(profileData, NaN) || isempty(profileData) || ~isnumeric(profileData)
        continue;
    end
    distanceVec = profileData(1, :);
    nChannels   = size(profileData, 1) - 1;
    singleSample = numel(distanceVec) == 1;
    for channelIdx = 1:nChannels
        if singleSample
            plot(plotAxes, distanceVec, profileData(channelIdx + 1, :), 'o');
        else
            plot(plotAxes, distanceVec, profileData(channelIdx + 1, :));
        end
    end
end
hold(plotAxes, 'off');

xlabel(plotAxes, 'Distance (px)');
ylabel(plotAxes, 'Intensity');
end
