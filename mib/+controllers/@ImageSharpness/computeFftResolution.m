function result = computeFftResolution(periodicImage, pixelSize, options)
% COMPUTEFFTRESOLUTION - Estimate resolution and astigmatism from the power spectrum of an image region.
%
% Syntax:
%   .. code-block:: matlab
%
%      result = controllers.ImageSharpness.computeFftResolution(periodicImage, pixelSize)
%      result = controllers.ImageSharpness.computeFftResolution(periodicImage, pixelSize, options)
%
% The method follows the Fourier sharpness analysis used for scanning electron
% microscopes (Postek and Vladar). The power spectrum of a sharp image keeps
% signal above the noise floor up to higher spatial frequencies than that of a
% blurred image; the highest such frequency is the cutoff and its inverse is
% the resolution.
%
% Steps:
%
%   1. Power spectrum ``|FFT|^2`` of ``periodicImage`` on a frequency grid in
%      physical units, so pixels of different x and y size give a correct,
%      circular frequency domain. Analysis is limited to the circle of radius
%      ``fNyquist = 1/(2*max(pixelSize))``.
%   2. Noise floor: mean power in the corners of the spectrum, outside the
%      Nyquist circle. At those frequencies a microscope image carries only
%      noise, which is white (flat) for shot and detector noise. Images without
%      corners (when the pixels are strongly anisotropic) fall back to the
%      0.85-1.0 Nyquist band. When the signal itself reaches the corners (the
%      image is undersampled) the floor is overestimated and the cutoff is too
%      low; such images are recognised only when their spectrum stays above
%      the threshold up to Nyquist. With ``SlowDetector`` the floor is a
%      noise power for every horizontal frequency instead (see "Slow
%      detector" below).
%   3. Radial average of the power, smoothed over 5 bins, converted to the
%      signal-to-noise ratio ``(power - floor) / floor``; with
%      ``SlowDetector`` the floor of a bin is the mean noise power of its
%      pixels.
%   4. Cutoff = first frequency, scanning up from the third bin, at which the
%      ratio falls below ``SnrThreshold`` and stays below it for three bins,
%      interpolated between bins. The three-bin condition matters for narrow
%      sectors: with 72 sectors single noisy low-frequency bins gave cutoffs
%      near zero (about 100 px resolution) in a few directions. Scanning
%      from low frequency, rather than taking the last bin above the threshold,
%      keeps isolated peaks of periodic patterns or scan noise beyond the true
%      cutoff from being picked. When the ratio never falls below the
%      threshold the cutoff is set to Nyquist and ``pixelLimited`` is true:
%      the resolution is then limited by the pixel size, the value reported is
%      2 pixels and the true resolution may be better.
%   5. Directional cutoffs: the same rule in ``NumberOfSectors`` overlapping
%      angular sectors covering 0-180 degrees (the spectrum of a real image is
%      point-symmetric), each ``2*180/NumberOfSectors`` degrees wide, with half
%      as many radial bins as the full radial average because every sector
%      holds fewer pixels.
%   6. Astigmatism: a centred ellipse ``A*x^2 + B*y^2 + C*x*y = 1`` is fitted by
%      linear least squares to the sector cutoffs in the frequency plane.
%      Astigmatic blur stretches the spectrum into such an ellipse; its short
%      axis is the most blurred direction. The ratio of the axes is the
%      astigmatism ratio (1 = round spectrum). When the fit is not an ellipse
%      (not positive definite) the extreme sector values are used instead.
%
% Angles are measured on the screen, counterclockwise from the horizontal
% image axis, in the range 0-180 degrees. A direction is the direction across
% which detail is resolved: blur along the horizontal axis lowers the cutoff
% at 0 degrees.
%
% Optionally the spectrum pixels on the horizontal and vertical frequency
% axes are excluded. A scanned image has line-to-line intensity jitter and
% stripes that put power exactly on these axes, unrelated to the beam shape;
% left in, they make the spectrum look elongated along the axes.
%
% Noise and signal-to-noise ratio come from the same noise floor. The power
% spectrum is normalised so that its mean over all pixels equals the image
% variance (Parseval); for white noise every spectrum pixel then carries, on
% average, the noise variance, so the floor is the noise variance and its
% square root the noise standard deviation in grey values. The signal power
% is the image variance minus the noise variance. Scan-line stripes are
% excluded from the floor but count as signal. Tested against known noise:
% SNR 101 for a true 100, 11.2 for 11.1, 1.01 for 1.00, on sharp and
% blurred images.
%
% Slow detector. The corner floor assumes noise independent from pixel to
% pixel. When the detector is slow for the scan speed, each pixel keeps part
% of the signal of the previous one: signal and noise are low-pass filtered
% along the scan line (horizontal), and the corners, at high horizontal
% frequency, hold only the damped noise. The floor is then too low, the SNR
% too high (2.9x for a real SEM image with a pixel-to-pixel noise
% correlation of 0.4), the resolution is reported at the pixel limit and the
% horizontal damping appears as an astigmatism at 0 degrees (ratio about 1.9).
% Detection, always on: ``noiseAnisotropy`` is the mean power at the highest
% vertical frequencies (top and bottom 20 % of the spectrum, horizontal
% frequency within 20 % of the axis) over the mean power of the same band
% turned by 90 degrees, both excluding the frequency axes. White noise gives
% 1.00 +- 0.05; first-order detector responses with a noise correlation of
% 0.4 and 0.6 give 4.7 and 11.3, the real images 10-19. Signal that reaches the
% vertical Nyquist frequency also raises the ratio (strong astigmatism with a
% sharp vertical direction: up to 138; every second row of a sharp image:
% 20), but it falls off towards Nyquist while noise stays flat, so
% ``acrossFlatness``, the mean power in the inner half of the vertical band
% over that in the outer half, is 1.40-1.86 for those cases and
% 0.69-1.03 for every detector case tested. ``correlatedNoise`` is set when
% ``noiseAnisotropy > 2`` and ``acrossFlatness < 1.2``.
%
% Correction, ``SlowDetector``: the noise power is estimated for every
% horizontal frequency, as the mean over the spectrum rows of the top and
% bottom 20 % of vertical frequencies, where an image with independent lines
% carries noise only (the centre column, which holds the scan-line stripes,
% is interpolated; the profile is smoothed over 9 columns). Every spectrum
% pixel is compared with the noise of its own column: the radial profile and
% each sector use the mean noise over the same pixels as the power. As the
% detector filters signal and noise alike, the signal-to-noise ratio per
% frequency, and so the cutoff, are those of the image before the detector:
% on synthetic images with detector correlations of 0.4 and 0.6 the
% resolution and astigmatism equal those of the same image with white noise
% within 1 %, against 2-3 px and ratios of 2.7-3.4 without the correction.
% The noise SD is that of the recorded image, i.e. after the detector (SD of
% the filtered noise within 1 %). Requirements: horizontal scan lines and
% no detail at the highest vertical frequencies. Periodic line jitter puts
% power into the same band and is counted as noise; on real SEM images
% with jitter this raised the noise SD by up to 8 % over the line-to-line
% autocorrelation estimate. On white noise the correction gives the corner
% result. Measurements: development/sharpness/plan_sharpness.md.
%
% Other images whose noise is not white (line averaging, compressed,
% denoised or resampled images) carry less noise power at high frequencies:
% the floor is too low, the SNR too high (5-9x for a 3-pixel smoothing
% kernel) and, through the same floor, the resolution too optimistic.
%
% The cutoff depends on the noise level as well as on blur: with the same
% beam, a longer dwell time lowers the floor and raises the cutoff. Compare
% values between images of the same kind of specimen recorded with similar
% dose. Oriented structures (membranes, fibres, edges of a grid bar) produce
% an elongated spectrum and a false astigmatism; regions should contain
% isotropic texture.
%
% Input Arguments:
%   - **periodicImage** - [double, 2D] zero-mean region, normally the output
%     of :func:`controllers.ImageSharpness.preprocessRegion`
%   - **pixelSize** - [numeric] pixel size ``[x, y]`` in physical units, ``x``
%     along columns, ``y`` along rows; a scalar is used for both
%   - **options** *(optional)* - struct with fields:
%
%     - ``.SnrThreshold`` - [numeric] signal-to-noise power ratio that defines
%       the cutoff (default: ``1``, signal power equals noise power)
%     - ``.NumberOfSectors`` - [numeric] number of angular sectors over
%       0-180 degrees, at least 4; ``0`` skips the directional analysis
%       (default: ``36``). The dialog allows up to 72: with 180 sectors (2
%       degrees wide) a 512 px region still gave single directions with
%       cutoffs near zero, as the sectors hold too few pixels per radial bin.
%     - ``.SuppressScanLines`` - [logical] exclude the horizontal and vertical
%       frequency axes (default: ``true``)
%     - ``.SlowDetector`` - [logical] noise floor per horizontal frequency,
%       for images whose noise the detector smears along the scan lines
%       (default: ``false``)
%
% Output Arguments:
%   - **result** - struct with fields:
%
%     - ``.resolution`` - [double] ``1/cutoffFrequency``, physical units of
%       ``pixelSize``
%     - ``.resolutionPixels`` - [double] resolution in pixels (of the larger
%       pixel side)
%     - ``.cutoffFrequency`` - [double] cycles per physical unit
%     - ``.pixelLimited`` - [logical] the spectrum stays above the threshold up
%       to Nyquist
%     - ``.nyquistFrequency`` - [double] ``1/(2*max(pixelSize))``
%     - ``.noiseFloor`` - [double] mean noise power per spectrum pixel, i.e.
%       the noise variance; with ``SlowDetector`` the mean of the noise
%       profile over the whole spectrum
%     - ``.noiseSd`` - [double] noise standard deviation in intensity units
%       of the image, ``sqrt(noiseFloor)``
%     - ``.signalToNoise`` - [double] signal-to-noise power ratio,
%       ``(variance - noiseFloor) / noiseFloor``, where ``variance`` is the
%       variance of ``periodicImage``
%     - ``.noiseAnisotropy`` - [double] high-frequency power across the scan
%       lines over that along them, 1 for white noise
%     - ``.acrossFlatness`` - [double] power in the inner over the outer half
%       of the band across the lines, about 1 for noise
%     - ``.correlatedNoise`` - [logical] the noise is smeared along the scan
%       lines (slow detector), computed with and without ``SlowDetector``
%     - ``.frequency`` - [double, vector] radial bin centres
%     - ``.radialPower`` - [double, vector] radially averaged power, not smoothed
%     - ``.radialNoise`` - [double, vector] noise floor per bin, smoothed like
%       the power; constant unless ``SlowDetector``
%     - ``.snr`` - [double, vector] smoothed signal-to-noise ratio per bin
%     - ``.sectorAngles`` - [double, vector] sector centres, degrees
%     - ``.sectorCutoff`` - [double, vector] cutoff frequency per sector
%     - ``.sectorResolution`` - [double, vector] ``1/sectorCutoff``
%     - ``.sectorPixelLimited`` - [logical, vector] sector reached Nyquist
%     - ``.bestResolution``, ``.worstResolution`` - [double] resolution along
%       the long and the short axis of the fitted ellipse
%     - ``.bestAngle``, ``.worstAngle`` - [double] directions of those axes,
%       degrees; ``worstAngle`` is the most blurred direction
%     - ``.astigmatismRatio`` - [double] ``worstResolution/bestResolution``,
%       ``>= 1``
%     - ``.ellipseCoefficients`` - [double] ``[A B C]``, empty when the fit
%       failed
%     - ``.spectrumImage`` - [single, 2D] ``log10`` power spectrum, centred,
%       reduced to at most 512 x 512 pixels for display
%     - ``.spectrumFrequencyX``, ``.spectrumFrequencyY`` - [double] frequency
%       limits of ``spectrumImage``, ``[min max]``
%
% **Example** - resolution of the central 512 x 512 pixels of a slice with 5 nm pixels:
%
%   .. code-block:: matlab
%
%      region = controllers.ImageSharpness.preprocessRegion(img(1:512, 1:512));
%      result = controllers.ImageSharpness.computeFftResolution(region, [5 5]);
%      fprintf('%.1f nm, astigmatism %.2f at %.0f deg\n', result.resolution, result.astigmatismRatio, result.worstAngle);
%
% References:
%   - Postek M.T., Vladar A.E. (1998) Image sharpness measurement in scanning
%     electron microscopy - Part I. Scanning 20, 1-9.
%     https://doi.org/10.1002/sca.1998.4950200101
%   - Vladar A.E., Postek M.T., Davidson M.P. (1998) Image sharpness
%     measurement in scanning electron microscopy - Part II. Scanning 20, 24-34.
%

% Updates
%

if nargin < 3; options = struct(); end
if ~isfield(options, 'SnrThreshold'); options.SnrThreshold = 1; end
if ~isfield(options, 'NumberOfSectors'); options.NumberOfSectors = 36; end
if ~isfield(options, 'SuppressScanLines'); options.SuppressScanLines = true; end
if ~isfield(options, 'SlowDetector'); options.SlowDetector = false; end
if isscalar(pixelSize); pixelSize = [pixelSize pixelSize]; end
if options.NumberOfSectors > 0 && options.NumberOfSectors < 4
    error('MIB:ImageSharpness:WrongParameter', 'NumberOfSectors should be 0 or at least 4');
end

[height, width] = size(periodicImage);
spectrum = fftshift(fft2(periodicImage));
powerSpectrum = abs(spectrum).^2 / (height*width);

% frequency grid in cycles per physical unit, DC at floor(n/2)+1
frequencyX = ((0:width-1) - floor(width/2)) / (width * pixelSize(1));
frequencyY = ((0:height-1) - floor(height/2)) / (height * pixelSize(2));
[gridX, gridY] = meshgrid(frequencyX, frequencyY);
radius = hypot(gridX, gridY);
% screen angle: rows grow downwards, so the y frequency is negated
angle = mod(atan2(-gridY, gridX), pi);

nyquistFrequency = 1 / (2*max(pixelSize));
validPixels = true(height, width);
if options.SuppressScanLines
    validPixels(floor(height/2)+1, :) = false;
    validPixels(:, floor(width/2)+1) = false;
end

% noise floor from the corners outside the Nyquist circle
cornerPixels = validPixels & radius > nyquistFrequency;
if nnz(cornerPixels) < 100
    cornerPixels = validPixels & radius > 0.85*nyquistFrequency & radius <= nyquistFrequency;
end
noiseFloor = mean(powerSpectrum(cornerPixels));

% noise power at the highest frequencies across the scan lines (vertical)
% and along them (horizontal), away from the frequency axes; equal for
% white noise, higher across the lines when the detector smears the noise
% along them. The flatness of the power across the lines tells noise (flat)
% from signal that reaches the vertical Nyquist frequency (falling).
maxFrequencyX = max(abs(frequencyX));
maxFrequencyY = max(abs(frequencyY));
offAxes = gridX ~= 0 & gridY ~= 0;
acrossLines = offAxes & abs(gridY) >= 0.8*maxFrequencyY & abs(gridX) <= 0.2*maxFrequencyX;
alongLines = offAxes & abs(gridX) >= 0.8*maxFrequencyX & abs(gridY) <= 0.2*maxFrequencyY;
noiseAnisotropy = mean(powerSpectrum(acrossLines)) / mean(powerSpectrum(alongLines));
acrossFlatness = mean(powerSpectrum(acrossLines & abs(gridY) < 0.9*maxFrequencyY)) / ...
    mean(powerSpectrum(acrossLines & abs(gridY) >= 0.9*maxFrequencyY));

insidePixels = validPixels & radius <= nyquistFrequency;

if options.SlowDetector
    % noise power for every horizontal frequency, from the spectrum rows of
    % the highest vertical frequencies; the centre column carries
    % scan-line stripes and is interpolated
    noiseRows = abs(frequencyY) >= 0.8*maxFrequencyY;
    noiseProfile = mean(powerSpectrum(noiseRows, :), 1);
    noiseProfile(floor(width/2)+1) = NaN;
    noiseProfile = movmean(fillmissing(noiseProfile, 'linear'), 9);
    noiseVariance = mean(noiseProfile);
    [~, insideColumns] = find(insidePixels);
    insideNoise = noiseProfile(insideColumns)';
else
    noiseVariance = noiseFloor;
    insideNoise = noiseFloor;
end

% full radial profile
numberOfBins = floor(min(height, width) / 2);
[frequency, radialPower, snr, cutoffFrequency, pixelLimited, radialNoise] = radialCutoff( ...
    radius(insidePixels), powerSpectrum(insidePixels), numberOfBins, nyquistFrequency, ...
    insideNoise, options.SnrThreshold);

result.resolution = 1 / cutoffFrequency;
result.resolutionPixels = result.resolution / max(pixelSize);
result.cutoffFrequency = cutoffFrequency;
result.pixelLimited = pixelLimited;
result.nyquistFrequency = nyquistFrequency;
result.noiseFloor = noiseVariance;
% mean noise power per spectrum pixel = noise variance (Parseval, power
% normalised per pixel)
totalVariance = mean(periodicImage(:).^2);
result.noiseSd = sqrt(noiseVariance);
result.signalToNoise = max(totalVariance - noiseVariance, 0) / noiseVariance;
result.noiseAnisotropy = noiseAnisotropy;
result.acrossFlatness = acrossFlatness;
result.correlatedNoise = noiseAnisotropy > 2 && acrossFlatness < 1.2;
result.frequency = frequency;
result.radialPower = radialPower;
result.radialNoise = radialNoise;
result.snr = snr;

% directional analysis
result.sectorAngles = [];
result.sectorCutoff = [];
result.sectorResolution = [];
result.sectorPixelLimited = [];
result.bestResolution = NaN;
result.worstResolution = NaN;
result.bestAngle = NaN;
result.worstAngle = NaN;
result.astigmatismRatio = NaN;
result.ellipseCoefficients = [];
if options.NumberOfSectors > 0
    numberOfSectors = options.NumberOfSectors;
    sectorAngles = (0:numberOfSectors-1) * pi / numberOfSectors;
    halfWidth = pi / numberOfSectors;
    sectorCutoff = zeros(1, numberOfSectors);
    sectorPixelLimited = false(1, numberOfSectors);
    insideRadius = radius(insidePixels);
    insidePower = powerSpectrum(insidePixels);
    insideAngle = angle(insidePixels);
    for sectorId = 1:numberOfSectors
        angleDifference = abs(mod(insideAngle - sectorAngles(sectorId) + pi/2, pi) - pi/2);
        inSector = angleDifference <= halfWidth;
        sectorNoise = insideNoise;
        if ~isscalar(sectorNoise); sectorNoise = sectorNoise(inSector); end
        [~, ~, ~, sectorCutoff(sectorId), sectorPixelLimited(sectorId)] = radialCutoff( ...
            insideRadius(inSector), insidePower(inSector), max(8, floor(numberOfBins/2)), ...
            nyquistFrequency, sectorNoise, options.SnrThreshold);
    end
    result.sectorAngles = sectorAngles * 180 / pi;
    result.sectorCutoff = sectorCutoff;
    result.sectorResolution = 1 ./ sectorCutoff;
    result.sectorPixelLimited = sectorPixelLimited;

    % ellipse fit A*x^2 + B*y^2 + C*x*y = 1 in the frequency plane
    pointX = sectorCutoff .* cos(sectorAngles);
    pointY = sectorCutoff .* sin(sectorAngles);
    designMatrix = [pointX(:).^2, pointY(:).^2, pointX(:).*pointY(:)];
    coefficients = designMatrix \ ones(numberOfSectors, 1);
    quadraticForm = [coefficients(1), coefficients(3)/2; coefficients(3)/2, coefficients(2)];
    [eigenVectors, eigenValues] = eig(quadraticForm);
    eigenValues = diag(eigenValues);
    if all(eigenValues > 0)
        [~, order] = sort(eigenValues);   % small eigenvalue = long axis = best direction
        longAxisFrequency = 1 / sqrt(eigenValues(order(1)));
        shortAxisFrequency = 1 / sqrt(eigenValues(order(2)));
        bestVector = eigenVectors(:, order(1));
        worstVector = eigenVectors(:, order(2));
        result.bestResolution = 1 / longAxisFrequency;
        result.worstResolution = 1 / shortAxisFrequency;
        result.bestAngle = mod(atan2(bestVector(2), bestVector(1)) * 180/pi, 180);
        result.worstAngle = mod(atan2(worstVector(2), worstVector(1)) * 180/pi, 180);
        result.ellipseCoefficients = coefficients(:)';
    else
        [maxCutoff, maxIndex] = max(sectorCutoff);
        [minCutoff, minIndex] = min(sectorCutoff);
        result.bestResolution = 1 / maxCutoff;
        result.worstResolution = 1 / minCutoff;
        result.bestAngle = result.sectorAngles(maxIndex);
        result.worstAngle = result.sectorAngles(minIndex);
    end
    result.astigmatismRatio = result.worstResolution / result.bestResolution;
end

% spectrum for display
displaySpectrum = log10(powerSpectrum + eps);
maxDisplaySize = 512;
if max(height, width) > maxDisplaySize
    scaleFactor = maxDisplaySize / max(height, width);
    displaySpectrum = imresize(displaySpectrum, scaleFactor, 'box');
end
result.spectrumImage = single(displaySpectrum);
result.spectrumFrequencyX = [frequencyX(1) frequencyX(end)];
result.spectrumFrequencyY = [frequencyY(1) frequencyY(end)];
end

% -------------------------------------------------------------------------
function [binCentres, radialPower, snr, cutoffFrequency, pixelLimited, radialNoise] = radialCutoff( ...
    radiusValues, powerValues, numberOfBins, nyquistFrequency, noiseValues, snrThreshold)
% RADIALCUTOFF - Radial average of power and the frequency where it reaches the noise floor.
%
% Bins are equally spaced from 0 to ``nyquistFrequency``. Empty bins are
% filled by linear interpolation before smoothing; empty bins at either end
% take the nearest filled value. The cutoff is the first
% downward crossing of ``snrThreshold`` at or after the third bin after which
% the ratio stays below the threshold for three bins; the first bins hold few
% pixels and the zero-mean region has no power at DC.

binEdges = linspace(0, nyquistFrequency, numberOfBins + 1);
binCentres = (binEdges(1:end-1) + binEdges(2:end)) / 2;
binIndex = discretize(radiusValues, binEdges);
keep = ~isnan(binIndex);
radialPower = accumarray(binIndex(keep), powerValues(keep), [numberOfBins 1], @mean, NaN)';

filledBins = ~isnan(radialPower);
if nnz(filledBins) < 2
    snr = nan(1, numberOfBins);
    radialNoise = nan(1, numberOfBins);
    cutoffFrequency = nyquistFrequency;
    pixelLimited = true;
    return;
end
% gaps inside the range are interpolated; empty bins at the ends (narrow
% sectors have no pixels at the lowest radii) take the nearest value, as an
% extrapolation could fall below the noise floor and fake a cutoff
filledPower = fillmissing(radialPower, 'linear', 'SamplePoints', binCentres, 'EndValues', 'nearest');
smoothedPower = movmean(filledPower, 5);
if isscalar(noiseValues)
    radialNoise = noiseValues * ones(1, numberOfBins);
else
    % noise that changes with direction: mean over the same pixels as the power
    radialNoise = accumarray(binIndex(keep), noiseValues(keep), [numberOfBins 1], @mean, NaN)';
    radialNoise = movmean(fillmissing(radialNoise, 'linear', 'SamplePoints', binCentres, 'EndValues', 'nearest'), 5);
end
snr = (smoothedPower - radialNoise) ./ radialNoise;

firstBin = min(3, numberOfBins);
% first bin from which the ratio stays below the threshold for 3 bins; a
% single noisy bin of a narrow sector would otherwise end the search early
below = snr < snrThreshold;
sustainedBelow = below;
for offset = 1:2
    sustainedBelow(1:end-offset) = sustainedBelow(1:end-offset) & below(1+offset:end);
end
belowIndex = find(sustainedBelow(firstBin:end), 1, 'first') + firstBin - 1;
if isempty(belowIndex)
    cutoffFrequency = nyquistFrequency;
    pixelLimited = true;
elseif belowIndex == firstBin
    cutoffFrequency = binCentres(firstBin);
    pixelLimited = false;
else
    % linear interpolation of the crossing between the two bins
    snrAbove = snr(belowIndex-1);
    snrBelow = snr(belowIndex);
    fraction = (snrAbove - snrThreshold) / (snrAbove - snrBelow);
    cutoffFrequency = binCentres(belowIndex-1) + fraction * (binCentres(belowIndex) - binCentres(belowIndex-1));
    pixelLimited = false;
end
end
