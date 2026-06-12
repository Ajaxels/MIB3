classdef AddFrameTest < matlab.unittest.TestCase
% Tests for MibDataset.addFrame and MibDataset.addFrameToImage.
%
% addFrame: pads or trims all sides by dX / dY pixels.
% addFrameToImage: resizes canvas to an absolute W×H, placing the image at a named position.
%
% Both methods take BatchOpt + parentFigure ([] suppresses the progress dialog).
%
% Verification strategies:
%   addFrame both    — h grows by 2*extH, w grows by 2*extW
%   addFrame pre     — only one side is added
%   addFrame content — original pixels survive inside the padded region
%   addFrameToImage  — canvas reaches target dimensions
%   addFrameToImage offset — original pixels placed at expected position

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function addFrame_both_expandsDimensions(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 4]);

            batchOpt = AddFrameTest.makeAddFrameOpt(8, 10, 0, 'both');
            mibModel.I{1}.addFrame(batchOpt, []);

            testCase.verifyEqual(mibModel.I{1}.image.height, 32, ...
                'height must grow by 2*extH=16 after direction=both');
            testCase.verifyEqual(mibModel.I{1}.image.width,  44, ...
                'width must grow by 2*extW=20 after direction=both');
            testCase.verifyEqual(mibModel.I{1}.image.depth,   4, ...
                'depth must be unchanged');
        end

        function addFrame_pre_oneSideExpands(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 4]);

            batchOpt = AddFrameTest.makeAddFrameOpt(5, 5, 0, 'pre');
            mibModel.I{1}.addFrame(batchOpt, []);

            testCase.verifyEqual(mibModel.I{1}.image.height, 21, ...
                'height must grow by exactly extH=5 with direction=pre');
            testCase.verifyEqual(mibModel.I{1}.image.width,  29, ...
                'width must grow by exactly extW=5 with direction=pre');
        end

        function addFrame_contentPreserved_insidePaddedRegion(testCase)
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 4]);
            originalPx = groundTruth.image(4, 7, 1, 1, 1);

            % extH=8, extW=10, direction=both → original at rows 9:24, cols 11:34
            batchOpt = AddFrameTest.makeAddFrameOpt(8, 10, 0, 'both');
            mibModel.I{1}.addFrame(batchOpt, []);

            newData  = mibModel.I{1}.image.data;
            testCase.verifyEqual(newData(4+8, 7+10, 1, 1, 1), originalPx, ...
                'original pixel (4,7) must appear at (12,17) after 8-row/10-col both-side frame');
        end

        function addFrameToImage_centerExpandsDimensions(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 4]);

            batchOpt = AddFrameTest.makeAddFrameToImageOpt('Center', 44, 36, 0);
            mibModel.I{1}.addFrameToImage(batchOpt, []);

            testCase.verifyEqual(mibModel.I{1}.image.height, 36, ...
                'addFrameToImage must produce the requested canvas height');
            testCase.verifyEqual(mibModel.I{1}.image.width,  44, ...
                'addFrameToImage must produce the requested canvas width');
        end

        function addFrameToImage_centerPlacesContentAtCorrectOffset(testCase)
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 4]);
            originalPx = groundTruth.image(4, 7, 1, 1, 1);

            % Center a 16x24 image in 36x44 canvas:
            %   leftFrame = round((44-24)/2) = 10
            %   topFrame  = round((36-16)/2) = 10
            batchOpt = AddFrameTest.makeAddFrameToImageOpt('Center', 44, 36, 0);
            mibModel.I{1}.addFrameToImage(batchOpt, []);

            newData = mibModel.I{1}.image.data;
            testCase.verifyEqual(newData(4+10, 7+10, 1, 1, 1), originalPx, ...
                'original pixel (4,7) must appear at (14,17) after centering in a 36x44 canvas');
        end

    end

    methods (Static, Access = private)

        function batchOpt = makeAddFrameOpt(extH, extW, padValue, direction)
            batchOpt.FrameWidth          = {extW, [-Inf Inf], 'on'};
            batchOpt.FrameHeight         = {extH, [-Inf Inf], 'on'};
            batchOpt.IntensityPadValue   = {padValue, [0 Inf], 'off'};
            batchOpt.Method              = {'use the pad value'};
            batchOpt.Direction           = {direction};
            batchOpt.showWaitbar         = false;
        end

        function batchOpt = makeAddFrameToImageOpt(position, newWidth, newHeight, frameColor)
            batchOpt.Position             = {position};
            batchOpt.NewImageWidth        = {newWidth,  [1 Inf], 'on'};
            batchOpt.NewImageHeight       = {newHeight, [1 Inf], 'on'};
            batchOpt.FrameColorIntensity  = {frameColor, [0 Inf], 'off'};
            batchOpt.showWaitbar          = false;
        end

    end
end
