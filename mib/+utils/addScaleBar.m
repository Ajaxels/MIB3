function I = addScaleBar(I, pixSize, scale, Options)
% ADDSCALEBAR - Add a scale bar to an RGB image.
%
% Requires ``insertText`` function from the Computer Vision System Toolbox.
%
% Syntax:
%   .. code-block:: matlab
%
%       imageOut = utils.addScaleBar(I, pixSize, scale)
%       imageOut = utils.addScaleBar(I, pixSize, scale, Options)
%
% Parameters:
%   **I** - RGB image that requires the scale bar
%
%   **pixSize** - structure with pixel size fields (``.x``, ``.y``, ``.z``, ``.units``)
%
%   **scale** - scaling factor indicating how the pixel size differs from the ``pixSize`` structure
%
%   **Options** *(optional)* - structure with additional settings:
%
%       - ``.orientation`` - orientation of the snapshot: ``1`` (ZX), ``2`` (ZY), ``3`` (XY, default)
%       - ``.scaleBarHeight`` - height of the scale bar in pixels (min 22), default ``[]`` (auto)
%       - ``.bgColor`` - background color, from ``0`` (black) to ``1`` (white), default ``0``
%       - ``.textSuffix`` - string appended after the scale text, default ``''``
%
% Return values:
%   **I** - input image with the scale bar appended at the bottom

if nargin < 4; Options = struct(); end
if ~isfield(Options, 'orientation'); Options.orientation = 3; end
if ~isfield(Options, 'scaleBarHeight'); Options.scaleBarHeight = []; end
if ~isfield(Options, 'bgColor'); Options.bgColor = 0; end
if ~isfield(Options, 'textSuffix'); Options.textSuffix = ''; end
scaleBarHeight = Options.scaleBarHeight;

if Options.orientation == 3
    pixelSize = pixSize.x / scale;
elseif Options.orientation == 1     % zx: horizontal X
    pixelSize = pixSize.x / scale;
elseif Options.orientation == 2
    pixelSize = pixSize.z / scale;
end

imageWidth = size(I, 2);
imageHeight = size(I, 1);
if isempty(scaleBarHeight)
    scaleBarHeight = 22 * ceil(min([imageWidth imageHeight]) / 600);
else
    if scaleBarHeight < 22
        warning('utils:addScaleBar', 'The height of the scale bar should be at least 22 pixels');
        return;
    end
end
resizeFactor = scaleBarHeight / 22;

targetStep = imageWidth * pixelSize / 10;  % targeted length of the scale bar in units
magnitude = floor(log10(targetStep));      % magnitude of the scale bar
magnitudePow = power(10, magnitude);
magnitudeDigit = floor(targetStep / magnitudePow + 0.5);
roundStep = magnitudeDigit * magnitudePow; % rounded step
if magnitude < 0
    formatStr = ['%.' num2str(abs(magnitude)) 'f %s'];
    scaleBarText = sprintf(formatStr, roundStep, pixSize.units);
else
    scaleBarText = sprintf('%d %s', roundStep, pixSize.units);
end

scaleBarLength = round(roundStep / pixelSize);

colorsNumber = size(I, 3);
shiftX = 5;     % shift of the scale bar from the left corner
maxIntensity = double(intmax(class(I)));
bgColor = round(Options.bgColor * maxIntensity);
fgColor = round((1 - Options.bgColor) * maxIntensity);

if scaleBarLength + shiftX*2 + (numel([scaleBarText Options.textSuffix]) * 12 * resizeFactor) > imageWidth
    if scaleBarLength + shiftX*2 + (numel(scaleBarText) * 12 * resizeFactor) > imageWidth
        warning('utils:addScaleBar', 'Image is too small to put the scale bar! Saving image without the scale bar...');
        return;
    end
else
    scaleBarText = [scaleBarText Options.textSuffix];
end

scaleBarSectionHeight = 22;
barModel = zeros(scaleBarSectionHeight, size(I, 2), size(I, 3), class(I)) + bgColor;

% draw the scale bar lines
barModel(10:12, shiftX:shiftX+scaleBarLength-1, :) = repmat(fgColor, [3, scaleBarLength, colorsNumber]);
barModel(8:14, shiftX, :) = repmat(fgColor, [7, 1, colorsNumber]);
barModel(8:14, shiftX+scaleBarLength-1, :) = repmat(fgColor, [7, 1, colorsNumber]);

% resize the scale bar
if resizeFactor > 1
    barModelCropped = barModel(:, 1:scaleBarLength+shiftX*2, :);
    barModelCropped = imresize(barModelCropped, [scaleBarHeight size(barModelCropped, 2)], 'nearest');
    scaleBarLength = size(barModelCropped, 2);

    barModel = zeros(scaleBarHeight, size(I, 2), size(I, 3), class(I)) + bgColor;
    barModel(:, round(shiftX*resizeFactor):round(shiftX*resizeFactor)+size(barModelCropped, 2)-1, :) = barModelCropped;
end

% add text using insertText (Computer Vision Toolbox)
scaleBarText = strrep(scaleBarText, 'u', char(956));    % replace u with mu sign
barModel = insertText(barModel, [scaleBarLength + 10*resizeFactor, round(scaleBarHeight/2)], scaleBarText, ...
    'FontSize', min([200 round(15*resizeFactor)]), ...
    'BoxOpacity', 0, 'TextColor', [fgColor, fgColor, fgColor], 'AnchorPoint', 'LeftCenter');

I = cat(1, I, barModel);
end
