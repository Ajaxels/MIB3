classdef PreferencesVersionTest < matlab.unittest.TestCase
% PREFERENCESVERSIONTEST - Unit tests for the version handling in MibModel.initializePreferences.
%
% Preferences are forward-compatible but not backward-compatible: a newer MIB
% understands everything an older one wrote, an older one must not adopt
% settings it does not implement. The three cases:
%
%   saved < current   - merge the saved values onto the current defaults, and
%                       restore mib3_<version>.mat if this version was
%                       downgraded earlier
%   saved == current   - adopt the saved preferences wholesale
%   saved > current    - park a copy under the writing version, then take over
%                        only the fields the running version already has
%
% These tests deliberately use the real ``Preferences = 'saved'`` path, which
% reads mib3.mat from utils.getPrefDir(). USERPROFILE and APPDATA are redirected
% to a temp folder for the duration of each test method, so the developer's own
% preferences and statistics are never read or written. Every test restores the
% environment through addTeardown, including on failure.

    properties (Constant)
        NewVersion = 'ver. 2026.09 / 20.08.2026 (preview)'   % 2026.09
        OldVersion = 'ver. 2025.12 / 05.12.2025 (alpha)'     % 2025.12
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function savedByNewerVersion_onlyKnownFieldsAreTakenOver(testCase)
            sandbox = testCase.useSandbox();
            testCase.writePrefsFile(sandbox, 2026.09);

            model = testCase.buildQuietly(PreferencesVersionTest.OldVersion);

            testCase.verifyEqual(model.preferences.System.Font.FontSize, 42, ...
                'a field the running version knows must be restored from the newer file');
            testCase.verifyFalse(isfield(model.preferences.System, 'FutureFeature'), ...
                'a field unknown to the running version must not be carried in');
        end

        function savedByNewerVersion_isParkedAndAnnounced(testCase)
            sandbox = testCase.useSandbox();
            testCase.writePrefsFile(sandbox, 2026.09);

            model = testCase.buildQuietly(PreferencesVersionTest.OldVersion);

            testCase.verifyTrue(isfile(fullfile(sandbox, 'Matlab', 'mib3_2026.09.mat')), ...
                'the newer preferences must be parked before this session can overwrite them');
            testCase.verifyTrue(isfield(model.sessionSettings, 'PreferencesDowngradeMessage'), ...
                'MibController.initialize needs the message to show the dialog');
            testCase.verifySubstring(model.sessionSettings.PreferencesDowngradeMessage, '2026.09', ...
                'the message must name the version that wrote the file');
        end

        function downgradeRoundTrip_keepsNewerFieldsAndOlderEdits(testCase)
            sandbox = testCase.useSandbox();
            prefsFn = testCase.writePrefsFile(sandbox, 2026.09);

            % the older MIB runs, parks the newer file, and on exit rewrites
            % mib3.mat with its own (narrower) schema plus one edited value
            downgraded = testCase.buildQuietly(PreferencesVersionTest.OldVersion);
            downgraded.preferences.System.Font.FontSize = 11;
            testCase.saveAsSession(prefsFn, downgraded.preferences, 2025.12);

            % back to the newer MIB
            restored = testCase.buildQuietly(PreferencesVersionTest.NewVersion);

            testCase.verifyEqual(restored.preferences.System.FutureFeature, 'newOnly', ...
                'the parked file must bring back the settings the older version could not keep');
            testCase.verifyEqual(restored.preferences.System.Font.FontSize, 11, ...
                'a value edited while on the older version must win over the parked one');
            testCase.verifyFalse(isfield(restored.sessionSettings, 'PreferencesDowngradeMessage'), ...
                'coming back to the newer version is not a downgrade');
        end

        function savedBySameVersion_isAdoptedWholesale(testCase)
            sandbox = testCase.useSandbox();
            testCase.writePrefsFile(sandbox, 2026.09);

            model = testCase.buildQuietly(PreferencesVersionTest.NewVersion);

            testCase.verifyEqual(model.preferences.System.Font.FontSize, 42);
            testCase.verifyEqual(model.preferences.System.FutureFeature, 'newOnly', ...
                'the same version implements every field in its own file');
            testCase.verifyFalse(isfield(model.sessionSettings, 'PreferencesDowngradeMessage'));
        end

        function noPrefsFile_startsFromDefaultsWithoutParking(testCase)
            sandbox = testCase.useSandbox();

            model = testCase.buildQuietly(PreferencesVersionTest.OldVersion);

            testCase.verifyFalse(isfield(model.sessionSettings, 'PreferencesDowngradeMessage'));
            testCase.verifyEmpty(dir(fullfile(sandbox, 'Matlab', 'mib3_*.mat')), ...
                'nothing may be parked when there is no preferences file at all');
        end

    end

    methods (Access = private)

        function sandbox = useSandbox(testCase)
            % redirect the preferences and statistics folders into a temp tree
            % for this test method, and restore the environment afterwards
            originalUserProfile = getenv('USERPROFILE');
            originalAppData     = getenv('APPDATA');
            testCase.addTeardown(@() setenv('USERPROFILE', originalUserProfile));
            testCase.addTeardown(@() setenv('APPDATA', originalAppData));

            sandbox = fullfile(tempname, 'mibPrefs');
            mkdir(fullfile(sandbox, 'Matlab'));
            mkdir(fullfile(sandbox, 'AppData'));
            testCase.addTeardown(@() rmdir(fileparts(sandbox), 's'));

            setenv('USERPROFILE', sandbox);
            setenv('APPDATA', fullfile(sandbox, 'AppData'));
        end

        function model = buildQuietly(testCase, mibVersion)
            % the downgrade branch warns on purpose - keep it out of the test output
            warningState = warning('off', 'MIB:preferencesFromNewerVersion');
            testCase.addTeardown(@() warning(warningState));
            model = models.MibModel(1, fileparts(which('mib3')), mibVersion, Verbose = false);
        end

        function prefsFn = writePrefsFile(testCase, sandbox, mibVersionNumeric)
            % a mib3.mat as the given version would have written it: one field
            % both versions have (System.Font.FontSize) and one that only the
            % newer version knows (System.FutureFeature)
            template = testCase.buildQuietly(PreferencesVersionTest.NewVersion);
            preferences = template.preferences;
            preferences.System.Font.FontSize = 42;
            preferences.System.FutureFeature = 'newOnly';

            prefsFn = fullfile(sandbox, 'Matlab', 'mib3.mat');
            testCase.saveAsSession(prefsFn, preferences, mibVersionNumeric);
        end

        function saveAsSession(~, prefsFn, preferences, mibVersionNumeric)
            % mirrors what MibController.exitProgram writes: Users.Tiers is
            % stripped, the numeric version is stamped alongside
            mib_pars = struct();
            mib_pars.preferences = preferences;
            if isfield(mib_pars.preferences, 'Users') && isfield(mib_pars.preferences.Users, 'Tiers')
                mib_pars.preferences.Users = rmfield(mib_pars.preferences.Users, 'Tiers');
            end
            mib_pars.mibVersion = mibVersionNumeric; %#ok<STRNU>
            save(prefsFn, 'mib_pars');
        end

    end
end
