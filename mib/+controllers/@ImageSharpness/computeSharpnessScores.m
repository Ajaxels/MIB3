function result = computeSharpnessScores(regionImage, smoothingSigma)
% COMPUTESHARPNESSSCORES - Relative focus scores of an image region.
%
% Syntax:
%   .. code-block:: matlab
%
%      result = controllers.ImageSharpness.computeSharpnessScores(regionImage)
%      result = controllers.ImageSharpness.computeSharpnessScores(regionImage, smoothingSigma)
%
% Two classic autofocus measures, both normalised by the intensity variance
% of the region so that brightness and contrast settings do not change them:
%
%   - **gradient energy** (Tenengrad): mean squared Sobel gradient magnitude
%     divided by the variance;
%   - **Laplacian variance**: variance of the Laplacian-filtered image divided
%     by the variance.
%
% Both grow when the image gets sharper, but they have no unit and depend on
% the content of the region: they rank images or regions of the same
% specimen (for example a focus series), and are meaningless across
% different specimens. Noise also raises them; a light Gaussian smoothing
% (default sigma 1 pixel) before the measures reduces that bias. A border of
% ``ceil(3*sigma)+2`` pixels is excluded from the statistics to avoid filter
% edge effects.
%
% Input Arguments:
%   - **regionImage** - [numeric, 2D] one color channel of the region, raw
%     intensities (not the periodic component); NaN pixels from a
%     non-rectangular ROI are replaced by the mean
%   - **smoothingSigma** *(optional)* - [numeric] sigma of the Gaussian
%     smoothing in pixels, ``0`` to disable (default: ``1``)
%
% Output Arguments:
%   - **result** - struct with fields:
%
%     - ``.gradientEnergy`` - [double] normalised Tenengrad score
%     - ``.laplacianVariance`` - [double] normalised Laplacian variance;
%       both are ``NaN`` for a region of constant intensity
%
% References:
%   - Pertuz S., Puig D., Garcia M.A. (2013) Analysis of focus measure
%     operators for shape-from-focus. Pattern Recognition 46, 1415-1432.
%     https://doi.org/10.1016/j.patcog.2012.11.011
%

% Updates
%

if nargin < 2; smoothingSigma = 1; end

imageData = double(regionImage);
nanPixels = isnan(imageData);
if any(nanPixels(:))
    imageData(nanPixels) = mean(imageData(~nanPixels));
end
if smoothingSigma > 0
    imageData = imgaussfilt(imageData, smoothingSigma, 'Padding', 'replicate');
end

[gradientX, gradientY] = imgradientxy(imageData, 'sobel');
laplacianImage = imfilter(imageData, fspecial('laplacian', 0), 'replicate');

border = ceil(3*smoothingSigma) + 2;
[height, width] = size(imageData);
rows = min(border+1, height):max(height-border, 1);
columns = min(border+1, width):max(width-border, 1);
centralImage = imageData(rows, columns);
intensityVariance = var(centralImage(:));
% relative test: filtering a constant image leaves rounding noise, not zero
if intensityVariance <= 1e-12 * max(1, mean(centralImage(:))^2)
    result.gradientEnergy = NaN;
    result.laplacianVariance = NaN;
    return;
end
gradientMagnitude2 = gradientX(rows, columns).^2 + gradientY(rows, columns).^2;
centralLaplacian = laplacianImage(rows, columns);
result.gradientEnergy = mean(gradientMagnitude2(:)) / intensityVariance;
result.laplacianVariance = var(centralLaplacian(:)) / intensityVariance;
end
