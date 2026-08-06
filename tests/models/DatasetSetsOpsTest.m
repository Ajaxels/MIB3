classdef DatasetSetsOpsTest < matlab.unittest.TestCase
% Tests for MibModel.datasetsSetsOps - Add, Rename, Select, Remove sets.
%
% Call pattern (batch mode): mibModel.datasetsSetsOps(batchOpt)
%   nargin == 2 and batchOpt is a struct triggers batch dispatch.
%
% Verification strategies:
%   renameSet  - Sets.names entry is updated
%   addSet     - numel(Sets.names) increases by 1
%   selectSet  - Sets.selectedSet index changes to the named set
%   removeSet  - numel(Sets.names) decreases back to 1

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

        function sortSets_movesContainersWithTheirSet(testCase)
            % Sorting must permute obj.I together with Sets.names, otherwise the
            % sorted names point at another set's data
            mibModel = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);
            mibModel.datasetsSetsOps(struct('Mode', {{'Rename set'}}, 'SetName', 'Charlie'));
            mibModel.datasetsSetsOps(struct('Mode', {{'Add set'}}, 'SetName', 'Alpha'));
            mibModel.datasetsSetsOps(struct('Mode', {{'Add set'}}, 'SetName', 'Bravo'));

            % remember the first container of every set so it can be traced after the sort
            datasetsInSet = mibModel.Sets.datasetsInSet;
            namesBefore = mibModel.Sets.names;
            firstContainerBefore = cell(1, numel(namesBefore));
            for setId = 1:numel(namesBefore)
                firstContainerBefore{setId} = mibModel.I{(setId-1)*datasetsInSet + 1};
            end

            mibModel.datasetsSetsOps(struct('Mode', {{'Sort sets'}}));

            testCase.verifyEqual(mibModel.Sets.names(:)', {'Alpha', 'Bravo', 'Charlie'});
            for setId = 1:numel(mibModel.Sets.names)
                setName = mibModel.Sets.names{setId};
                expectedDataset = firstContainerBefore{strcmp(namesBefore, setName)};
                testCase.verifyTrue(mibModel.I{(setId-1)*datasetsInSet + 1} == expectedDataset, ...
                    sprintf('set "%s" must keep its own containers after sorting', setName));
            end
        end

        function sortSets_remapsActiveIdAndLinkedPairs(testCase)
            mibModel = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);
            mibModel.datasetsSetsOps(struct('Mode', {{'Rename set'}}, 'SetName', 'Zulu'));
            mibModel.datasetsSetsOps(struct('Mode', {{'Add set'}}, 'SetName', 'Alpha'));

            datasetsInSet = mibModel.Sets.datasetsInSet;
            % active dataset: buffer 3 of "Zulu" (set 1 before the sort)
            mibModel.id = 3;
            mibModel.Sets.selectedSet = 1;
            mibModel.Sets.selectedDataset(1) = 3;
            % link buffer 3 of "Zulu" with buffer 2 of "Alpha" (set 2 before the sort)
            mibModel.linkedPairs = [3, datasetsInSet + 2];
            activeDataset = mibModel.I{3};

            mibModel.datasetsSetsOps(struct('Mode', {{'Sort sets'}}));

            % "Zulu" is now set 2, so its buffer 3 is global datasetsInSet + 3
            testCase.verifyEqual(mibModel.Sets.selectedSet, 2);
            testCase.verifyEqual(mibModel.id, datasetsInSet + 3);
            testCase.verifyTrue(mibModel.I{mibModel.id} == activeDataset);
            testCase.verifyEqual(mibModel.linkedPairs, [2, datasetsInSet + 3]);
        end

        function sortSets_clearsUndoHistory(testCase)
            % undo items store a global container index, which the sort invalidates
            mibModel = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);
            mibModel.datasetsSetsOps(struct('Mode', {{'Rename set'}}, 'SetName', 'Zulu'));
            mibModel.datasetsSetsOps(struct('Mode', {{'Add set'}}, 'SetName', 'Alpha'));
            mibModel.Sets.selectedSet = 1;
            mibModel.id = 1;

            mibModel.backup('image', 1);
            testCase.assumeGreaterThan(mibModel.Backup.undoIndex, 1, ...
                'pre-condition: a backup step must be stored');

            mibModel.datasetsSetsOps(struct('Mode', {{'Sort sets'}}));

            testCase.verifyEqual(mibModel.Backup.undoIndex, 1, ...
                'Sort sets must drop undo steps that point at the old container indices');
        end

    end
end
