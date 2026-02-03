function [lowIn, highIn, lowOut, highOut] = getImAdjustStretchCoef(obj, channels)
% function [lowIn, highIn, lowOut, highOut] = getImAdjustStretchCoef(obj, channels)
% Return image stretching coefficients to be used for imadjust function to
% stretch contrast of the image
%
% Parameters:
% channels: [@em optional] color channel or vector of color channels to get
% coefficients; when skipped return coefficients for all color channels
%
% Return values:
% lowIn: values matching low_in parameter of imadjust
% highIn: values matching high_in parameter of imadjust
% lowOut: values matching low_out parameter of imadjust
% highOut: values matching high_in parameter of imadjust

%|
% Examples:
% @code [lowIn, highIn, lowOut, highOut] = obj.mibModel.I{obj.mibModel.id}.getImAdjustStretchCoef(channel);  // call from mibController; get coefficients @endcode

% Updates
% 01.11.2017, IB, updated syntax

if nargin < 2; channels = 1:obj.colors; end

% max integer for the current image class
maxInt = obj.maxInt;
noChannels = numel(channels);
viewPort = obj.viewPort;

if mean(viewPort.min(channels)) == viewPort.min(1) && ...
    mean(viewPort.max(channels)) == viewPort.max(1)
    % all channels have the same stretching coefficients
    processChannels = channels(1);
else
    % channels have different stretching coefficients
    processChannels = channels;
    lowIn = zeros([noChannels, 1]);
    highIn = zeros([noChannels, 1]);
    lowOut = zeros([noChannels, 1]);
    highOut = zeros([noChannels, 1]);
end

for i = 1:numel(processChannels)
    colCh = processChannels(i);
    if viewPort.min(colCh) >= 0 && viewPort.max(colCh) <= maxInt
        lowIn(i) = viewPort.min(colCh)/maxInt; highIn(i) = viewPort.max(colCh)/maxInt;
        lowOut(i) = 0; highOut(i) = 1;
    elseif viewPort.min(colCh) >= 0 && viewPort.max(colCh) > maxInt
        lowIn(i) = viewPort.min(colCh)/maxInt; highIn(i) = 1;
        lowOut(i) = 0; highOut(i) = maxInt/viewPort.max(colCh);
    elseif viewPort.min(colCh) < 0 && viewPort.max(colCh) <= maxInt
        lowIn(i) = 0; highIn(i) = viewPort.max(colCh)/maxInt;
        lowOut(i) = abs(maxInt/(maxInt+abs(viewPort.min(colCh)))-1); highOut(i) = 1;
    else
        lowIn(i) = 0; highIn(i) = 1;
        lowOut(i) = abs(maxInt/(maxInt+abs(viewPort.min(colCh)))-1);
        highOut(i) = maxInt/viewPort.max(colCh);
    end
end

if numel(channels) > numel(processChannels)
    % extend result to number of required channels
    lowIn = repmat(lowIn, [noChannels, 1]);
    highIn = repmat(highIn, [noChannels, 1]);
    lowOut = repmat(lowOut, [noChannels, 1]);
    highOut = repmat(highOut, [noChannels, 1]);
end

end