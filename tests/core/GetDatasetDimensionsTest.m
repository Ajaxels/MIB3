classdef GetDatasetDimensionsTest < matlab.unittest.TestCase
% GETDATASETDIMENSIONSTEST - Unit tests for MibDataset.getDatasetDimensions.
%
% Verification strategies:
%   splitDims=true  - five individual outputs match buildSyntheticModel dims
%   splitDims=false - single vector [h w d c t] output
%   orient=3 (YX)   - dimensions reported in the default XY orientation
%   mask/labels     - type argument accepted for non-image layers

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function getDims_image_splitDims_matchesBuildArgs(testCase)
            % The OUTPUT ORDER is load-bearing and differs from MIB2's. MIB2
            % returned [height width COLOR DEPTH time]; MIB3 returns
            % [height width DEPTH COLORS time]. segmentationSpot kept MIB2's
            % positions through the port and read the 4th output as the depth,
            % so every 3D spot came out one slice thick. Every dimension here is
            % distinct precisely so a swap cannot pass.
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [12 20 6]);

            [height, width, depth, colors, time] = ...
                mibModel.I{1}.getDatasetDimensions('image', 3, struct('blockModeSwitch', 0));

            testCase.verifyEqual(height, 12);
            testCase.verifyEqual(width,  20);
            testCase.verifyEqual(depth,   6, ...
                'depth is the THIRD output - MIB2 returned colour there');
            testCase.verifyEqual(colors,  1);
            testCase.verifyEqual(time,    1);
        end

        function getDims_nonImageLayersAlsoReportDepthThird(testCase)
            % The spot tool asks for 'selection'/'mask' dimensions, and those
            % layers are single-channel: reading the 4th output returns 1 for
            % ANY dataset, so the mistake looked like a plausible depth and only
            % showed up as a spot that painted one slice.
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [12 20 6]);
            dataset = mibModel.I{1};

            for layerType = {'selection', 'mask'}
                [~, ~, depth, colors] = dataset.getDatasetDimensions(layerType{1}, 3, ...
                    struct('blockModeSwitch', 0));
                testCase.verifyEqual(depth, 6, ...
                    sprintf('%s depth must be the third output', layerType{1}));
                testCase.verifyEqual(colors, 1);
            end
        end

        function getDims_throughAxisFollowsTheOrientation(testCase)
            % What a 3D spot spans: the axis perpendicular to the shown plane.
            % Distinct dims in all three axes, so an orientation mix-up cannot
            % pass unnoticed.
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [40 50 16]);
            dataset = mibModel.I{1};

            [~, ~, depthYX] = dataset.getDatasetDimensions('selection', 3, ...
                struct('blockModeSwitch', 0));
            [~, ~, depthZX] = dataset.getDatasetDimensions('selection', 1, ...
                struct('blockModeSwitch', 0));
            [~, ~, depthZY] = dataset.getDatasetDimensions('selection', 2, ...
                struct('blockModeSwitch', 0));

            testCase.verifyEqual(depthYX, 16, 'YX looks through Z');
            testCase.verifyEqual(depthZX, 40, 'ZX looks through Y (the height)');
            testCase.verifyEqual(depthZY, 50, 'ZY looks through X (the width)');
        end

        function getDims_image_splitDimsFalse_returnsVector(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [8 16 4]);

            opts.blockModeSwitch = 0;
            opts.splitDims = false;
            dims = mibModel.I{1}.getDatasetDimensions('image', 3, opts);

            testCase.verifyEqual(dims, [8, 16, 4, 1, 1], ...
                'splitDims=false must return a single [h w d c t] vector');
        end

        function getDims_labels_returnsDepthNotColors(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [8 8 5]);

            [~, ~, depth, ~, ~] = ...
                mibModel.I{1}.getDatasetDimensions('labels', 3, struct('blockModeSwitch', 0));

            testCase.verifyEqual(depth, 5, ...
                'getDatasetDimensions for labels must return the correct depth');
        end

        function getDims_blockMode_measuresTheShownSlices(testCase)
            % The shown block is dataset.slices, so only the DATASET can report
            % it. Snapshot and MakeMovie asked the image instead and threw
            % "Unrecognized method, property, or field 'slices'" out of the
            % UpdateGuiWidgets listener every time "Shown area" was ticked.
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [40 60 5]);
            dataset = mibModel.I{1};
            dataset.slices{1} = [10 25];    % 16 rows
            dataset.slices{2} = [ 5 34];    % 30 columns

            [height, width, depth] = dataset.getDatasetDimensions('image', 3, ...
                struct('blockModeSwitch', true));

            testCase.verifyEqual(height, 16);
            testCase.verifyEqual(width,  30);
            testCase.verifyEqual(depth,   5, 'block mode crops XY only, never Z');

            % Full dimensions are unaffected, so the two answers stay distinct.
            [fullHeight, fullWidth] = dataset.getDatasetDimensions('image', 3, ...
                struct('blockModeSwitch', false));
            testCase.verifyEqual([fullHeight, fullWidth], [40, 60]);
        end

        function getDims_imageRefusesBlockModeWithAnActionableError(testCase)
            % core.MibImage has no `slices`, so it CANNOT answer this - and the
            % old branch tried anyway, producing an error that named this file
            % rather than the caller that asked the wrong object. Refusing
            % loudly is required: silently returning the full dimensions would
            % hand a snapshot tool the wrong size and say nothing.
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel('dims', [16 16 3]);

            testCase.verifyError( ...
                @() mibModel.I{1}.image.getDatasetDimensions([], [], true), ...
                'MibImage:getDatasetDimensions:blockModeUnsupported');

            % The message has to say what to call instead.
            try
                mibModel.I{1}.image.getDatasetDimensions([], [], true);
            catch blockModeError
                testCase.verifySubstring(blockModeError.message, ...
                    'dataset.getDatasetDimensions');
            end

            % blockModeSwitch=false is the normal path and still works.
            [height, width] = mibModel.I{1}.image.getDatasetDimensions([], [], false);
            testCase.verifyEqual([height, width], [16, 16]);
        end

        function getDims_nanOrientIsTreatedAsTheDefault(testCase)
            % NaN is a MIB2 leftover several call sites still pass. It used to
            % fall through every branch with nothing assigned, so the failure
            % read "Unrecognized function or variable 'height'" - naming a local
            % variable instead of the argument that was wrong.
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel('dims', [12 20 6]);
            dataset = mibModel.I{1};

            [nanHeight, nanWidth, nanDepth] = dataset.getDatasetDimensions('image', NaN, ...
                struct('blockModeSwitch', 0));
            [refHeight, refWidth, refDepth] = dataset.getDatasetDimensions('image', [], ...
                struct('blockModeSwitch', 0));
            testCase.verifyEqual([nanHeight, nanWidth, nanDepth], ...
                [refHeight, refWidth, refDepth], 'NaN orient must mean "current", as [] does');

            [imgHeight, imgWidth] = dataset.image.getDatasetDimensions(NaN);
            testCase.verifyEqual([imgHeight, imgWidth], [12, 20]);

            % An orient that is neither empty, NaN, nor 1/2/3 is a real mistake
            % and must be named as one.
            testCase.verifyError(@() dataset.image.getDatasetDimensions(7), ...
                'MibImage:getDatasetDimensions:badOrient');
        end

    end
end
