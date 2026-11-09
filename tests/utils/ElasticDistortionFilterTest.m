classdef ElasticDistortionFilterTest < matlab.unittest.TestCase
% ELASTICDISTORTIONFILTERTEST - utils.elasticDistortionFilter: the displacement field of Simard et al.
%
% The field is uniform noise smoothed by a Gaussian of Sigma (kernel
% 2*ceil(2*Sigma)+1) times ScalingFactor: away from the border its spread is
% ScalingFactor * norm(kernel) / sqrt(3) pixels whatever the image size,
% it never exceeds ScalingFactor, and the dropped HSize field is not read.
%
% See also: utils.elasticDistortionFilter

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})
        function spreadDoesNotDependOnTheImageSize(testCase)
            settings = struct('ScalingFactor', {{30}}, 'Sigma', {{4}});
            kernel = fspecial('gaussian', 17, 4);       % 2*ceil(2*Sigma)+1
            expectedSpread = 30 * norm(kernel(:)) / sqrt(3);    % 1.30 px
            for side = [128 512]
                [~, field] = utils.elasticDistortionFilter(zeros(side, side, 'uint8'), settings, 0);
                inside = 9:side - 8;     % the replicate padding of the smoothing adds to the border
                testCase.verifyEqual(std(field.fdx(inside, inside), 0, 'all'), expectedSpread, 'RelTol', 0.1, sprintf('%d px', side));
                testCase.verifyEqual(std(field.fdy(inside, inside), 0, 'all'), expectedSpread, 'RelTol', 0.1, sprintf('%d px', side));
                testCase.verifyLessThanOrEqual(max(abs([field.fdx(:); field.fdy(:)])), 30);
            end
        end

        function edgesRepeat(testCase)
            % The positions are clamped to the image: a strong field never brings in black
            % from outside, and the values stay within those of the image.
            image = uint8(100 + repmat((0:99)', 1, 120));
            distorted = utils.elasticDistortionFilter(image, struct('ScalingFactor', {{200}}, 'Sigma', {{4}}), 1);
            testCase.verifyGreaterThanOrEqual(min(distorted(:)), min(image(:)));
            testCase.verifyLessThanOrEqual(max(distorted(:)), max(image(:)));
            testCase.verifyNotEqual(distorted, image, 'the image is distorted');
        end

        function hsizeIsNotRead(testCase)
            image = uint8(repmat(0:4:255, 64, 1));
            settings = struct('ScalingFactor', {{30}}, 'Sigma', {{4}});
            expected = utils.elasticDistortionFilter(image, settings, 3);
            settings.HSize = '7';
            testCase.verifyEqual(utils.elasticDistortionFilter(image, settings, 3), expected);
            testCase.verifyNotEqual(expected, image, 'the image is distorted');
        end
    end
end
