function result = computeDecorrelationResolution(periodicImage, pixelSize, options)
% COMPUTEDECORRELATIONRESOLUTION - Estimate image resolution by decorrelation analysis.
%
% Syntax:
%   .. code-block:: matlab
%
%      result = controllers.ImageSharpness.computeDecorrelationResolution(periodicImage, pixelSize)
%      result = controllers.ImageSharpness.computeDecorrelationResolution(periodicImage, pixelSize, options)
%
% Implementation of the parameter-free single-image resolution estimate of
% Descloux, Grussmayer and Radenovic (2019), written from the published
% description. The image spectrum is correlated with its own phase-only
% (amplitude-normalised) version, low-pass filtered with a circular mask of
% increasing radius ``r``. While the mask passes signal-dominated
% frequencies the correlation ``d(r)`` grows; once it passes frequencies that
% carry only noise, whose phase is random, ``d(r)`` falls. The radius of the
% peak marks where signal ends. Strong low frequencies push this peak to small
% radii, so the curve is recomputed for a series of Gaussian high-pass
% filtered spectra (filter ``1 - exp(-2*g^2*r^2)``); the largest peak radius
% over all curves is the cutoff ``kc``, normalised to Nyquist, and the
% resolution is ``2*pixelSize/kc``.
%
% Implementation details:
%
%   - All radii are normalised to ``fNyquist = 1/(2*max(pixelSize))`` on a
%     physical frequency grid, so pixels of different x and y size give a
%     circular domain; the spectrum outside the unit circle is ignored.
%   - Because the normalised spectrum has unit amplitude,
%     ``d(r) = sum(w*|F|) / (sqrt(sum(w^2*|F|^2)) * sqrt(n(r)))`` where the
%     sums run over the pixels inside radius ``r``, ``w`` is the high-pass
%     filter and ``n(r)`` the number of those pixels; the numerator norm uses
%     the whole unit disc. Pixels are sorted by radius once and every curve
%     is evaluated with cumulative sums, so the cost is one sort plus one
%     pass per filter instead of one pass per radius and filter.
%   - A peak counts only when it is not the last point of the curve and rises
%     at least ``0.001`` above the minimum that follows it (the original uses
%     ``0.0005`` on values floored to 3 decimals); a curve without such a
%     peak gives ``kc = 0``. When no curve has a peak, the resolution is
%     ``NaN``, as in the original method.
%
% When there is no peak: ``d(r)`` falls only where the spectrum amplitude
% drops faster than ``1/r``, which a blur (optical cutoff) produces. An
% image whose amplitude falls as ``1/r`` right up to the noise, typical of
% undersampled images where the pixel is coarser than the beam, gives curves
% that are flat and then rise, with no peak; pure white noise gives a rising
% curve too, so the two cases cannot be told apart from ``d(r)``, and the
% method reports nothing. In the same images a flat stretch of the curve can
% carry a small ripple that passes as a peak at a low radius, giving a
% resolution several times coarser than the FFT estimate. A large
% disagreement between the two methods therefore points to such a
% spectrum; synthetic tests and measured values are in
% ``development/sharpness/plan_sharpness.md``.
%   - Filters: ``g`` takes ``size/4`` (almost unfiltered) and
%     ``NumberOfFilters`` values spaced logarithmically from ``2/r0`` down to
%     ``0.15``, where ``r0`` is the peak radius of the unfiltered curve. A
%     second pass refines ``r`` between the neighbours of the best peak and
%     ``g`` between the neighbours of the best filter.
%
% Unlike the FFT cutoff, the decorrelation estimate needs no noise-floor
% model and is robust to the noise level, but it gives no direction. Values
% close to 2 pixels (``kc`` near 1) mean the image is limited by the pixel
% size.
%
% Input Arguments:
%   - **periodicImage** - [double, 2D] zero-mean region, normally the output
%     of :func:`controllers.ImageSharpness.preprocessRegion`
%   - **pixelSize** - [numeric] pixel size ``[x, y]`` in physical units; a
%     scalar is used for both
%   - **options** *(optional)* - struct with fields:
%
%     - ``.NumberOfRadii`` - [numeric] sampled radii per curve (default: ``50``)
%     - ``.NumberOfFilters`` - [numeric] high-pass filters (default: ``10``)
%
% Output Arguments:
%   - **result** - struct with fields:
%
%     - ``.resolution`` - [double] physical units of ``pixelSize``; ``NaN``
%       when no curve had a peak
%     - ``.resolutionPixels`` - [double] resolution in pixels (of the larger
%       pixel side)
%     - ``.cutoffNormalized`` - [double] ``kc``, 0-1 of Nyquist; ``0`` when
%       no curve had a peak
%     - ``.peakAmplitude`` - [double] ``d`` at the selected peak, a rough
%       signal-to-noise indicator
%     - ``.radii`` - [double, vector] normalised radii of the first pass
%     - ``.curves`` - [double, matrix] ``d(r)`` of the first pass, one row per
%       filter, first row unfiltered
%     - ``.peakRadii`` - [double, vector] peak radius of every curve of the
%       first pass
%
% References:
%   - Descloux A., Grussmayer K.S., Radenovic A. (2019) Parameter-free image
%     resolution estimation based on decorrelation analysis. Nature Methods
%     16, 918-924. https://doi.org/10.1038/s41592-019-0515-7
%

% Updates
%

