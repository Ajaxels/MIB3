classdef FloatImageConversionTest < matlab.unittest.TestCase
% Unit tests for io.loaders.BaseImageLoader.convertFloatImage.
%
% MIB operates with integer images, so floating point data coming from a loader
% is converted to uint16 during loading. Two modes exist and picking the wrong
% one is silent: stretching a detector that stores integer counts as floats
% (TEM cameras) rewrites every intensity, while truncating normalized 0-1 data
% collapses the image to a 0/1 bitmap.
%
% The tests run with ``silentMode`` on, i.e. they assert on the mode that
% convertFloatImage *suggests* - which is what a user loading a dataset sees
% preselected in the conversion dialog.

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Access = private)
        function [img, imginfo] = convertSilently(~, floatImage)
            % convert with the dialog suppressed, i.e. apply the suggested mode
            imginfo = dictionary();
            imginfo{'viewPort'} = struct('min', 0, 'max', realmax('single'), 'gamma', 1);
            loader = mibtest.helpers.FloatConversionLoader();
            [img, imginfo] = loader.convert(floatImage, imginfo, struct('silentMode', true));
        end
    end

    methods (Test, TestTags = {'Unit'})

        function counts_storedAsFloat_areTruncatedNotStretched(testCase)
            % a TEM camera frame: integer counts in a float container, the
            % intensities must survive the conversion unchanged
            floatImage = single(3976.51) + single(4069) * rand(16, 24, 3, 'single');
            [img, ~] = testCase.convertSilently(floatImage);

            testCase.verifyClass(img, 'uint16');
            testCase.verifyEqual(img, uint16(fix(floatImage)), ...
                'float counts must be truncated, not rescaled');
        end

        function normalized01Data_isStretchedOverFullRange(testCase)
            floatImage = single(rand(16, 24, 'single'));
            floatImage(1) = 0;  floatImage(end) = 1;
            [img, ~] = testCase.convertSilently(floatImage);

            testCase.verifyEqual(min(img(:)), uint16(0));
            testCase.verifyEqual(max(img(:)), uint16(65535));
            testCase.verifyGreaterThan(numel(unique(img(:))), 100, ...
                '0-1 data must be stretched, truncation would leave 2 intensities');
        end

        function narrowFloatRange_isStretched(testCase)
            % 0-3.7 fits into uint16 but truncation would leave 4 grey levels
            floatImage = single(3.7) * rand(16, 24, 'single');
            [img, ~] = testCase.convertSilently(floatImage);

            testCase.verifyGreaterThan(numel(unique(img(:))), 100);
        end

        function negativeValues_areStretchedNotClipped(testCase)
            floatImage = single(-500) + single(2000) * rand(16, 24, 'single');
            [img, ~] = testCase.convertSilently(floatImage);

            testCase.verifyEqual(min(img(:)), uint16(0));
            testCase.verifyEqual(max(img(:)), uint16(65535), ...
                'negative values must be shifted into the uint16 range, not clipped to 0');
        end

        function rangeWiderThanUint16_isStretched(testCase)
            floatImage = single(70000) * rand(16, 24, 'single');
            [img, ~] = testCase.convertSilently(floatImage);

            testCase.verifyEqual(max(img(:)), uint16(65535));
            testCase.verifyGreaterThan(numel(unique(img(:))), 100);
        end

        function flatImage_doesNotDivideByZero(testCase)
            [img, ~] = testCase.convertSilently(zeros(8, 8, 'single'));

            testCase.verifyClass(img, 'uint16');
            testCase.verifyTrue(all(img(:) == 0));
        end

        function imginfo_isSyncedWithTheNewClass(testCase)
            floatImage = single(3976.51) + single(4069) * rand(8, 8, 'single');
            [~, imginfo] = testCase.convertSilently(floatImage);

            testCase.verifyEqual(imginfo{'imgClass'}, 'uint16');
            testCase.verifyEqual(imginfo{'MaxInt'}, 65535);
            viewPort = imginfo{'viewPort'};
            testCase.verifyEqual(viewPort.min, 0);
            testCase.verifyEqual(viewPort.max, 65535, ...
                'viewPort.max must drop from the float ceiling to the uint16 one');
        end

        function doublePrecisionInput_isAlsoConverted(testCase)
            floatImage = 3976.51 + 4069 * rand(8, 8);
            [img, ~] = testCase.convertSilently(floatImage);

            testCase.verifyClass(img, 'uint16');
            testCase.verifyEqual(img, uint16(fix(floatImage)));
        end
    end
end
