function makeSharpnessIcon(outputFolder)
% Ribbon icon for Sharpness and noise: Fourier spectrum background, ruler crossing it.
% Rendered at 384 px and reduced with antialiasing to 24 and 16 px (RGBA PNG).
if nargin < 1; outputFolder = fileparts(mfilename('fullpath')); end
canvasSize = 384;

% ---- spectrum: log |FFT| of a slightly astigmatic random texture
randomStream = RandStream('mt19937ar', 'Seed', 7);
textureSize = 256;
[frequencyX, frequencyY] = meshgrid(((0:textureSize-1) - textureSize/2) / textureSize);
theta = 35*pi/180;
alongMajor = frequencyX*cos(theta) - frequencyY*sin(theta);
alongMinor = frequencyX*sin(theta) + frequencyY*cos(theta);
transferFunction = exp(-2*pi^2*(9*alongMajor.^2 + 3*alongMinor.^2));
spectrum = abs(ifftshift(fft2(randn(randomStream, textureSize)))) .* transferFunction;
spectrum = log10(spectrum + 0.02);
spectrum = rescale(spectrum);
spectrum = imgaussfilt(spectrum, 1.2);
spectrum = imresize(spectrum(textureSize/2+(-80:79), textureSize/2+(-80:79)), [canvasSize canvasSize]);
spectrum = rescale(spectrum) .^ 1.3;
% dark navy -> blue -> cyan -> white
anchors = [0.05 0.07 0.20; 0.10 0.25 0.65; 0.20 0.70 0.95; 1 1 1];
colorMap = interp1(linspace(0, 1, size(anchors, 1)), anchors, linspace(0, 1, 256));
rgb = ind2rgb(im2uint8(spectrum), colorMap);

% ---- rounded square background mask
[pixelX, pixelY] = meshgrid(1:canvasSize);
margin = canvasSize * 0.03;
cornerRadius = canvasSize * 0.16;
inner = [margin + cornerRadius, canvasSize - margin - cornerRadius];
distanceX = max(max(inner(1) - pixelX, pixelX - inner(2)), 0);
distanceY = max(max(inner(1) - pixelY, pixelY - inner(2)), 0);
alpha = double(hypot(distanceX, distanceY) <= cornerRadius);

% ---- ruler: rotated bar from bottom-left to top-right with tick marks
rulerAngle = 40*pi/180;              % screen angle, counterclockwise
rulerLength = canvasSize * 1.25;
rulerWidth = canvasSize * 0.17;
centre = [canvasSize canvasSize] / 2 + canvasSize*0.21*[sin(40*pi/180), cos(40*pi/180)];
along = [cos(rulerAngle), -sin(rulerAngle)];      % image coordinates, rows down
across = [sin(rulerAngle), cos(rulerAngle)];
cornerPoints = [-1 -1; 1 -1; 1 1; -1 1];
cornerXY = centre + cornerPoints(:, 1)*rulerLength/2*along + cornerPoints(:, 2)*rulerWidth/2*across;
rulerMask = poly2mask(cornerXY(:, 1), cornerXY(:, 2), canvasSize, canvasSize);
outlineWidth = canvasSize * 0.018;
outlineMask = imdilate(rulerMask, strel('disk', round(outlineWidth))) & ~rulerMask;
rulerColor = [1.00 0.72 0.10];
outlineColor = [0.30 0.18 0.02];
tickColor = [0.30 0.18 0.02];
tickMask = false(canvasSize);
numberOfTicks = 5;
for tickId = 1:numberOfTicks
    position = (tickId - (numberOfTicks + 1)/2) * rulerLength / (numberOfTicks + 1.5);
    if mod(tickId, 2) == 1; tickLength = 0.6; else; tickLength = 0.38; end
    startPoint = centre + position*along - rulerWidth/2*across;
    endPoint = startPoint + tickLength*rulerWidth*across;
    halfThickness = canvasSize * 0.024;
    tickCorners = [startPoint - halfThickness*along; startPoint + halfThickness*along; ...
        endPoint + halfThickness*along; endPoint - halfThickness*along];
    tickMask = tickMask | poly2mask(tickCorners(:, 1), tickCorners(:, 2), canvasSize, canvasSize);
end
tickMask = tickMask & rulerMask;

% composite inside the rounded square only
for channel = 1:3
    layer = rgb(:, :, channel);
    layer(rulerMask) = rulerColor(channel);
    layer(tickMask) = tickColor(channel);
    layer(outlineMask) = outlineColor(channel);
    rgb(:, :, channel) = layer;
end

for iconSize = [24 16]
    smallRgb = imresize(rgb .* alpha, [iconSize iconSize], 'bilinear', 'Antialiasing', true);
    smallAlpha = imresize(alpha, [iconSize iconSize], 'bilinear', 'Antialiasing', true);
    smallRgb = smallRgb ./ max(smallAlpha, eps);       % un-premultiply
    smallRgb = min(max(smallRgb, 0), 1);
    smallAlpha = min(max(smallAlpha, 0), 1);
    fileName = fullfile(outputFolder, sprintf('image_sharpness_%dpx.png', iconSize));
    imwrite(im2uint8(smallRgb), fileName, 'Alpha', im2uint8(smallAlpha));
    % enlarged previews on light and dark backgrounds
    for background = [0.96 0.17]
        preview = smallRgb .* smallAlpha + background * (1 - smallAlpha);
        imwrite(imresize(preview, 12, 'nearest'), fullfile(outputFolder, sprintf('preview_%dpx_%s.png', iconSize, num2str(round(background*100)))));
    end
end
fprintf('icons written to %s\n', outputFolder);
end
