classdef StitchModelInstancesTest < matlab.unittest.TestCase
% STITCHMODELINSTANCESTEST - Unit tests for MibDataset.stitchModelInstances.
%
% Covers (MibDataset level, no GUI):
%   layer replacement       - labels become an indexed uint16 instance model
%   type-63 unpacking       - selection and mask survive the switch away from
%                             the bit-packed model, so getData2D('selection')
%                             keeps working after stitching (the packed layers
%                             live in bits 7-8 of obj.labels and are lost
%                             unless stitchModelInstances unpacks them first)

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        % -----------------------------------------------------------------
        % stitching result
        % -----------------------------------------------------------------

        function stitch_from63_producesTwoInstances(testCase)
            [mibModel, groundTruth] = StitchModelInstancesTest.buildInstanceStack('labels63');

            stats = mibModel.I{1}.stitchModelInstances();

            testCase.verifyEqual(stats.numOutput3DObjects, 2);
            stitched = cell2mat(mibModel.getData3D('labels', 1, 3, NaN, ...
                struct('id', 1, 'blockModeSwitch', 0)));
            testCase.verifyClass(stitched, 'uint16');
            % both columns keep one consistent index through the whole stack
            testCase.verifyEqual(numel(unique(stitched(groundTruth.columnA))), 1);
            testCase.verifyEqual(numel(unique(stitched(groundTruth.columnB))), 1);
            testCase.verifyNotEqual(stitched(find(groundTruth.columnA, 1)), ...
                                    stitched(find(groundTruth.columnB, 1)));
        end

        % -----------------------------------------------------------------
        % selection / mask survival when leaving the packed type-63 model
        % -----------------------------------------------------------------

        function stitch_from63_selectionReadableAs2D(testCase)
            % regression: getRGBimage calls getData2D('selection', ...) right
            % after stitching and used to error with "Index in position 3
            % exceeds array bounds" because obj.selection stayed empty
            [mibModel, groundTruth] = StitchModelInstancesTest.buildInstanceStack('labels63');

            mibModel.I{1}.stitchModelInstances();

            sliceNo = 3;
            selectionSlice = cell2mat(mibModel.I{1}.getData2D('selection', sliceNo, NaN, NaN, ...
                struct('blockModeSwitch', 0)));
            testCase.verifyEqual(selectionSlice, groundTruth.selection(:, :, sliceNo));
        end

        function stitch_from63_selectionPreservedAs3D(testCase)
            [mibModel, groundTruth] = StitchModelInstancesTest.buildInstanceStack('labels63');

            mibModel.I{1}.stitchModelInstances();

            selection = cell2mat(mibModel.getData3D('selection', 1, 3, NaN, ...
                struct('id', 1, 'blockModeSwitch', 0)));
            testCase.verifyEqual(selection, groundTruth.selection);
        end

        function stitch_from63_maskPreserved(testCase)
            [mibModel, groundTruth] = StitchModelInstancesTest.buildInstanceStack('labels63');

            mibModel.I{1}.stitchModelInstances();

            mask = cell2mat(mibModel.getData3D('mask', 1, 3, NaN, ...
                struct('id', 1, 'blockModeSwitch', 0)));
            testCase.verifyEqual(mask, groundTruth.mask);
        end

        function stitch_from65535_selectionPreserved(testCase)
            % already unpacked: the standalone selection layer must be left alone
            [mibModel, groundTruth] = StitchModelInstancesTest.buildInstanceStack('labels65535');

            mibModel.I{1}.stitchModelInstances();

            selection = cell2mat(mibModel.getData3D('selection', 1, 3, NaN, ...
                struct('id', 1, 'blockModeSwitch', 0)));
            testCase.verifyEqual(selection, groundTruth.selection);
        end

    end

    methods (Static, Access = private)
        function [mibModel, groundTruth] = buildInstanceStack(modelType)
            % Two square columns running through the whole stack, with the
            % per-slice instance indices deliberately swapped between slices -
            % this is what independently generated 2D instance predictions look
            % like, and stitching must resolve them into 2 objects.
            dims = [32 32 8];
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', modelType, 'dims', dims);

            columnA = false(dims);
            columnB = false(dims);
            columnA(5:12, 5:12, :)   = true;
            columnB(20:28, 20:28, :) = true;

            instanceStack = zeros(dims, 'uint8');
            for sliceNo = 1:dims(3)
                if mod(sliceNo, 2) == 1
                    indexA = 1; indexB = 2;
                else
                    indexA = 2; indexB = 1;   % indices are not consistent across slices
                end
                sliceLabels = zeros(dims(1:2), 'uint8');
                sliceLabels(columnA(:, :, sliceNo)) = indexA;
                sliceLabels(columnB(:, :, sliceNo)) = indexB;
                instanceStack(:, :, sliceNo) = sliceLabels;
            end

            instanceStack = cast(instanceStack, class(groundTruth.labels));
            mibModel.setData3D(instanceStack, 'labels', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));

            groundTruth.labels  = instanceStack;
            groundTruth.columnA = columnA;
            groundTruth.columnB = columnB;
        end
    end
end
