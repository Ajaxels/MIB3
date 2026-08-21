classdef Mib3DeploymentReferencesTest < matlab.unittest.TestCase
    % Guards the "if false" block in mib/mib3.m against drift.
    %
    % Child dialogs are constructed by name through core.ChildView, e.g.
    % core.ChildView(obj, 'views.StitchingGUI'), so MATLAB Compiler cannot see the
    % reference and drops the .mlapp from the standalone build. The "if false" block
    % names each one so the dependency analyser keeps it. A view added to
    % mib/+views/ but not to that block therefore works perfectly when MIB runs from
    % MATLAB and fails only when a user opens that dialog in the compiled app - a
    % failure this test moves forward to build time.
    %
    % Scope is the .mlapp files directly in mib/+views/. Deliberately excluded:
    %   - +views/+components/  - referenced statically as views.components.Xxx
    %   - @MibView             - constructed directly by controllers.MibController
    % Both are visible to the compiler already, so listing them would be noise.

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function ifFalseBlockListsEveryView(testCase)
            mibFolder   = Mib3DeploymentReferencesTest.mibFolderPath();
            viewsFolder = fullfile(mibFolder, '+views');

            viewFiles     = dir(fullfile(viewsFolder, '*.mlapp'));
            expectedViews = sort(string(erase({viewFiles.name}, '.mlapp')));
            testCase.assertNotEmpty(expectedViews, ...
                sprintf('No .mlapp files found in %s - the test is looking in the wrong place.', ...
                viewsFolder));

            listedViews = Mib3DeploymentReferencesTest.viewsNamedInIfFalseBlock( ...
                fullfile(mibFolder, 'mib3.m'));

            missingFromBlock = setdiff(expectedViews, listedViews);
            testCase.verifyEmpty(missingFromBlock, sprintf( ...
                ['These views exist in mib/+views/ but are not named in the "if false" block ' ...
                 'of mib3.m, so MATLAB Compiler will drop them from the standalone build:\n  %s\n' ...
                 'Add a "views.<Name>;" line for each.'], strjoin(missingFromBlock, '\n  ')));

            staleInBlock = setdiff(listedViews, expectedViews);
            testCase.verifyEmpty(staleInBlock, sprintf( ...
                ['These views are named in the "if false" block of mib3.m but have no .mlapp ' ...
                 'in mib/+views/ - renamed or deleted, and the block was not updated:\n  %s'], ...
                strjoin(staleInBlock, '\n  ')));
        end

    end

    methods (Static, Access = private)

        function mibFolder = mibFolderPath()
            % tests/ -> repo root -> mib/
            testsFolder = fileparts(mfilename('fullpath'));
            mibFolder   = fullfile(fileparts(testsFolder), 'mib');
        end

        function viewNames = viewsNamedInIfFalseBlock(mib3File)
            % Collect the views.<Name> identifiers inside the "if false" ... "end" block.
            % Comments are stripped first: the block's own header comment contains the
            % word "views." and would otherwise be picked up as an empty view name.
            lines = splitlines(string(fileread(mib3File)));

            blockStart = find(~cellfun(@isempty, ...
                regexp(lines, '^\s*if\s+false\s*$', 'once')), 1);
            assert(~isempty(blockStart), ...
                'No "if false" block found in %s - it was renamed or removed.', mib3File);

            blockEnd = blockStart + find(~cellfun(@isempty, ...
                regexp(lines(blockStart+1:end), '^\s*end\s*$', 'once')), 1);
            assert(~isempty(blockEnd), ...
                'The "if false" block in %s is not closed by a plain "end".', mib3File);

            codeOnly  = extractBefore(lines(blockStart:blockEnd) + "%", "%");
            tokens    = regexp(codeOnly, 'views\.(\w+)', 'tokens');
            viewNames = sort(unique(string([tokens{:}])));
        end

    end
end
