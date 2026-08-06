classdef AllocateMaskTest < matlab.unittest.TestCase
% ALLOCATEMASKTEST - Unit tests for MibDataset.allocateMask.
%
% allocateMask creates a zero-filled MibLabels mask container when one does
% not yet exist.  For labels63 models the mask lives in packed bits and the
% method returns without allocating.
%
% Verification strategies:
%   labels255 - after clearLayer('mask') + allocateMask: maskExist == true;
%               mask dims match image dims; second call is a no-op
%   labels63  - allocateMask returns without allocating a separate container
%               (mask is in packed bits; maskExist remains true via labels63)
%   zeros     - freshly allocated mask must be all-zero

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function allocateMask_labels255_maskExistIsTrue(testCase)
            % Build a labels255 dataset WITHOUT setting mask data so the
            % mask container starts as an unallocated placeholder.
            mibModel = AllocateMaskTest.bareModel([16 16 4]);

            testCase.assumeFalse(mibModel.I{1}.maskExist, ...
                'precondition: bare model must start with maskExist == false');

            mibModel.I{1}.allocateMask();

            testCase.verifyTrue(mibModel.I{1}.maskExist, ...
                'maskExist must be true after allocateMask');
        end

        function allocateMask_labels255_maskDimsMatchImage(testCase)
            mibModel = AllocateMaskTest.bareModel([12 20 6]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.I{1}.allocateMask();

            maskData = cell2mat(mibModel.getData3D('mask', 1, 3, [], opt));
            testCase.verifyEqual(size(maskData, 1), 12, 'mask height must match image');
            testCase.verifyEqual(size(maskData, 2), 20, 'mask width must match image');
            testCase.verifyEqual(size(maskData, 3),  6, 'mask depth must match image');
        end

        function allocateMask_labels255_freshMaskIsAllZero(testCase)
            mibModel = AllocateMaskTest.bareModel([16 16 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.I{1}.allocateMask();

            maskData = cell2mat(mibModel.getData3D('mask', 1, 3, [], opt));
            testCase.verifyEqual(sum(double(maskData(:))), 0, ...
                'freshly allocated mask must be all-zero');
        end

        function allocateMask_labels255_secondCallIsNoop(testCase)
            mibModel = AllocateMaskTest.bareModel([16 16 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.I{1}.allocateMask();

            % Write a sentinel value to the mask
            sentinel = zeros(16, 16, 4, 'uint8');
            sentinel(8, 8, 2) = 1;
            mibModel.setData3D(sentinel, 'mask', 1, 3, [], opt);

            % Second call must not overwrite the existing mask
            mibModel.I{1}.allocateMask();

            maskData = cell2mat(mibModel.getData3D('mask', 1, 3, [], opt));
            testCase.verifyEqual(maskData(8, 8, 2), uint8(1), ...
                'second allocateMask call must not overwrite an existing mask');
        end

        function allocateMask_labels63_maskAccessible(testCase)
            % For labels63 the mask is stored in packed bits - allocateMask
            % is a no-op, but the mask must still be readable (it exists).
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels63', 'dims', [16 16 4]);

            mibModel.I{1}.allocateMask();

            testCase.verifyTrue(mibModel.I{1}.maskExist, ...
                'labels63 mask is always accessible via packed bits');
        end

    end

    % =====================================================================
    % Private helpers
    % =====================================================================
    methods (Static, Access = private)

        function mibModel = bareModel(dims)
            % Construct a labels255 MibDataset without setting mask data so
            % the mask container remains an unallocated placeholder.
            testsFolder = fileparts(fileparts(mfilename('fullpath')));
            mibFolder   = fullfile(fileparts(testsFolder), 'mib');
            rng(0, 'twister');
            imgData = uint8(randi(255, [dims(1), dims(2), dims(3), 1]));
            mibModel = models.MibModel(1, mibFolder);
            mibModel.I{1} = core.MibDataset(imgData, dictionary(), 'Standard', 'labels63');
            mibModel.I{1}.updateBoundingBox([], [0 0 0]);
            mibModel.I{1}.createModel(255);
            % Intentionally no setData3D for mask - leaves mask unallocated
        end

    end
end
