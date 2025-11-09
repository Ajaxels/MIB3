function lut = generateLUT(noColorChannels)
% function lut = generateLUT(noColorChannels)
% generate default LUT table for color channels. The first 3 color channels
% are Red, Green, Blue; others are generated using Hue shifts.
%
% Parameters:
% noColorChannels: required number of color channels, when [] return 3 colors (Red, Green, Blue)
%
% Return values:
% lut: matrix with default LUT for color channels, as lut(colorChannel, R G B) in range from 0 to 1

%|
% @b Examples:
% @code lut = utils.defaults.generateLUT(5); // get the default scheme for 5 color channels @endcode

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