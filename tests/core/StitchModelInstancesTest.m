classdef StitchModelInstancesTest < matlab.unittest.TestCase
% STITCHMODELINSTANCESTEST - Unit tests for 2D-to-3D instance stitching.
%
% Covers (MibDataset level, no GUI):
%   layer replacement       - labels become an indexed uint16 instance model
%   type-63 unpacking       - selection and mask survive the switch away from
%                             the bit-packed model, so getData2D('selection')
%                             keeps working after stitching (the packed layers
%                             live in bits 7-8 of obj.labels and are lost
%                             unless stitchModelInstances unpacks them first)
%
% and (MibModel level, batch mode so no dialog opens):
%   session settings        - the last-used dialog values live under the single
%                             key sessionSettings.stitchInstances2Dto3D, shared
%                             with controllers.MibDeep.mergeInstancesTo3D so a
%                             threshold trialled at one entry point is offered
%                             at the other. Kept here rather than in a file of
%                             its own so the feature's tests stay together.
%                             MibDeep's half of the round trip needs a live
%                             controller and a modal dialog, so what is asserted
%                             here is the contract it depends on: the key is
%                             read and written, and the other entry point's
%                             anisotropy field is not clobbered.

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

        % -----------------------------------------------------------------
        % model filename propagation
        % -----------------------------------------------------------------

        function filename_carriesOverWithTheSuffix(testCase)
            % regression: replacing obj.labels resets filename to the MibLabels
            % placeholder, so the name of the stitched 2D model used to be lost
            mibModel = StitchModelInstancesTest.buildInstanceStack('labels65535');
            mibModel.I{1}.labels.filename = fullfile('C:', 'data', 'Labels_stack.model');

            mibModel.I{1}.stitchModelInstances();

            testCase.verifyEqual(mibModel.I{1}.labels.filename, ...
                fullfile('C:', 'data', 'Labels_stack_3d.model'), ...
                'the 2D model name must be propagated with _3d inserted before the extension');
        end

        function filename_labelsVariableIsPreserved(testCase)
            mibModel = StitchModelInstancesTest.buildInstanceStack('labels65535');
            mibModel.I{1}.labels.filename = 'Labels_stack.model';
            mibModel.I{1}.labels.labelsVariable = 'myLabels';

            mibModel.I{1}.stitchModelInstances();

            testCase.verifyEqual(mibModel.I{1}.labels.labelsVariable, 'myLabels');
        end

        function filename_suffixIsNotAppendedTwice(testCase)
            % stitching an already-stitched model must not build up _3d_3d
            mibModel = StitchModelInstancesTest.buildInstanceStack('labels65535');
            mibModel.I{1}.labels.filename = 'Labels_stack_3d.model';

            mibModel.I{1}.stitchModelInstances();

            testCase.verifyEqual(mibModel.I{1}.labels.filename, 'Labels_stack_3d.model');
        end

        function filename_unsetNameIsLeftAlone(testCase)
            % '' is a model created in MIB and never saved, 'Labels_none.model'
            % the MibLabels default - neither has a name worth propagating, and
            % inventing one would stop Save As suggesting a name from the image
            for unsetName = {'', 'Labels_none.model'}
                mibModel = StitchModelInstancesTest.buildInstanceStack('labels65535');
                mibModel.I{1}.labels.filename = unsetName{1};

                mibModel.I{1}.stitchModelInstances();

                testCase.verifyEqual(mibModel.I{1}.labels.filename, unsetName{1}, ...
                    sprintf('"%s" must be left as it is', unsetName{1}));
            end
        end

        function filename_emptySuffixKeepsTheNameUnchanged(testCase)
            mibModel = StitchModelInstancesTest.buildInstanceStack('labels65535');
            mibModel.I{1}.labels.filename = 'Labels_stack.model';

            mibModel.I{1}.stitchModelInstances(struct('filenameSuffix', ''));

            testCase.verifyEqual(mibModel.I{1}.labels.filename, 'Labels_stack.model');
        end

        function filename_survivesUndo(testCase)
            % the 'modelLayers' backup deep-copies the layer object, so Ctrl+Z
            % must bring back the 2D model's name along with its pixels
            mibModel = StitchModelInstancesTest.buildInstanceStack('labels65535');
            mibModel.I{1}.labels.filename = 'Labels_stack.model';

            mibModel.backup('modelLayers', 1, struct('id', 1));
            mibModel.I{1}.stitchModelInstances();
            testCase.assertEqual(mibModel.I{1}.labels.filename, 'Labels_stack_3d.model');

            mibModel.undo();

            testCase.verifyEqual(mibModel.I{1}.labels.filename, 'Labels_stack.model');
        end

        % -----------------------------------------------------------------
        % session settings: one key, shared with MibDeep.mergeInstancesTo3D
        % -----------------------------------------------------------------

        function sessionSettings_writtenUnderTheSharedKey(testCase)
            mibModel = StitchModelInstancesTest.buildInstanceStack('labels65535');
            testCase.assertFalse(isfield(mibModel.sessionSettings, 'stitchInstances2Dto3D'), ...
                'the key must not be seeded by generateSessionSettings');

            StitchModelInstancesTest.runBatch(mibModel, ...
                'IoUThreshold', {0.42, [0 1], 'off'}, 'MinObjectVoxels', {123, [0 1e9], 'on'});

            testCase.assertTrue(isfield(mibModel.sessionSettings, 'stitchInstances2Dto3D'));
            stored = mibModel.sessionSettings.stitchInstances2Dto3D;
            testCase.verifyEqual(stored.IoUThreshold, 0.42);
            testCase.verifyEqual(stored.MinObjectVoxels, 123);
        end

        function sessionSettings_areReadBackOnTheNextRun(testCase)
            % A value stored by a previous run - or by MibDeep - must reappear
            % as the default, which is what the reported bug was about.
            mibModel = StitchModelInstancesTest.buildInstanceStack('labels65535');
            mibModel.sessionSettings.stitchInstances2Dto3D = struct( ...
                'IoUThreshold', 0.11, 'ZLookback', 3, 'MinObjectVoxels', 77);

            % no IoUThreshold / ZLookback / MinObjectVoxels in this call, so the
            % stored values are the only place they can come from
            StitchModelInstancesTest.runBatch(mibModel);

            stored = mibModel.sessionSettings.stitchInstances2Dto3D;
            testCase.verifyEqual(stored.IoUThreshold, 0.11);
            testCase.verifyEqual(stored.ZLookback, 3);
            testCase.verifyEqual(stored.MinObjectVoxels, 77);
        end

        function sessionSettings_explicitArgumentWinsOverTheStoredValue(testCase)
            mibModel = StitchModelInstancesTest.buildInstanceStack('labels65535');
            mibModel.sessionSettings.stitchInstances2Dto3D = struct('IoUThreshold', 0.11);

            StitchModelInstancesTest.runBatch(mibModel, 'IoUThreshold', {0.9, [0 1], 'off'});

            testCase.verifyEqual(mibModel.sessionSettings.stitchInstances2Dto3D.IoUThreshold, 0.9);
        end

        function sessionSettings_mibDeepAnisotropyRatioSurvivesARibbonRun(testCase)
            % The one value the two entry points cannot share: here it is a
            % yes/no (the ratio comes from the dataset pixel size), in MibDeep a
            % raw ratio. They are stored under separate names and each side must
            % write only its own, or one dialog silently resets the other.
            mibModel = StitchModelInstancesTest.buildInstanceStack('labels65535');
            mibModel.sessionSettings.stitchInstances2Dto3D = struct( ...
                'Anisotropy', 4, 'IoUThreshold', 0.3);

            StitchModelInstancesTest.runBatch(mibModel, 'UseAnisotropy', true);

            stored = mibModel.sessionSettings.stitchInstances2Dto3D;
            testCase.verifyEqual(stored.Anisotropy, 4, ...
                'MibDeep''s ratio must survive a run from the ribbon');
            testCase.verifyTrue(stored.UseAnisotropy, ...
                'the ribbon stores its own answer under its own name');
        end

        function sessionSettings_outOfRangeStoredValueIsIgnored(testCase)
            % A stale or hand-edited entry must not widen a spinner's range.
            mibModel = StitchModelInstancesTest.buildInstanceStack('labels65535');
            mibModel.sessionSettings.stitchInstances2Dto3D = struct( ...
                'IoUThreshold', 42, 'ZLookback', -5);

            StitchModelInstancesTest.runBatch(mibModel);

            stored = mibModel.sessionSettings.stitchInstances2Dto3D;
            testCase.verifyEqual(stored.IoUThreshold, 0.25, 'must fall back to the default');
            testCase.verifyEqual(stored.ZLookback, 1, 'must fall back to the default');
        end

    end

    methods (Static, Access = private)

        function runBatch(mibModel, varargin)
            % Drive MibModel.stitchModelInstances non-interactively. Passing
            % .Method is what switches the dialog off, so every case here goes
            % through the real session-settings read and write.
            BatchOptIn = struct('Method', {{'graph'}}, 'showWaitbar', false);
            for k = 1:2:numel(varargin)
                BatchOptIn.(varargin{k}) = varargin{k+1};
            end
            mibModel.stitchModelInstances(BatchOptIn);
        end

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
