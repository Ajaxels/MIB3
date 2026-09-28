classdef PreferencesOverrideTest < matlab.unittest.TestCase
% PREFERENCESOVERRIDETEST - Unit tests for the JSON preferences override file.
%
% MibModel.saveOverridePreferences writes the settings that differ from the
% defaults to mib3_prefs_override[_COMPUTERNAME].json; MibModel.initializePreferences
% reads it on the first start of a user without mib3.mat. jsondecode loses the
% orientation of vectors, turns {} into [] and cannot hold Inf/NaN, so the reader
% coerces every value back to the class and shape of its default - these tests
% check that a round trip returns exactly the values that were saved.
%
% USERPROFILE and APPDATA are redirected to a temp folder, so no mib3.mat exists and
% the override branch runs; the model is given a sandbox folder as mibPath, so the
% override files are written there rather than next to the real mib3.m.

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function roundTrip_restoresValuesClassesAndShapes(testCase)
            mibPath = testCase.useSandbox();
            source = testCase.buildModel(mibPath, 'defaults');
            source.preferences.System.MouseWheel = 'zoom';
            source.preferences.System.Dirs.RecentDirsNumber = 5;
            source.preferences.Colors.SelectionColor = [1 0 0];
            source.preferences.Colors.ModelMaterialColors = [1 0 0; 0 1 0];
            source.preferences.Colors.MaskColor = [0.12345 0.5 1];         % rounded to 3 decimals
            source.preferences.KeyShortcuts.shift(3) = ~source.preferences.KeyShortcuts.shift(3);
            source.preferences.Deep.TrainingOpt.GradientThreshold = 5;      % default Inf
            source.preferences.Deep.TrainingOpt.MaxEpochs = Inf;            % default finite
            source.preferences.Deep.ImageFilenameExtension = {{'AM', 'TIF'}, 'PNG'};   % nested cell
            source.preferences.DoNotShowDialogs.SomeDialog = true;
            expected = source.preferences;

            numberOfSettings = source.saveOverridePreferences(fullfile(mibPath, 'mib3_prefs_override.json'));
            testCase.verifyEqual(numberOfSettings, 10);

            restored = testCase.buildModel(mibPath, 'saved').preferences;
            testCase.verifyEqual(restored.System.MouseWheel, expected.System.MouseWheel);
            testCase.verifyEqual(restored.System.Dirs.RecentDirsNumber, expected.System.Dirs.RecentDirsNumber);
            testCase.verifyEqual(restored.Colors.SelectionColor, expected.Colors.SelectionColor, ...
                'a row vector must come back as a row');
            testCase.verifyEqual(restored.Colors.ModelMaterialColors, expected.Colors.ModelMaterialColors);
            testCase.verifyEqual(restored.Colors.MaskColor, [0.123 0.5 1], ...
                'colors are written with 3 decimals');
            testCase.verifyEqual(restored.KeyShortcuts, expected.KeyShortcuts, ...
                'key shortcut arrays must keep their orientation and class');
            testCase.verifyEqual(restored.Deep.TrainingOpt.GradientThreshold, 5);
            testCase.verifyEqual(restored.Deep.TrainingOpt.MaxEpochs, Inf, ...
                'Inf must survive the round trip');
            testCase.verifyEqual(restored.Deep.TrainingOpt.ValidationPatience, Inf, ...
                'a setting that was not written keeps its default');
            testCase.verifyEqual(restored.Deep.ImageFilenameExtension, expected.Deep.ImageFilenameExtension);
            testCase.verifyEqual(restored.DoNotShowDialogs, expected.DoNotShowDialogs);
            testCase.verifyEqual(restored.System.Dirs.RecentDirs, {}, ...
                'the empty cell default must stay a cell');
        end

        function materialColors_areCappedAt255(testCase)
            mibPath = testCase.useSandbox();
            source = testCase.buildModel(mibPath, 'defaults');
            % the palette of a 63-bit model, as copied in by the Preferences callback
            source.preferences.Colors.ModelMaterialColors = round(rand(65535, 3), 3);
            expected = source.preferences.Colors.ModelMaterialColors(1:255, :);

            source.saveOverridePreferences(fullfile(mibPath, 'mib3_prefs_override.json'));

            restored = testCase.buildModel(mibPath, 'saved').preferences;
            testCase.verifyEqual(restored.Colors.ModelMaterialColors, expected);
        end

        function personalState_isNotWritten(testCase)
            mibPath = testCase.useSandbox();
            source = testCase.buildModel(mibPath, 'defaults');
            source.preferences.System.Dirs.RecentDirs = {'c:\private'};
            source.preferences.Deep.SendReports.SMTP_password = 'secret';
            source.preferences.System.UserStatsProfile = 'c:\private\mib_user_PC.mat';
            source.preferences.Tips.CurrentTipIndex = 7;
            overrideFile = fullfile(mibPath, 'mib3_prefs_override.json');

            numberOfSettings = source.saveOverridePreferences(overrideFile);

            testCase.verifyEqual(numberOfSettings, 0);
            jsonText = fileread(overrideFile);
            testCase.verifySubstring(jsonText, '"_comment"');
            testCase.verifyEmpty(strfind(jsonText, 'secret'), 'the SMTP password must never be written');
            testCase.verifyEmpty(strfind(jsonText, 'private'), 'the recent directories and the statistics file are personal');
        end

        function computerSpecificFile_winsOverGeneric(testCase)
            mibPath = testCase.useSandbox();
            source = testCase.buildModel(mibPath, 'defaults');
            source.preferences.System.MouseWheel = 'zoom';
            source.saveOverridePreferences(fullfile(mibPath, 'mib3_prefs_override.json'));
            source.preferences.System.MouseWheel = 'scroll';
            source.preferences.System.LeftMouseButton = 'pan';
            source.saveOverridePreferences(fullfile(mibPath, ...
                sprintf('mib3_prefs_override_%s.json', utils.identifyComputerName())));

            restored = testCase.buildModel(mibPath, 'saved').preferences;

            testCase.verifyEqual(restored.System.LeftMouseButton, 'pan');
            testCase.verifyEqual(restored.System.MouseWheel, 'scroll', ...
                'only the file of this computer is read');
        end

        function handEditedFile_unknownSettingIsDropped(testCase)
            mibPath = testCase.useSandbox();
            testCase.writeText(fullfile(mibPath, 'mib3_prefs_override.json'), ...
                '{"preferences": {"System": {"_comment": {"MouseWheel": "x"}, "MouseWheel": "zoom", "MouseWhel": "typo"}}}');

            model = testCase.verifyWarning(@() testCase.buildModel(mibPath, 'saved'), ...
                'MIB:preferencesOverride');
            restored = model.preferences;

            testCase.verifyEqual(restored.System.MouseWheel, 'zoom');
            testCase.verifyFalse(isfield(restored.System, 'MouseWhel'));
            testCase.verifyFalse(isfield(restored.System, 'x_comment'));
        end

        function malformedFile_isIgnored(testCase)
            mibPath = testCase.useSandbox();
            testCase.writeText(fullfile(mibPath, 'mib3_prefs_override.json'), ...
                '{"preferences": {"System": {"MouseWheel": "zoom",}}}');

            model = testCase.verifyWarning(@() testCase.buildModel(mibPath, 'saved'), ...
                'MIB:preferencesOverride');
            restored = model.preferences;

            testCase.verifyEqual(restored.System.MouseWheel, 'scroll', ...
                'a file that cannot be read leaves the defaults in place');
        end

    end

    methods (Access = private)

        function mibPath = useSandbox(testCase)
            % redirect the preferences and statistics folders into a temp tree,
            % and return a folder that stands in for the MIB program folder
            originalUserProfile = getenv('USERPROFILE');
            originalAppData     = getenv('APPDATA');
            testCase.addTeardown(@() setenv('USERPROFILE', originalUserProfile));
            testCase.addTeardown(@() setenv('APPDATA', originalAppData));

            sandbox = fullfile(tempname, 'mibPrefs');
            mkdir(fullfile(sandbox, 'Matlab'));
            mkdir(fullfile(sandbox, 'AppData'));
            % the model loads its placeholder image from the program folder
            mibPath = fullfile(fileparts(sandbox), 'mib');
            mkdir(fullfile(mibPath, 'assets', 'images'));
            copyfile(fullfile(fileparts(which('mib3')), 'assets', 'images', 'default.png'), ...
                fullfile(mibPath, 'assets', 'images'));
            testCase.addTeardown(@() rmdir(fileparts(sandbox), 's'));

            setenv('USERPROFILE', sandbox);
            setenv('APPDATA', fullfile(sandbox, 'AppData'));
        end

        function model = buildModel(~, mibPath, preferencesMode)
            % a CPU limit above the default of 2, so the clamp leaves the setting unchanged
            model = models.MibModel(64, mibPath, 'ver. 2026.09 / 20.08.2026', ...
                Verbose = false, Preferences = preferencesMode);
        end

        function writeText(~, filename, text)
            fileId = fopen(filename, 'w');
            fwrite(fileId, text, 'char');
            fclose(fileId);
        end

    end
end
