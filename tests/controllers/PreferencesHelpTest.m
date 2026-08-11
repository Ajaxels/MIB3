classdef PreferencesHelpTest < matlab.unittest.TestCase
% PREFERENCESHELPTEST - Tests the Preferences help-button section anchors.
%
% The Help button jumps to the section of ``home-preferences.html`` matching the
% selected category. Those anchors are **generated** by Zensical from the
% headings of ``docs/docs/user-interface/ribbon/home/home-preferences.md``, by
% lowercasing and replacing spaces with hyphens. Nothing else in the repo
% connects the two, so renaming a heading in the docs would silently land every
% user at the top of the page with no error anywhere - which is exactly the kind
% of breakage that needs a test.
%
% The anchors live in a ``switch`` inside ``helpBtnCallback``, which needs the
% open dialog to reach. Rather than open a window, or keep a second copy of the
% list here that could drift, these tests read the ``switch`` out of the source
% file and check what it actually contains against the built page.

    properties (Access = private)
        SourceText      % text of Preferences.m
        HelpPagePath    % built help page
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (TestMethodSetup)
        function readSources(testCase)
            mibFolder = fileparts(which('mib3'));
            testCase.SourceText = fileread(fullfile(mibFolder, '+controllers', ...
                '@Preferences', 'Preferences.m'));
            testCase.HelpPagePath = fullfile(fileparts(mibFolder), 'docs', 'html', ...
                'user-interface', 'ribbon', 'home', 'home-preferences.html');
        end
    end

    methods (Test, TestTags = {'Unit'})

        function everyCategoryHasAnAnchor(testCase)
            % One case per panel, so no category silently lands on the top of
            % the page. The panel list matches updateWidgets/panelsList.
            expectedPanels = {'UserInterfacePanel', 'ColorsPanel', 'BackupAndUndoPanel', ...
                'ExternalDirectoriesPanel', 'KeyboardShortcutsPanel', ...
                'SegmentationToolsPanel', 'InputOutputPanel'};

            [panels, anchors] = testCase.parseHelpSwitch();
            testCase.verifyEmpty(setdiff(expectedPanels, panels), ...
                'a preferences category has no help anchor');
            testCase.verifyNumElements(unique(anchors), numel(anchors), ...
                'two categories share an anchor, so one of them jumps to the wrong section');
        end

        function everyAnchorExistsInTheBuiltHelpPage(testCase)
            % The load-bearing test: pins the switch to the real generated file.
            testCase.assumeTrue(isfile(testCase.HelpPagePath), ...
                'skipped: docs/html is not built in this checkout');
            htmlText = fileread(testCase.HelpPagePath);

            [panels, anchors] = testCase.parseHelpSwitch();
            for anchorIdx = 1:numel(anchors)
                testCase.verifySubstring(htmlText, sprintf('id="%s"', anchors{anchorIdx}), ...
                    sprintf(['%s points at #%s, which no longer exists in the built docs - ' ...
                    'a heading in home-preferences.md was probably renamed'], ...
                    panels{anchorIdx}, anchors{anchorIdx}));
            end
        end

        function theLocalUrlKeepsThreeSlashesAndTheFragment(testCase)
            % A file URL needs THREE slashes. web() rewrote the path to a
            % single-slash "file:/C:/...", which the browser read as a host name
            % and turned into "http://home-preferences.html/", so the callback
            % builds the URL itself and hands it to the OS.
            testCase.verifySubstring(testCase.SourceText, ...
                'target = [''file:///'' strrep(helpFilePath, ''\'', ''/'') anchor];', ...
                'the local help URL must be a three-slash file:// URL with the anchor appended');
        end
    end

    methods (Access = private)
        function [panels, anchors] = parseHelpSwitch(testCase)
            % PARSEHELPSWITCH - Panel/anchor pairs as written in helpBtnCallback.
            tokens = regexp(testCase.SourceText, ...
                'case\s+''(\w*Panel)'';\s*anchor\s*=\s*''#([\w-]+)''', 'tokens');
            testCase.assertNotEmpty(tokens, ...
                'no help anchors found - helpBtnCallback was restructured, update this test');
            panels  = cellfun(@(t) t{1}, tokens, 'UniformOutput', false);
            anchors = cellfun(@(t) t{2}, tokens, 'UniformOutput', false);
        end
    end
end
