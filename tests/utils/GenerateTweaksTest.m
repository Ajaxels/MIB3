classdef GenerateTweaksTest < matlab.unittest.TestCase
% GENERATETWEAKSTEST - Consistency of the Fine-tuning registry with the preferences.
%
% utils.defaults.generateTweaks describes the settings of Preferences -> Fine-tuning,
% while their defaults live in utils.defaults.generatePreferences. The two lists are
% kept by hand, and the Preferences dialog trusts the registry blindly: a path that
% does not exist errors when the panel is opened, a default outside its Limits errors
% in the numeric field, and a Prefs.Tweaks setting nobody described is never shown.

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function everyDescribedSettingExistsAndFitsItsType(testCase)
            tweaks = utils.defaults.generateTweaks();
            defaults = utils.defaults.generatePreferences();
            testCase.assertNotEmpty(tweaks);
            testCase.verifyNumElements(unique({tweaks.Path}), numel(tweaks), 'a setting is described twice');

            for tweakId = 1:numel(tweaks)
                tweak = tweaks(tweakId);
                pathParts = strsplit(tweak.Path, '.');
                testCase.assertTrue(isfield(getParent(defaults, pathParts), pathParts{end}), ...
                    sprintf('%s has no default in generatePreferences', tweak.Path));
                value = getfield(defaults, pathParts{:});

                switch tweak.Type
                    case {'numeric', 'integer'}
                        testCase.verifyTrue(isnumeric(value) && isscalar(value), tweak.Path);
                        testCase.verifySize(tweak.Limits, [1 2], tweak.Path);
                        testCase.verifyTrue(value >= tweak.Limits(1) && value <= tweak.Limits(2), ...
                            sprintf('the default of %s is outside its Limits', tweak.Path));
                        if strcmp(tweak.Type, 'integer')
                            testCase.verifyEqual(value, round(value), tweak.Path);
                        end
                    case 'logical'
                        testCase.verifyTrue(islogical(value) && isscalar(value), tweak.Path);
                    case 'dropdown'
                        testCase.verifyTrue(ischar(value), tweak.Path);
                        testCase.verifyTrue(any(strcmp(value, tweak.Items)), ...
                            sprintf('the default of %s is not one of its Items', tweak.Path));
                    otherwise
                        testCase.verifyFail(sprintf('%s has an unknown Type ''%s''', tweak.Path, tweak.Type));
                end
                testCase.verifyNotEmpty(tweak.Description, tweak.Path);
                testCase.verifyEmpty(regexp(tweak.Description, '[\x{2013}\x{2014}]', 'once'), ...
                    sprintf('%s: plain hyphen only in descriptions', tweak.Path));
            end
        end

        function everyTweaksPreferenceIsDescribed(testCase)
            % a setting under Prefs.Tweaks without a description would be
            % invisible in the dialog
            defaults = utils.defaults.generatePreferences();
            tweaks = utils.defaults.generateTweaks();
            describedPaths = {tweaks.Path};
            tweaksPaths = collectLeafPaths(defaults.Tweaks, 'Tweaks');
            testCase.verifyEmpty(setdiff(tweaksPaths, describedPaths), ...
                'these Prefs.Tweaks settings are missing from utils.defaults.generateTweaks');
        end

    end
end

function parent = getParent(structure, pathParts)
% the structure holding the last element of pathParts
parent = structure;
for partId = 1:numel(pathParts) - 1
    parent = parent.(pathParts{partId});
end
end

function paths = collectLeafPaths(structure, parentPath)
% dotted paths of all non-struct fields of a nested structure
paths = {};
fieldNames = fieldnames(structure);
for fieldId = 1:numel(fieldNames)
    fieldPath = [parentPath '.' fieldNames{fieldId}];
    if isstruct(structure.(fieldNames{fieldId}))
        paths = [paths, collectLeafPaths(structure.(fieldNames{fieldId}), fieldPath)]; %#ok<AGROW>
    else
        paths{end+1} = fieldPath; %#ok<AGROW>
    end
end
end
