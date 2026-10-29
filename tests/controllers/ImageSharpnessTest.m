classdef ImageSharpnessTest < matlab.unittest.TestCase
% IMAGESHARPNESSTEST - Unit tests for the static analysis methods of controllers.ImageSharpness.
%
% Synthetic isotropic textures (1/f^2 power spectrum, like most microscopy
% images) are blurred with known Gaussian kernels; the tests check the
% behaviour the dialog relies on, not exact values:
%   - resolution estimates grow with blur, for both Fourier methods
%   - an isotropic blur gives no astigmatism, an elliptical blur gives the
%     right ratio direction and angle (screen angle, counterclockwise)
%   - scan-line stripes do not fake astigmatism when suppressed
%   - noise smeared along the scan lines by a slow detector is detected and
%     the correction restores the white-noise result; vertical detail is
%     not taken for it
%   - a strongly smoothed integer image is flagged as denoised
%   - physical pixel sizes scale the results, also when x and y differ
%   - small regions are refused; a sharp image is flagged as pixel-limited
%     and pure noise gives no resolution

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function resolutionGrowsWithBlur(testCase)
            texture = ImageSharpnessTest.makeTexture(256, 1);
            sigmas = [1 2 4];
            fftResolution = zeros(size(sigmas));
            decorrelationResolution = zeros(size(sigmas));
            gradientEnergy = zeros(size(sigmas));
            for sigmaId = 1:numel(sigmas)
                image = ImageSharpnessTest.blurAndNoise(texture, sigmas(sigmaId), 0.05, sigmaId);
                result = controllers.ImageSharpness.analyseRegion(image, 1);
                fftResolution(sigmaId) = result.fft.resolution;
                decorrelationResolution(sigmaId) = result.decorrelation.resolution;
                gradientEnergy(sigmaId) = result.sharpness.gradientEnergy;
            end
            testCase.verifyTrue(all(diff(fftResolution) > 0), ...
                sprintf('FFT resolution should grow with blur: %s', mat2str(fftResolution, 3)));
            testCase.verifyTrue(all(diff(decorrelationResolution) > 0), ...
                sprintf('Decorrelation resolution should grow with blur: %s', mat2str(decorrelationResolution, 3)));
            testCase.verifyTrue(all(diff(gradientEnergy) < 0), ...
                sprintf('Gradient energy should fall with blur: %s', mat2str(gradientEnergy, 3)));
            % both methods agree within a factor of 1.5 for a moderate blur
            testCase.verifyLessThan(abs(log(fftResolution(2)/decorrelationResolution(2))), log(1.5));
        end

        function isotropicBlurHasNoAstigmatism(testCase)
            texture = ImageSharpnessTest.makeTexture(256, 2);
            image = ImageSharpnessTest.blurAndNoise(texture, 2, 0.05, 1);
            result = controllers.ImageSharpness.computeFftResolution( ...
                controllers.ImageSharpness.preprocessRegion(image), 1);
            testCase.verifyLessThan(result.astigmatismRatio, 1.1);
        end

        function ellipticalBlurGivesRatioAndAngle(testCase)
            texture = ImageSharpnessTest.makeTexture(256, 3);
            for angle = [0 30 120]
                image = ImageSharpnessTest.blurAndNoise(texture, [3 1 angle], 0.05, angle);
                result = controllers.ImageSharpness.computeFftResolution( ...
                    controllers.ImageSharpness.preprocessRegion(image), 1);
                testCase.verifyGreaterThan(result.astigmatismRatio, 1.5, sprintf('angle %d', angle));
                angleError = abs(mod(result.worstAngle - angle + 90, 180) - 90);
                testCase.verifyLessThan(angleError, 5, ...
                    sprintf('worst direction %.1f instead of %d', result.worstAngle, angle));
            end
        end

        function scanLinesSuppressed(testCase)
            texture = ImageSharpnessTest.makeTexture(256, 4);
            image = ImageSharpnessTest.blurAndNoise(texture, 2, 0.05, 2);
            randomStream = RandStream('mt19937ar', 'Seed', 5);
            image = image + 0.3*std(image(:))*randn(randomStream, size(image, 1), 1);   % one offset per scan line
            periodicImage = controllers.ImageSharpness.preprocessRegion(image);
            withLines = controllers.ImageSharpness.computeFftResolution(periodicImage, 1, struct('SuppressScanLines', false));
            suppressed = controllers.ImageSharpness.computeFftResolution(periodicImage, 1, struct('SuppressScanLines', true));
            testCase.verifyGreaterThan(withLines.astigmatismRatio, 1.3);
            testCase.verifyLessThan(suppressed.astigmatismRatio, 1.1);
        end

        function pixelSizeScalesResults(testCase)
            texture = ImageSharpnessTest.makeTexture(256, 6);
            image = ImageSharpnessTest.blurAndNoise(texture, 2, 0.05, 3);
            inPixels = controllers.ImageSharpness.analyseRegion(image, 1);
            inNanometers = controllers.ImageSharpness.analyseRegion(image, 5);
            % a radius exactly on a bin edge may fall into the neighbouring bin after scaling
            testCase.verifyEqual(inNanometers.fft.resolution, 5*inPixels.fft.resolution, 'RelTol', 1e-3);
            testCase.verifyEqual(inNanometers.decorrelation.resolution, 5*inPixels.decorrelation.resolution, 'RelTol', 1e-9);
            testCase.verifyEqual(inNanometers.fft.resolutionPixels, inPixels.fft.resolutionPixels, 'RelTol', 1e-3);
        end

        function anisotropicPixelsAndNonSquareRegion(testCase)
            % every second row of an isotropic image: y pixel twice the x pixel, and
            % with that pixel size the spectrum must stay round and the resolution
            % in physical units must not change
            texture = ImageSharpnessTest.makeTexture(512, 7);
            image = ImageSharpnessTest.blurAndNoise(texture, 4, 0.05, 4);
            full = controllers.ImageSharpness.analyseRegion(image, 1);
            everySecondRow = controllers.ImageSharpness.analyseRegion(image(1:2:end, :), [1 2]);
            testCase.verifyEqual(everySecondRow.fft.nyquistFrequency, 1/(2*2), 'RelTol', 1e-12);
            testCase.verifyLessThan(everySecondRow.fft.astigmatismRatio, 1.15);
            testCase.verifyEqual(everySecondRow.fft.resolution, full.fft.resolution, 'RelTol', 0.15);
            testCase.verifyEqual(everySecondRow.decorrelation.resolution, full.decorrelation.resolution, 'RelTol', 0.15);
        end

        function sharpImageIsPixelLimitedAndNoiseHasNoPeak(testCase)
            % cameraman has sharp edges: signal above the noise floor up to Nyquist
            sharpImage = imread('cameraman.tif');
            fftResult = controllers.ImageSharpness.computeFftResolution( ...
                controllers.ImageSharpness.preprocessRegion(sharpImage), 1);
            testCase.verifyTrue(fftResult.pixelLimited);
            testCase.verifyEqual(fftResult.resolutionPixels, 2, 'RelTol', 1e-12);
            % pure white noise: no decorrelation peak and no FFT signal above the floor
            randomStream = RandStream('mt19937ar', 'Seed', 12);
            noiseImage = controllers.ImageSharpness.preprocessRegion(randn(randomStream, 256));
            decorrelationResult = controllers.ImageSharpness.computeDecorrelationResolution(noiseImage, 1);
            testCase.verifyTrue(isnan(decorrelationResult.resolution));
            fftResult = controllers.ImageSharpness.computeFftResolution(noiseImage, 1);
            testCase.verifyFalse(fftResult.pixelLimited);
            testCase.verifyGreaterThan(fftResult.resolutionPixels, 20);
        end

        function noiseEstimateMatchesKnownNoise(testCase)
            % white noise of known level on a sharp and on a blurred image
            texture = ImageSharpnessTest.makeTexture(512, 11);
            randomStream = RandStream('mt19937ar', 'Seed', 21);
            for blurSigma = [1 3]
                signal = ImageSharpnessTest.blurAndNoise(texture, blurSigma, 0, 1);
                signal = 50 * signal / std(signal(:));       % grey values
                for noiseSigma = [5 15 50]
                    noise = noiseSigma * randn(randomStream, size(signal));
                    trueSnr = var(signal(:)) / var(noise(:));
                    result = controllers.ImageSharpness.computeFftResolution( ...
                        controllers.ImageSharpness.preprocessRegion(signal + noise), 1);
                    label = sprintf('blur %d, noise %d', blurSigma, noiseSigma);
                    testCase.verifyEqual(result.noiseSd, noiseSigma, 'RelTol', 0.05, label);
                    testCase.verifyEqual(result.signalToNoise, trueSnr, 'RelTol', 0.1, label);
                end
            end
        end

        function slowDetectorIsDetectedAndCorrected(testCase)
            % a slow detector low-pass filters signal and noise along the scan
            % line (first-order response, pixel-to-pixel noise correlation 0.4);
            % the correction must give the resolution of the same image with
            % white noise and the noise SD of the recorded image
            texture = ImageSharpnessTest.makeTexture(512, 13);
            signal = ImageSharpnessTest.blurAndNoise(texture, 1.5, 0, 1);
            signal = signal / std(signal(:));
            randomStream = RandStream('mt19937ar', 'Seed', 31);
            noise = 0.3 * randn(randomStream, size(signal));
            detectorResponse = 0.4;
            detectorFilter = @(image) filter(1 - detectorResponse, [1 -detectorResponse], image, [], 2);
            whiteNoise = controllers.ImageSharpness.computeFftResolution( ...
                controllers.ImageSharpness.preprocessRegion(signal + noise), 1);
            slowImage = controllers.ImageSharpness.preprocessRegion(detectorFilter(signal + noise));
            uncorrected = controllers.ImageSharpness.computeFftResolution(slowImage, 1);
            corrected = controllers.ImageSharpness.computeFftResolution(slowImage, 1, struct('SlowDetector', true));

            testCase.verifyFalse(whiteNoise.correlatedNoise);
            testCase.verifyTrue(uncorrected.correlatedNoise);
            testCase.verifyTrue(corrected.correlatedNoise, 'detection must not depend on the correction');
            testCase.verifyLessThan(uncorrected.resolution, 0.7*whiteNoise.resolution);
            testCase.verifyGreaterThan(uncorrected.astigmatismRatio, 1.5);
            testCase.verifyEqual(corrected.resolution, whiteNoise.resolution, 'RelTol', 0.05);
            testCase.verifyLessThan(corrected.astigmatismRatio, 1.1);
            recordedNoise = detectorFilter(noise);
            testCase.verifyEqual(corrected.noiseSd, std(recordedNoise(:)), 'RelTol', 0.05);
            % on white noise the correction gives the corner floor result
            whiteCorrected = controllers.ImageSharpness.computeFftResolution( ...
                controllers.ImageSharpness.preprocessRegion(signal + noise), 1, struct('SlowDetector', true));
            testCase.verifyEqual(whiteCorrected.resolution, whiteNoise.resolution, 'RelTol', 0.02);
            testCase.verifyEqual(whiteCorrected.noiseSd, whiteNoise.noiseSd, 'RelTol', 0.02);
        end

        function verticalDetailIsNotSlowDetector(testCase)
            % detail up to the vertical Nyquist frequency also raises the power
            % across the scan lines, but falls off towards Nyquist: no warning
            texture = ImageSharpnessTest.makeTexture(512, 14);
            astigmatic = ImageSharpnessTest.blurAndNoise(texture, [3 0.5 0], 0.05, 1);
            result = controllers.ImageSharpness.computeFftResolution( ...
                controllers.ImageSharpness.preprocessRegion(astigmatic), 1);
            testCase.verifyGreaterThan(result.noiseAnisotropy, 2);
            testCase.verifyFalse(result.correlatedNoise, 'blur along x with a sharp y direction');
            sharp = ImageSharpnessTest.blurAndNoise(texture, 1, 0.05, 2);
            result = controllers.ImageSharpness.computeFftResolution( ...
                controllers.ImageSharpness.preprocessRegion(sharp(1:2:end, :)), [1 2]);
            testCase.verifyFalse(result.correlatedNoise, 'every second row of a sharp image');
        end

        function denoisedImageIsFlagged(testCase)
            % a smoothed uint8 image keeps only rounding noise in the spectrum
            % corners; raw images, floating-point images and low-count images
            % with little signal are not flagged
            texture = ImageSharpnessTest.makeTexture(512, 15);
            signal = ImageSharpnessTest.blurAndNoise(texture, 1.5, 0, 1);
            randomStream = RandStream('mt19937ar', 'Seed', 41);
            raw = 128 + 30*signal/std(signal(:)) + 15*randn(randomStream, size(signal));
            smoothed = imgaussfilt(raw, 2);
            options = struct('UseDecorrelation', false, 'UseSharpness', false);
            rawResult = controllers.ImageSharpness.analyseRegion(uint8(raw), 1, options);
            smoothedResult = controllers.ImageSharpness.analyseRegion(uint8(smoothed), 1, options);
            floatResult = controllers.ImageSharpness.analyseRegion(smoothed, 1, options);
            testCase.verifyFalse(rawResult.fft.denoised, sprintf('raw, noise SD %.3g', rawResult.fft.noiseSd));
            testCase.verifyTrue(smoothedResult.fft.denoised, sprintf('smoothed, noise SD %.3g, SNR %.3g', ...
                smoothedResult.fft.noiseSd, smoothedResult.fft.signalToNoise));
            testCase.verifyFalse(floatResult.fft.denoised, 'floating-point image');
            counts = uint8(rand(randomStream, size(signal)) < 0.2*(1 + 0.3*signal/std(signal(:))));
            countsResult = controllers.ImageSharpness.analyseRegion(counts, 1, options);
            testCase.verifyLessThan(countsResult.fft.noiseSd, 1);
            testCase.verifyFalse(countsResult.fft.denoised, 'low-count image');
            fftOff = controllers.ImageSharpness.analyseRegion(uint8(smoothed), 1, struct('UseFft', false));
            testCase.verifyEmpty(fftOff.fft);
        end

        function mergeResultsWithDifferentFields(testCase)
            % rows of an older version (no regionSource) combine with newer rows
            olderRows = struct('datasetName', {'a.tif', 'b.tif'}, 'regionName', {'Shown area', 'ROI 1'});
            newerRows = struct('datasetName', 'c.tif', 'regionSource', 'ROIs', 'regionName', 'ROI 2');
            merged = controllers.ImageSharpness.mergeResults(olderRows, newerRows);
            testCase.verifySize(merged, [3 1]);
            testCase.verifyEqual({merged.datasetName}, {'a.tif', 'b.tif', 'c.tif'});
            testCase.verifyEmpty(merged(1).regionSource);
            testCase.verifyEqual(merged(3).regionSource, 'ROIs');
            testCase.verifyEqual(controllers.ImageSharpness.mergeResults([], newerRows), newerRows);
        end

        function smallRegionIsRefused(testCase)
            testCase.verifyError(@() controllers.ImageSharpness.preprocessRegion(rand(50, 200)), ...
                'MIB:ImageSharpness:RegionTooSmall');
            testCase.verifyError(@() controllers.ImageSharpness.preprocessRegion(rand(64, 64, 3)), ...
                'MIB:ImageSharpness:NotTwoDimensional');
        end

        function periodicComponentRemovesBorderJump(testCase)
            % a linear ramp is entirely smooth: its periodic component is flat
            ramp = repmat(linspace(0, 100, 128), 128, 1) + repmat(linspace(0, 50, 128)', 1, 128);
            periodicImage = controllers.ImageSharpness.preprocessRegion(uint16(ramp));
            testCase.verifyLessThan(std(periodicImage(:)), 1);
            testCase.verifyEqual(mean(periodicImage(:)), 0, 'AbsTol', 1e-9);
        end

        function nanPixelsAndConstantRegion(testCase)
            texture = ImageSharpnessTest.makeTexture(128, 9);
            texture(1:10, 1:10) = NaN;
            result = controllers.ImageSharpness.analyseRegion(texture, 1);
            testCase.verifyTrue(isfinite(result.fft.resolution));
            testCase.verifyTrue(isfinite(result.sharpness.gradientEnergy));
            constant = controllers.ImageSharpness.computeSharpnessScores(ones(100));
            testCase.verifyTrue(isnan(constant.gradientEnergy));
        end

        function switchedOffMethodsReturnEmpty(testCase)
            texture = ImageSharpnessTest.makeTexture(128, 10);
            result = controllers.ImageSharpness.analyseRegion(texture, 1, ...
                struct('UseFft', false, 'UseDecorrelation', false));
            testCase.verifyEmpty(result.fft);
            testCase.verifyEmpty(result.decorrelation);
            testCase.verifyNotEmpty(result.sharpness);
        end
    end

    methods (Static)
        function texture = makeTexture(imageSize, seed)
            % isotropic random texture with a 1/f^2 power spectrum and sparse particles
            randomStream = RandStream('mt19937ar', 'Seed', seed);
            [frequencyX, frequencyY] = meshgrid(ifftshift((0:imageSize-1) - floor(imageSize/2)));
            radius = hypot(frequencyX, frequencyY);
            radius(1, 1) = 1;
            spectrum = (randn(randomStream, imageSize) + 1i*randn(randomStream, imageSize)) ./ radius;
            texture = real(ifft2(spectrum));
            texture = texture / std(texture(:)) + 3*double(rand(randomStream, imageSize) > 0.995);
        end

        function image = blurAndNoise(texture, sigma, noiseLevel, seed)
            % exact Gaussian blur in the Fourier domain plus white noise
            %
            % sigma: scalar for an isotropic blur, or [sigmaMajor sigmaMinor angle]
            % for a blur elongated along a screen angle in degrees (counterclockwise,
            % rows grow downwards). A spatial kernel is not used on purpose:
            % imgaussfilt truncates at 2 sigma, and the axis-aligned sidelobes of a
            % truncated square kernel are large enough for the directional analysis
            % to report them as astigmatism at low noise.
            if isscalar(sigma); sigma = [sigma sigma 0]; end
            [height, width] = size(texture);
            frequencyX = ifftshift((0:width-1) - floor(width/2)) / width;
            frequencyY = ifftshift((0:height-1) - floor(height/2))' / height;
            theta = sigma(3)*pi/180;
            alongMajor = frequencyX*cos(theta) - frequencyY*sin(theta);
            alongMinor = frequencyX*sin(theta) + frequencyY*cos(theta);
            transferFunction = exp(-2*pi^2*(sigma(1)^2*alongMajor.^2 + sigma(2)^2*alongMinor.^2));
            image = real(ifft2(fft2(texture) .* transferFunction));
            randomStream = RandStream('mt19937ar', 'Seed', 100 + seed);
            image = image + noiseLevel*std(image(:))*randn(randomStream, size(image));
        end
    end
end