if nargin < 3; options = struct(); end
if ~isfield(options, 'NumberOfRadii'); options.NumberOfRadii = 50; end
if ~isfield(options, 'NumberOfFilters'); options.NumberOfFilters = 10; end
if isscalar(pixelSize); pixelSize = [pixelSize pixelSize]; end

[height, width] = size(periodicImage);
spectrumAmplitude = abs(fftshift(fft2(periodicImage)));

frequencyX = ((0:width-1) - floor(width/2)) / (width * pixelSize(1));
frequencyY = ((0:height-1) - floor(height/2)) / (height * pixelSize(2));
[gridX, gridY] = meshgrid(frequencyX, frequencyY);
nyquistFrequency = 1 / (2*max(pixelSize));
normalizedRadius = hypot(gridX, gridY) / nyquistFrequency;

% pixels inside the unit disc with non-zero amplitude, sorted by radius
discPixels = normalizedRadius <= 1 & spectrumAmplitude > 0;
[sortedRadius, sortOrder] = sort(normalizedRadius(discPixels));
discAmplitude = spectrumAmplitude(discPixels);
sortedAmplitude = discAmplitude(sortOrder);
pixelCount = (1:numel(sortedRadius))';

peakThreshold = 1e-3;

% first pass: unfiltered curve gives r0
radii = linspace(0, 1, options.NumberOfRadii + 1);
radii = radii(2:end);
unfilteredCurve = decorrelationCurve(ones(size(sortedRadius)));
[r0, ~] = findPeak(unfilteredCurve, radii);
if r0 == 0; r0 = 1; end

filterWidths = [min(height, width)/4, exp(linspace(log(2/r0), log(0.15), options.NumberOfFilters))];
curves = zeros(numel(filterWidths), numel(radii));
peakRadii = zeros(1, numel(filterWidths));
peakAmplitudes = zeros(1, numel(filterWidths));
for filterId = 1:numel(filterWidths)
    filterWeights = highPass(filterWidths(filterId));
    curves(filterId, :) = decorrelationCurve(filterWeights);
    [peakRadii(filterId), peakAmplitudes(filterId)] = findPeak(curves(filterId, :), radii);
end

result.radii = radii;
result.curves = curves;
result.peakRadii = peakRadii;

[bestRadius, bestFilter] = max(peakRadii);
if bestRadius == 0
    result.resolution = NaN;
    result.resolutionPixels = NaN;
    result.cutoffNormalized = 0;
    result.peakAmplitude = 0;
    return;
end
bestAmplitude = peakAmplitudes(bestFilter);

% second pass: refine radius and filter around the best peak
radiusIndex = find(radii == bestRadius, 1);
refinedRadii = linspace(radii(max(radiusIndex-1, 1)), radii(min(radiusIndex+1, numel(radii))), options.NumberOfRadii);
lowerFilter = filterWidths(min(bestFilter+1, numel(filterWidths)));
upperFilter = filterWidths(max(bestFilter-1, 1));
refinedFilters = exp(linspace(log(upperFilter), log(lowerFilter), options.NumberOfFilters));
for filterId = 1:numel(refinedFilters)
    refinedCurve = decorrelationCurve(highPass(refinedFilters(filterId)), refinedRadii);
    [peakRadius, peakAmplitude] = findPeak(refinedCurve, refinedRadii);
    % a peak at the edge of the refined range is not a local maximum there
    if peakRadius > bestRadius && peakRadius < refinedRadii(end)
        bestRadius = peakRadius;
        bestAmplitude = peakAmplitude;
    end
end

result.cutoffNormalized = bestRadius;
result.peakAmplitude = bestAmplitude;
result.resolution = 2 * max(pixelSize) / bestRadius;
result.resolutionPixels = 2 / bestRadius;

    % ---------------------------------------------------------------------
    function weights = highPass(filterWidth)
        % Gaussian high-pass filter evaluated at the sorted radii
        weights = 1 - exp(-2 * filterWidth^2 * sortedRadius.^2);
    end

    function curve = decorrelationCurve(weights, sampleRadii)
        % d(r) for the given filter weights at the sample radii
        if nargin < 2; sampleRadii = radii; end
        weightedAmplitude = weights .* sortedAmplitude;
        totalNorm = sqrt(sum(weightedAmplitude.^2));
        cumulativeAmplitude = cumsum(weightedAmplitude);
        % number of disc pixels inside every sampled radius (sampleRadii increase)
        countIndex = cumsum(histcounts(sortedRadius, [-Inf, sampleRadii(:)']));
        curve = zeros(size(sampleRadii));
        hasPixels = countIndex > 0;
        curve(hasPixels) = cumulativeAmplitude(countIndex(hasPixels))' ./ ...
            (totalNorm * sqrt(pixelCount(countIndex(hasPixels))'));
        curve(~isfinite(curve)) = 0;
    end

    function [peakRadius, peakAmplitude] = findPeak(curve, sampleRadii)
        % highest significant local maximum that is not at the end of the curve
        curve = curve(:)';
        candidates = curve;
        while true
            [peakAmplitude, peakIndex] = max(candidates);
            if isempty(candidates) || peakAmplitude <= 0
                peakRadius = 0;
                peakAmplitude = 0;
                return;
            end
            if peakIndex < numel(curve) && peakAmplitude - min(curve(peakIndex:end)) > peakThreshold
                peakRadius = sampleRadii(peakIndex);
                return;
            end
            candidates(peakIndex) = -Inf;
            if all(isinf(candidates))
                peakRadius = 0;
                peakAmplitude = 0;
                return;
            end
        end
    end
end
