function lut = generateLUT(noColorChannels)
% GENERATELUT - Generate default LUT table for color channels.
%
% Syntax:
%   .. code-block:: matlab
%
%      lut = generateLUT(noColorChannels)
%
% The first 3 color channels are Red, Green, Blue; others are generated using Hue shifts.
%
% Input Arguments:
%   - **noColorChannels** - [numeric] required number of color channels; pass ``[]`` to get 3 colors (Red, Green, Blue)
%
% Output Arguments:
%   - **lut** - [numeric] matrix with default LUT for color channels, ``lut(colorChannel, [R G B])`` in range 0-1
%
% Usage:
%
%   **Example 1** - get the default colour scheme for 5 colour channels
%
%   .. code-block:: matlab
%
%      lut = utils.defaults.generateLUT(5);
%

% Fixed first 3 colors
colors = [
    1 0 0;  % Red
    0 1 0;  % Green
    0 0 1   % Blue
    ];

if noColorChannels <= 3
    lut = colors(1:noColorChannels, :);
    return;
end


% Generate remaining colors in HSV space for maximum coverage
remaining = noColorChannels - 3;
hues = linspace(0, 1, remaining + 1);  % Spread hues evenly
hues = hues(1:end-1);  % Remove duplicate at end

% Shift hues to avoid red, green, blue regions
hues = hues + 0.1;  % Offset to avoid primary colors
hues = mod(hues, 1);

for i = 1:remaining
    % HSV: vary hue, use medium saturation and brightness
    hsv = [hues(i), 0.7, 0.85];
    rgb = hsv2rgb(hsv);
    colors = [colors; rgb];
end

lut = colors;
end
