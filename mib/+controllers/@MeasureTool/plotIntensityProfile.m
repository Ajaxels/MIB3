function plotIntensityProfile(obj, dataIndex)
% PLOTINTENSITYPROFILE - Plot the intensity profile in a standalone figure.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.plotIntensityProfile(dataIndex)
%
% Opens (or reuses) figure 1952 and plots the intensity profile for the
% measurement at ``dataIndex``.
%
% Input Arguments:
%   - **obj** - :class:`controllers.MeasureTool`
%   - **dataIndex** - [double] 1-based index in ``hMeasure.Data``
%

datasetId = obj.mibModel.getActiveId();
hMeasure  = obj.mibModel.I{datasetId}.measure;

if dataIndex > hMeasure.getNumberOfMeasurements(); return; end

profileData = hMeasure.Data(dataIndex).profile;
if isequal(profileData, NaN) || isempty(profileData) || ~isnumeric(profileData)
    return;
end

figHandle = figure(1952);
clf(figHandle);
figHandle.Name = sprintf('Intensity profile - measurement %d', hMeasure.Data(dataIndex).n);

plotAxes     = axes(figHandle);
distanceVec  = profileData(1, :);
nChannels    = size(profileData, 1) - 1;

singleSample = numel(distanceVec) == 1;
hold(plotAxes, 'on');
for channelIdx = 1:nChannels
    if singleSample
        plot(plotAxes, distanceVec, profileData(channelIdx + 1, :), 'o', ...
            'DisplayName', sprintf('Ch %d', channelIdx));
    else
        plot(plotAxes, distanceVec, profileData(channelIdx + 1, :), ...
            'DisplayName', sprintf('Ch %d', channelIdx));
    end
end
hold(plotAxes, 'off');

xlabel(plotAxes, 'Distance (px)');
ylabel(plotAxes, 'Intensity');
title(plotAxes, sprintf('%s - n=%d', hMeasure.Data(dataIndex).type, hMeasure.Data(dataIndex).n));
if nChannels > 1
    legend(plotAxes, 'show');
end
end
