classdef ZXOrientationFrameTest < matlab.unittest.TestCase
% ZXORIENTATIONFRAMETEST - The ZX view keeps X horizontal: slices are [z, x].
%
% In the ZX orientation (orient = 1) getData/setData work with slices whose rows
% are Z and columns are X, so X runs horizontally as in the YX view. MIB2 and
% earlier MIB3 versions used [x, z]; every caller of orient 1 depends on this
% frame, so it is pinned here for the image, all three label containers, the
% subarea options, the write path and the reported dimensions.
%
% Every dimension is distinct (Y = 12, X = 20, Z = 6) so a transposed frame
% cannot pass by accident.

    properties (Constant)
        Dims = [12 20 6]   % [height (Y), width (X), depth (Z)]
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function imageVolumeIsZRowsXColumns(testCase)
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', testCase.Dims);
            volume = cell2mat(mibModel.I{1}.getData3D('image', 1, 1, 1, struct('blockModeSwitch', 0)));
            expected = permute(groundTruth.image(:,:,:,1), [3 2 1]);   % [z, x, y]
            testCase.verifyEqual(squeeze(volume), expected);
        end

        function labelVolumesAreZRowsXColumns(testCase)
            % MibLabels63 (bit-packed with mask/selection), MibLabels255 and
            % MibLabels65535 each implement their own permute
            for modelType = {'labels63', 'labels255', 'labels65535'}
                [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel( ...
                    'modelType', modelType{1}, 'dims', testCase.Dims);
                options = struct('blockModeSwitch', 0);
                labels = cell2mat(mibModel.I{1}.getData3D('labels', 1, 1, NaN, options));
                testCase.verifyEqual(double(squeeze(labels)), double(permute(groundTruth.labels, [3 2 1])), ...
                    sprintf('%s labels', modelType{1}));
                mask = cell2mat(mibModel.I{1}.getData3D('mask', 1, 1, NaN, options));
                testCase.verifyEqual(double(squeeze(mask)), double(permute(groundTruth.mask, [3 2 1])), ...
                    sprintf('%s mask', modelType{1}));
            end
        end

        function sliceAndSubareaOptions(testCase)
            % options.x is the horizontal range (X), options.y the vertical one (Z),
            % the slice number is Y
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', testCase.Dims);
            sliceY = 7;
            slice = cell2mat(mibModel.I{1}.getData2D('image', sliceY, 1, 1, struct('blockModeSwitch', 0)));
            testCase.verifyEqual(slice, squeeze(groundTruth.image(sliceY, :, :, 1)).');

            options = struct('blockModeSwitch', 0, 'x', [4 15], 'y', [2 5]);
            part = cell2mat(mibModel.I{1}.getData2D('image', sliceY, 1, 1, options));
            testCase.verifyEqual(part, squeeze(groundTruth.image(sliceY, 4:15, 2:5, 1)).');
        end

        function writeLandsAtDatasetXZ(testCase)
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', testCase.Dims);
            dataset = mibModel.I{1};
            options = struct('blockModeSwitch', 0);
            sliceY = 3;
            pattern = zeros(testCase.Dims(3), testCase.Dims(2), 'uint8');   % [z, x]
            pattern(2, 17) = 1;    % Z = 2, X = 17
            dataset.setData2D(pattern, 'selection', sliceY, 1, [], options);

            selection = cell2mat(dataset.getData3D('selection', 1, 3, [], options));   % [y, x, z]
            written = squeeze(selection(sliceY, :, :));    % [x, z]
            [xIndex, zIndex] = find(written);
            testCase.verifyEqual([xIndex, zIndex], [17, 2]);
            otherSlices = setdiff(1:testCase.Dims(1), sliceY);
            testCase.verifyEqual(selection(otherSlices, :, :), groundTruth.selection(otherSlices, :, :), ...
                'a ZX write must touch only its own Y slice');
        end

        function dimensionsAreZHeightXWidth(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', testCase.Dims);
            [height, width, depth] = mibModel.I{1}.getDatasetDimensions('image', 1, ...
                struct('blockModeSwitch', 0));
            testCase.verifyEqual([height, width, depth], testCase.Dims([3 2 1]));
        end

        function displayStretchFollowsZ(testCase)
            % Z is stretched vertically in ZX and horizontally in ZY
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', testCase.Dims);
            dataset = mibModel.I{1};
            dataset.image.pixSize.x = 2;
            dataset.image.pixSize.y = 2;
            dataset.image.pixSize.z = 8;
            [stretchX, stretchY] = dataset.getDisplayStretch(1);
            testCase.verifyEqual([stretchX, stretchY], [1 4]);
            [stretchX, stretchY] = dataset.getDisplayStretch(2);
            testCase.verifyEqual([stretchX, stretchY], [4 1]);
            [stretchX, stretchY] = dataset.getDisplayStretch(3);
            testCase.verifyEqual([stretchX, stretchY], [1 1]);
        end

        function roiFileFrameSwapIsOwnInverse(testCase)
            % .roi files keep ZX ROIs in the legacy [x, z] frame; only ZX entries change
            Data = struct('label', {'zx', 'yx'}, 'type', {'polygon', 'polygon'}, ...
                'X', {[1 2 3], [4 5 6]}, 'Y', {[7 8 9], [1 1 2]}, 'orientation', {1, 3}, ...
                'BoundingBox', {struct('x', [1 3], 'y', [7 9]), struct('x', [4 6], 'y', [1 2])});
            swapped = core.RoiRegion.swapZXAxes(Data);
            testCase.verifyEqual(swapped(1).X, [7 8 9]);
            testCase.verifyEqual(swapped(1).Y, [1 2 3]);
            testCase.verifyEqual(swapped(1).BoundingBox, struct('x', [7 9], 'y', [1 3]));
            testCase.verifyEqual(swapped(2), Data(2));
            testCase.verifyEqual(core.RoiRegion.swapZXAxes(swapped), Data);
        end

        function measureFileFrameSwapIsOwnInverse(testCase)
            circ = struct('xc', 5, 'yc', 9, 'R', 2);
            spline = struct('x', [1 2], 'y', [3 4]);
            Data = struct('X', {[1 2], [1 2]}, 'Y', {[3 4], [3 4]}, 'orientation', {1, 2}, ...
                'circ', {circ, circ}, 'spline', {spline, spline});
            swapped = core.Measurements.swapZXAxes(Data);
            testCase.verifyEqual([swapped(1).X; swapped(1).Y], [3 4; 1 2]);
            testCase.verifyEqual([swapped(1).circ.xc, swapped(1).circ.yc], [9 5]);
            testCase.verifyEqual([swapped(1).spline.x; swapped(1).spline.y], [3 4; 1 2]);
            testCase.verifyEqual(swapped(2), Data(2));
            testCase.verifyEqual(core.Measurements.swapZXAxes(swapped), Data);
        end
    end
end
