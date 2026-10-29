function result = analyseRegion(regionImage, pixelSize, options)
% ANALYSEREGION - Run the selected sharpness and resolution measures on one image region.
%
% Syntax:
%   .. code-block:: matlab
%
%      result = controllers.ImageSharpness.analyseRegion(regionImage, pixelSize)
%      result = controllers.ImageSharpness.analyseRegion(regionImage, pixelSize, options)
%
% The region is preprocessed once with
% :func:`controllers.ImageSharpness.preprocessRegion` for the two Fourier
% methods; the focus scores use the raw intensities. Methods that are
% switched off return ``[]``.
%
% Input Arguments:
%   - **regionImage** - [numeric, 2D] one color channel, at least 64 x 64
%     pixels
%   - **pixelSize** - [numeric] ``[x, y]`` pixel size, x along columns; a
%     scalar is used for both
%   - **options** *(optional)* - struct with fields:
%
%     - ``.UseFft`` - [logical] FFT cutoff and astigmatism (default: ``true``)
%     - ``.UseDecorrelation`` - [logical] decorrelation analysis (default: ``true``)
%     - ``.UseSharpness`` - [logical] focus scores (default: ``true``)
%     - ``.SnrThreshold``, ``.NumberOfSectors``, ``.SuppressScanLines``,
%       ``.SlowDetector`` - passed to :func:`controllers.ImageSharpness.computeFftResolution`
%     - ``.SmoothingSigma`` - passed to
%       :func:`controllers.ImageSharpness.computeSharpnessScores` (default: ``1``)
%
% Output Arguments:
%   - **result** - struct with fields ``.fft``, ``.decorrelation`` and
%     ``.sharpness``, each the output of the corresponding ``compute*``
%     method or ``[]``. ``.fft`` gets one more field:
%
%     - ``.denoised`` - [logical] the noise SD is below one grey value at an
%       SNR above 100 (20 dB) in an integer image: the image was probably
%       denoised or smoothed. Both Fourier methods measure where the signal
%       sinks into the noise, and with almost no noise left that point is
%       at or near Nyquist: a denoised SBEM image with visibly less detail
%       than the raw image of the same specimen reported 20 nm
%       (pixel-limited) and 25 nm against 44 nm and 71 nm of the raw image,
%       although its signal power at 30-160 nm periods was 4-7x lower. Raw
%       detector noise is above one grey value, as digitisation is set up so
%       that the noise is not rounded away: the test stack and raw SEM
%       images give 16-5000. Rounding alone gives 0.29 (``sqrt(1/12)``),
%       which a Gaussian smoothing of sigma 1.5 px reaches. The SNR
%       condition keeps low-count images (photon counting, noise below one
%       count but also little signal) unflagged. Light denoising is not
%       detected: a 3 x 3 median filter of the raw SBEM image left a noise
%       SD of 3.7 at SNR 43. Not computed for floating-point images, whose
%       grey value has no fixed size.
%
% Errors:
%   - ``MIB:ImageSharpness:RegionTooSmall`` from ``preprocessRegion``
%
% **Example** - all measures of a 5 nm pixel image:
%
%   .. code-block:: matlab
%
%      result = controllers.ImageSharpness.analyseRegion(img, 5);
%      fprintf('FFT %.1f nm, decorrelation %.1f nm\n', result.fft.resolution, result.decorrelation.resolution);
%

% Updates
%

if nargin < 3; options = struct(); end
defaults = struct('UseFft', true, 'UseDecorrelation', true, 'UseSharpness', true, ...
    'SnrThreshold', 1, 'NumberOfSectors', 36, 'SuppressScanLines', true, 'SlowDetector', false, 'SmoothingSigma', 1);
defaultNames = fieldnames(defaults);
for fieldId = 1:numel(defaultNames)
    if ~isfield(options, defaultNames{fieldId})
        options.(defaultNames{fieldId}) = defaults.(defaultNames{fieldId});
    end
end

result = struct('fft', [], 'decorrelation', [], 'sharpness', []);
periodicImage = controllers.ImageSharpness.preprocessRegion(regionImage);
if options.UseFft
    fftOptions = struct('SnrThreshold', options.SnrThreshold, ...
        'NumberOfSectors', options.NumberOfSectors, 'SuppressScanLines', options.SuppressScanLines, ...
        'SlowDetector', options.SlowDetector);
    result.fft = controllers.ImageSharpness.computeFftResolution(periodicImage, pixelSize, fftOptions);
    result.fft.denoised = isinteger(regionImage) && result.fft.noiseSd < 1 && result.fft.signalToNoise > 100;
end
if options.UseDecorrelation
    result.decorrelation = controllers.ImageSharpness.computeDecorrelationResolution(periodicImage, pixelSize);
end
if options.UseSharpness
    result.sharpness = controllers.ImageSharpness.computeSharpnessScores(regionImage, options.SmoothingSigma);
end
end
