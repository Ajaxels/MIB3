classdef DatasetSetsOpsTest < matlab.unittest.TestCase
% Tests for MibModel.datasetsSetsOps — Add, Rename, Select, Remove sets.
%
% Call pattern (batch mode): mibModel.datasetsSetsOps(batchOpt)
%   nargin == 2 and batchOpt is a struct triggers batch dispatch.
%
% Verification strategies:
%   renameSet  — Sets.names entry is updated
%   addSet     — numel(Sets.names) increases by 1
%   selectSet  — Sets.selectedSet index changes to the named set
%   removeSet  — numel(Sets.names) decreases back to 1

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function renameSet_updatesName(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);

            batchOpt.Mode    = {'Rename set'};
            batchOpt.SetName = 'Experiment A';

            mibModel.datasetsSetsOps(batchOpt);

            currentName = mibModel.Sets.names{mibModel.Sets.selectedSet};
            testCase.verifyEqual(currentName, 'Experiment A', ...
                'Rename set must update the name of the currently selected set');
        end

        function addSet_increasesSetCount(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);
            countBefore = numel(mibModel.Sets.names);

            batchOpt.Mode    = {'Add set'};
            batchOpt.SetName = 'Set 2';

            mibModel.datasetsSetsOps(batchOpt);

            testCase.verifyEqual(numel(mibModel.Sets.names), countBefore + 1, ...
                'Add set must append one entry to Sets.names');
        end

        function selectSet_changesSelectedSet(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);

            % Add a second set; Add set also moves selectedSet to the new set
            addOpt.Mode    = {'Add set'};
            addOpt.SetName = 'Set B';
            mibModel.datasetsSetsOps(addOpt);
            % selectedSet should now be 2
            testCase.assumeEqual(mibModel.Sets.selectedSet, 2, ...
                'pre-condition: Add set must leave selectedSet pointing at the new set');

            selOpt.Mode    = {'Select set'};
            selOpt.SetName = mibModel.Sets.names{1};  % select the first set
            mibModel.datasetsSetsOps(selOpt);

            testCase.verifyEqual(mibModel.Sets.selectedSet, 1, ...
                'Select set must move selectedSet to the index of the named set');
        end

        function removeSet_decreasesCount(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);

            addOpt.Mode    = {'Add set'};
            addOpt.SetName = 'Temp';
            mibModel.datasetsSetsOps(addOpt);
            testCase.assumeEqual(numel(mibModel.Sets.names), 2, ...
                'pre-condition: two sets must exist before removal');

            remOpt.Mode    = {'Remove set'};
            remOpt.SetName = '';  % removes the currently selected set
            mibModel.datasetsSetsOps(remOpt);

            testCase.verifyEqual(numel(mibModel.Sets.names), 1, ...
                'Remove set must reduce Sets.names back to 1 entry');
        end

    end
end
