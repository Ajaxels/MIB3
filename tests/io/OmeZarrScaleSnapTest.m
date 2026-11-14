classdef OmeZarrScaleSnapTest < matlab.unittest.TestCase
% OMEZARRSCALESNAPTEST - Pyramid scale factors keep exact values after the division of voxel sizes.
%
% A level scale factor is a ratio of two voxel sizes read from the store. Powers of 2
% divide exactly, other factors (the isotropic level of an anisotropic stack: 6, 7, 2.6)
% do not, and the level map maps a full-resolution voxel to a level pixel with
% ``ceil(voxel / factor)``, so ``2.9999999999999996`` puts a voxel into the wrong pixel.
% ``OmeZarrMetadataUtils.snapRatio`` removes that noise and must leave genuine
% non-integer factors (a WSI pyramid) alone.

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})
        function testRatioIsExactForIntegerAndRationalFactors(testCase)
            % ratios whose floating-point division is not exact on its own
            baseSizes = [0.0053 0.0049 0.005 0.0041 0.0077 0.00123];
            factors = [3 6 7 2.6 5.2 10.4 1.5 13];
            for baseSize = baseSizes
                for factor = factors
                    levelScales = [0 0 baseSize * factor];   % index 3 is the axis under test
                    level0Scales = [0 0 baseSize];
                    ratio = io.loaders.OmeZarrMetadataUtils.safeRatio(levelScales, 3, level0Scales);
                    testCase.verifyEqual(ratio, factor, ...
                        sprintf('voxel %g, factor %g gave %.17g', baseSize, factor, ratio));
                end
            end
        end

        function testCeilMapsVoxelsToTheRightPixel(testCase)
            % the failure the snap exists for: ceil(3 / 2.9999999999999996) == 2
            testCase.verifyEqual(ceil(3 / io.loaders.OmeZarrMetadataUtils.snapRatio(2.9999999999999996)), 1);
            testCase.verifyEqual(ceil(3 / io.loaders.OmeZarrMetadataUtils.snapRatio(3.0000000000000004)), 1);
            testCase.verifyEqual(ceil(7 / io.loaders.OmeZarrMetadataUtils.snapRatio(6.999999999999999)), 1);
        end

        function testGenuineNonIntegerFactorIsUntouched(testCase)
            % a whole-slide pyramid whose levels are not multiples of 1/1000
            genuine = [4.0003 2.00051 15.7 1.00002];
            testCase.verifyEqual(io.loaders.OmeZarrMetadataUtils.snapRatio(genuine), genuine);
        end

        function testPowersOfTwoAndArraysAreUnchanged(testCase)
            factors = [1 2 4 8 16 32 64 128];
            testCase.verifyEqual(io.loaders.OmeZarrMetadataUtils.snapRatio(factors), factors);
            matrixIn = [1 1 1; 2 2 1; 4.0000000000000009 4 2.0000000000000004];
            testCase.verifyEqual(io.loaders.OmeZarrMetadataUtils.snapRatio(matrixIn), [1 1 1; 2 2 1; 4 4 2]);
        end

        function testFailureStillReturnsOne(testCase)
            % unchanged contract of safeRatio
            testCase.verifyEqual(io.loaders.OmeZarrMetadataUtils.safeRatio([], [], []), 1);
            testCase.verifyEqual(io.loaders.OmeZarrMetadataUtils.safeRatio([1 1 1], 3, [1 1 0]), 1);
        end
    end
end
