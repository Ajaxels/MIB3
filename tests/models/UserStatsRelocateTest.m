classdef UserStatsRelocateTest < matlab.unittest.TestCase
% USERSTATSRELOCATETEST - Unit tests for MibModel.relocateUserStats.
%
% Choosing another folder for the user statistics must never replace the file
% that this computer already has there (mib_user_<COMPUTERNAME>.mat): the two
% files are snapshots of the history of the same computer, so they are merged
% counter by counter with the larger value winning, and the points of the
% running session are added on top. A file that cannot be read is not touched
% at all, and a failed relocation leaves the model as it was.
%
% Every test works in its own temporary folders on a model built from the
% defaults, so no statistics file of the user is read or written.

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function existingShard_isMergedNotReplaced(testCase)
            [oldFolder, newFolder] = testCase.makeFolders('local', 'shared');
            ownShardName = testCase.ownShardName();
            % the shared folder keeps the full history of this computer, the
            % local one only an older part of it
            testCase.saveShard(newFolder, ownShardName, testCase.makeTiers(5000, 40, datetime(2026, 1, 1)));
            testCase.saveShard(newFolder, 'mib_user_OTHERPC.mat', testCase.makeTiers(700, 5, datetime(2026, 3, 1)));
            model = testCase.buildSessionModel(oldFolder, testCase.makeTiers(100, 2, datetime(2026, 9, 1)), 30, 1);

            model.relocateUserStats(newFolder);

            written = testCase.readShard(newFolder, ownShardName);
            testCase.verifyEqual(written.collectedPoints, 5030, ...
                'the larger history is kept and the points of the session are added');
            testCase.verifyEqual(written.numberOfLassos, 41);
            testCase.verifyEqual(written.logStartDate, datetime(2026, 1, 1), ...
                'the log starts at the earliest date of the two files');
            testCase.verifyEqual(model.preferences.Users.Tiers.collectedPoints, 5730, ...
                'the total includes the other computer');
            testCase.verifyEqual(model.preferences.System.UserStatsProfile, fullfile(newFolder, ownShardName));
            testCase.verifyEqual(model.getOwnStatsShard().collectedPoints, 5030, ...
                'the shard written on exit matches the file');
        end

        function returnToOlderFolder_keepsNewerHistory(testCase)
            [oldFolder, newFolder] = testCase.makeFolders('local', 'shared');
            ownShardName = testCase.ownShardName();
            testCase.saveShard(oldFolder, ownShardName, testCase.makeTiers(100, 2, datetime(2026, 9, 1)));
            model = testCase.buildSessionModel(newFolder, testCase.makeTiers(5000, 40, datetime(2026, 1, 1)), 20, 0);

            model.relocateUserStats(oldFolder);

            testCase.verifyEqual(testCase.readShard(oldFolder, ownShardName).collectedPoints, 5020);
            testCase.verifyEqual(model.preferences.Users.Tiers.collectedPoints, 5020);
            testCase.verifyEqual(model.getOwnStatsShard().collectedPoints, 5020);
        end

        function folderWithoutShard_receivesCarriedShard(testCase)
            [oldFolder, newFolder] = testCase.makeFolders('local', 'shared');
            testCase.saveShard(newFolder, 'mib_user_OTHERPC.mat', testCase.makeTiers(700, 5, datetime(2026, 3, 1)));
            model = testCase.buildSessionModel(oldFolder, testCase.makeTiers(100, 2, datetime(2026, 9, 1)), 30, 1);

            model.relocateUserStats(newFolder);

            written = testCase.readShard(newFolder, testCase.ownShardName());
            testCase.verifyEqual(written.collectedPoints, 130);
            testCase.verifyEqual(written.numberOfLassos, 3);
            testCase.verifyEqual(model.preferences.Users.Tiers.collectedPoints, 830);
        end

        function unreadableShard_isLeftUntouched(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.SuppressedWarningsFixture('MIB:loadUserStats'));
            [oldFolder, newFolder] = testCase.makeFolders('local', 'shared');
            shardPath = fullfile(newFolder, testCase.ownShardName());
            fileId = fopen(shardPath, 'w');
            fwrite(fileId, 'not a mat file', 'char');
            fclose(fileId);
            model = testCase.buildSessionModel(oldFolder, testCase.makeTiers(100, 2, datetime(2026, 9, 1)), 30, 1);
            preferencesBefore = model.preferences;
            sessionSettingsBefore = model.sessionSettings;

            testCase.verifyError(@() model.relocateUserStats(newFolder), ...
                'MIB:relocateUserStats:unreadableShard');

            testCase.verifyEqual(fileread(shardPath), 'not a mat file', 'the file must not be overwritten');
            testCase.verifyEqual(model.preferences, preferencesBefore);
            testCase.verifyEqual(model.sessionSettings, sessionSettingsBefore);
        end

        function writeFailure_leavesModelUnchanged(testCase)
            [oldFolder, blockedFolder] = testCase.makeFolders('local', 'blocked');
            % a file where the folder should be, so the shard cannot be written
            rmdir(blockedFolder);
            fileId = fopen(blockedFolder, 'w');
            fclose(fileId);
            model = testCase.buildSessionModel(oldFolder, testCase.makeTiers(100, 2, datetime(2026, 9, 1)), 30, 1);
            preferencesBefore = model.preferences;
            sessionSettingsBefore = model.sessionSettings;

            testCase.verifyError(@() model.relocateUserStats(blockedFolder), ...
                'MIB:relocateUserStats:writeFailed');

            testCase.verifyEqual(model.preferences, preferencesBefore);
            testCase.verifyEqual(model.sessionSettings, sessionSettingsBefore);
        end

    end

    methods (Access = private)

        function varargout = makeFolders(testCase, varargin)
            % one empty folder per name, inside a temporary folder removed after the test
            root = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            varargout = cell(1, numel(varargin));
            for folderId = 1:numel(varargin)
                varargout{folderId} = fullfile(root, varargin{folderId});
                mkdir(varargout{folderId});
            end
        end

        function model = buildSessionModel(~, statsFolder, ownShardAtLoad, sessionPoints, sessionLassos)
            % a session that loaded ownShardAtLoad from statsFolder as the only
            % shard there, and has earned sessionPoints and sessionLassos since
            mibFolder = fileparts(which('mib3'));
            model = models.MibModel(1, mibFolder, Verbose = false, Preferences = 'defaults');
            model.preferences.System.UserStatsProfile = fullfile(statsFolder, ...
                sprintf('mib_user_%s.mat', utils.identifyComputerName()));
            model.sessionSettings.UserStats.TotalAtLoad = ownShardAtLoad;
            model.sessionSettings.UserStats.OwnShardAtLoad = ownShardAtLoad;
            model.preferences.Users.Tiers = ownShardAtLoad;
            model.preferences.Users.Tiers.collectedPoints = ownShardAtLoad.collectedPoints + sessionPoints;
            model.preferences.Users.Tiers.numberOfLassos = ownShardAtLoad.numberOfLassos + sessionLassos;
        end

        function tiers = makeTiers(~, collectedPoints, numberOfLassos, logStartDate)
            tiers = utils.defaults.generatePreferences().Users.Tiers;
            tiers.collectedPoints = collectedPoints;
            tiers.numberOfLassos = numberOfLassos;
            tiers.logStartDate = logStartDate;
        end

        function shardName = ownShardName(~)
            shardName = sprintf('mib_user_%s.mat', utils.identifyComputerName());
        end

        function saveShard(~, folder, shardName, tiers)
            Tiers = tiers;  % saved under the variable name read by utils.loadUserStats
            save(fullfile(folder, shardName), 'Tiers');
        end

        function tiers = readShard(~, folder, shardName)
            loaded = load(fullfile(folder, shardName), 'Tiers');
            tiers = loaded.Tiers;
        end

    end
end
