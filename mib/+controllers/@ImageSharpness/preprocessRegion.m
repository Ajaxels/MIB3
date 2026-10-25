function periodicImage = preprocessRegion(regionImage)
% PREPROCESSREGION - Prepare an image region for Fourier analysis.
%
% Converts the region to double, removes the mean and returns the periodic
% component of the periodic-plus-smooth decomposition (Moisan, 2011). The
% Fourier transform assumes the image repeats itself; the jump between the
% left/right and top/bottom borders of a real image then shows up as a bright
% cross along the frequency axes and adds false high-frequency power. The
% periodic component has no such jump and, unlike a window function, does
% not damp the image content near the borders.
%
% Syntax:
%   .. code-block:: matlab
%
%      periodicImage = controllers.ImageSharpness.preprocessRegion(regionImage)
%
% Input Arguments:
%   - **regionImage** - [numeric, 2D] one color channel of the analysed region,
%     any numeric class; NaN values (from a non-rectangular ROI crop) are
%     replaced by the mean of the valid pixels
%
% Output Arguments:
%   - **periodicImage** - [double, 2D] periodic component with zero mean, same
%     size as ``regionImage``
%
% Errors:
%   - ``MIB:ImageSharpness:RegionTooSmall`` when the shorter side of the region
%     is below 64 pixels; Fourier based estimates on fewer pixels are dominated
%     by the noise of the spectrum
%   - ``MIB:ImageSharpness:NotTwoDimensional`` when the input is not a 2D matrix
%
% References:
%   - Moisan L. (2011) Periodic plus smooth image decomposition. J Math Imaging
%     Vis 39, 161-179. https://doi.org/10.1007/s10851-010-0227-1
%
% See also: controllers.ImageSharpness.computeFftResolution,
% controllers.ImageSharpness.computeDecorrelationResolution

% Updates
%

if ~ismatrix(regionImage)
    error('MIB:ImageSharpness:NotTwoDimensional', ...
        'The region must be a 2D image of a single color channel');
end
[height, width] = size(regionImage);
if min(height, width) < 64
    error('MIB:ImageSharpness:RegionTooSmall', ...
        'The region is %d x %d pixels; at least 64 x 64 pixels are required', width, height);
end

imageData = double(regionImage);
nanPixels = isnan(imageData);
if any(nanPixels(:))
    imageData(nanPixels) = mean(imageData(~nanPixels));
end
imageData = imageData - mean(imageData(:));

% boundary image: differences across the opposite borders
boundaryImage = zeros(height, width);
boundaryImage(1, :)   = imageData(end, :) - imageData(1, :);
boundaryImage(end, :) = -boundaryImage(1, :);
boundaryImage(:, 1)   = boundaryImage(:, 1)   + imageData(:, end) - imageData(:, 1);
boundaryImage(:, end) = boundaryImage(:, end) - imageData(:, end) + imageData(:, 1);

% solve the Poisson equation for the smooth component in the Fourier domain
rowFrequency = 2*cos(2*pi*(0:height-1)'/height);
columnFrequency = 2*cos(2*pi*(0:width-1)/width);
denominator = rowFrequency + columnFrequency - 4;
denominator(1, 1) = 1;  % the DC term is set to zero below
smoothSpectrum = fft2(boundaryImage) ./ denominator;
smoothSpectrum(1, 1) = 0;
smoothImage = real(ifft2(smoothSpectrum));

periodicImage = imageData - smoothImage;
periodicImage = periodicImage - mean(periodicImage(:));
end
