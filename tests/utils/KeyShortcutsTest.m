classdef KeyShortcutsTest < matlab.unittest.TestCase
% KEYSHORTCUTSTEST - Unit tests for the default shortcuts and utils.findKeyShortcut.
%
% utils.findKeyShortcut holds the matching rules of all key press handlers. A row
% that the rules can never reach, or two rows with one combination, would leave a
% shortcut dead without any error, so these tests check the whole default table.

    properties
        Shortcuts
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
            testCase.Shortcuts = utils.defaults.generateKeyShortcuts();
        end
    end

    methods (Test, TestTags = {'Unit'})

        function everyDefaultCombination_findsItsOwnAction(testCase)
            shortcuts = testCase.Shortcuts;
            for row = find(~cellfun(@isempty, shortcuts.Key))
                modifier = {'control', 'shift', 'alt'};
                modifier = modifier(logical([shortcuts.control(row), shortcuts.shift(row), shortcuts.alt(row)]));
                found = utils.findKeyShortcut(shortcuts, shortcuts.Key{row}, modifier);
                testCase.verifyEqual(found, row, sprintf('"%s" is not reachable', shortcuts.Action{row}));
            end
        end

        function shiftAndAlt_areIgnoredForActionsThatUseThem(testCase)
            testCase.verifyFinds('s', {'shift'}, 'Subtract from material');
            testCase.verifyFinds('s', {'alt'}, 'Subtract from material');
            testCase.verifyFinds('s', {'alt', 'shift'}, 'Subtract from material');
            testCase.verifyFinds('a', {'shift'}, 'Add to selection to material');
            testCase.verifyFinds('a', {'alt', 'shift'}, 'Add to selection to material');
        end

        function altOnKeyOfAddAction_findsItsOwnAction(testCase)
            testCase.verifyFinds('a', {'alt'}, 'Select Mask or material in all slices');
        end

        function unknownCombination_findsNothing(testCase)
            testCase.verifyEmpty(utils.findKeyShortcut(testCase.Shortcuts, 'f12', {}));
            testCase.verifyEmpty(utils.findKeyShortcut(testCase.Shortcuts, 'i', {'alt'}));
        end

        function emptyKey_doesNotFindActionsWithoutShortcut(testCase)
            testCase.verifyEmpty(utils.findKeyShortcut(testCase.Shortcuts, '', {}));
        end

        function sameCombinationTwice_findsTheFirst(testCase)
            shortcuts = testCase.Shortcuts;
            rows = find(cellfun(@isempty, shortcuts.Key), 2);
            shortcuts.Key(rows) = {'f12'};
            testCase.verifyEqual(utils.findKeyShortcut(shortcuts, 'f12', {}), rows(1));
        end

        function defaults_haveNoRepeatedCombination(testCase)
            shortcuts = testCase.Shortcuts;
            assigned = ~cellfun(@isempty, shortcuts.Key);
            combination = strcat(shortcuts.Key(assigned), compose('-%d%d%d', ...
                [shortcuts.control(assigned); shortcuts.shift(assigned); shortcuts.alt(assigned)]')');
            testCase.verifyEqual(numel(unique(combination)), nnz(assigned));
        end

        function actionNames_areUnique(testCase)
            testCase.verifyEqual(numel(unique(testCase.Shortcuts.Action)), numel(testCase.Shortcuts.Action));
        end

        function categoriesAndLabels_followTheSortedActions(testCase)
            [shortcuts, categories, labels] = utils.defaults.generateKeyShortcuts();
            testCase.verifyEqual(size(categories), size(shortcuts.Action));
            testCase.verifyEqual(size(labels), size(shortcuts.Action));

            row = strcmp(shortcuts.Action, 'Increse active material index by 1 for models with 65535 materials');
            testCase.verifyEqual(labels{row}, 'Increase active material index by 1 for models with 65535 materials');
            differs = ~strcmp(labels, shortcuts.Action);
            testCase.verifyEqual(nnz(differs & ~row), 0, 'without a label of its own an action shows its name');
            testCase.verifyEqual(categories{strcmp(shortcuts.Action, 'Select material 9')}, 'Materials');
            testCase.verifyEqual(categories{strcmp(shortcuts.Action, 'Select segmentation tool: Brush')}, 'Segmentation tools');
        end

        function selectActions_haveNoDefaultKey(testCase)
            shortcuts = testCase.Shortcuts;
            materialRows = startsWith(shortcuts.Action, 'Select material ');
            toolRows = startsWith(shortcuts.Action, 'Select segmentation tool: ');
            testCase.verifyEqual(nnz(materialRows), 9);
            testCase.verifyTrue(all(cellfun(@isempty, shortcuts.Key(materialRows | toolRows))));
        end

        function selectToolActions_matchTheToolsOfTheSegmentationPanel(testCase)
            % the handler looks the tool up by name and does nothing for an unknown one
            folder = testCase.createTemporaryFolder();
            mlappFile = fullfile(folder, 'segmentation.zip');
            copyfile(fullfile(fileparts(which('mib3')), '+views', '+components', 'Segmentation.mlapp'), mlappFile);
            unzip(mlappFile, folder);
            documentText = fileread(fullfile(folder, 'matlab', 'document.xml'));
            itemsText = extractBetween(documentText, 'segmTool.Items = {', '};');
            tools = extractBetween(itemsText{1}, '''', '''');
            tools = tools(~strcmp(strtrim(tools), ','));

            shortcuts = testCase.Shortcuts;
            toolActions = shortcuts.Action(startsWith(shortcuts.Action, 'Select segmentation tool: '));
            testCase.verifyEqual(sort(extractAfter(toolActions(:), 'Select segmentation tool: ')), ...
                sort(cellstr(tools(:))));
        end

    end

    methods (Access = private)

        function verifyFinds(testCase, key, modifier, actionName)
            row = utils.findKeyShortcut(testCase.Shortcuts, key, modifier);
            testCase.verifyEqual(testCase.Shortcuts.Action{row}, actionName);
        end

    end
end
