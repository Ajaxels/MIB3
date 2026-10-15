classdef Zarr3SaverResumeTest < matlab.unittest.TestCase
% ZARR3SAVERRESUMETEST - Resuming an interrupted io.savers.Zarr3Saver.saveStreamResumable.
%
% The writer records every finished slab task in the store (.mib_progress.log)
% next to a description of the conversion (.mib_resume.json). With
% options.Resume it reopens the store, skips the recorded tasks and runs the
% rest; a different source or different settings refuse the resume without
% touching the store. Runs without a pool: the tasks execute on the client.

    properties (Access = private)
        OrigZarrLib
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (TestMethodSetup)
        function forceNativeBackend(testCase)
            testCase.OrigZarrLib = io.zarr.Config.library();
            io.zarr.Config.setLibrary('native');
        end
    end

    methods (TestMethodTeardown)
        function restoreBackend(testCase)
            io.zarr.Config.setLibrary(testCase.OrigZarrLib);
        end
    end

    methods (Static)
        function writeSlices(folder, volume, sliceIndices)
            for z = sliceIndices
                imwrite(volume(:, :, z), fullfile(folder, sprintf('s_%03d.tif', z)));
            end
        end

        function provider = makeProvider(folder)
            provider = io.savers.ImageDatastoreSliceProvider(imageDatastore(folder, 'FileExtensions', '.tif'));
        end

        function saverOpts = anisotropicOptions(resumeConversion)
            % chunk Z 4 -> 10 level-0 slab tasks for 40 slices; voxel z > xy makes
            % the coarser levels halve Z, so the second phase runs too
            saverOpts = struct('silent', true, 'showWaitbar', false, 'ChunkSize', [32 32 4], ...
                'MinLevelSize', 16, 'DownsampleStrategy', 'Anisotropy-preserving', ...
                'SourceFingerprint', 'test source', 'Resume', resumeConversion);
        end

        function metadata = anisotropicMetadata()
            metadata = struct('pixSize', struct('x', 0.013, 'y', 0.013, 'z', 0.03));
        end
    end

    methods (Test, TestTags = {'Unit'})

        function failedThenResumed_skipsFinishedSlabs_matchesFreshRun(testCase)
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            sourceFolder = fullfile(tmp.Folder, 'slices'); mkdir(sourceFolder);
            volume = uint8(randi(255, 128, 120, 40));
            Zarr3SaverResumeTest.writeSlices(sourceFolder, volume, 1:40);
            plan = io.savers.Zarr3Saver.computeLevelPlan(128, 120, 40, ...
                Zarr3SaverResumeTest.anisotropicMetadata().pixSize, Zarr3SaverResumeTest.anisotropicOptions(false));
            testCase.assertTrue(any([plan.cumZFactor] > 1), 'the fixture must have a Z-downsampled level');

            freshPath = io.savers.Zarr3Saver(struct()).saveStreamResumable( ...
                Zarr3SaverResumeTest.makeProvider(sourceFolder), Zarr3SaverResumeTest.anisotropicMetadata(), ...
                fullfile(tmp.Folder, 'fresh.zarr3'), Zarr3SaverResumeTest.anisotropicOptions(false));

            % interrupted run: slice 23 (slab Z 21-24) cannot be read
            storePath = fullfile(tmp.Folder, 'resumed.zarr3');
            provider = Zarr3SaverResumeTest.makeProvider(sourceFolder);
            delete(fullfile(sourceFolder, 's_023.tif'));
            testCase.verifyError(@() io.savers.Zarr3Saver(struct()).saveStreamResumable(provider, ...
                Zarr3SaverResumeTest.anisotropicMetadata(), storePath, Zarr3SaverResumeTest.anisotropicOptions(false)), ...
                'io:Zarr3Saver:taskFailed');
            testCase.verifyTrue(isfile(fullfile(storePath, '.mib_resume.json')));
            progressLines = splitlines(strtrim(fileread(fullfile(storePath, '.mib_progress.log'))));
            testCase.verifyEqual(numel(progressLines), 5, 'the 5 slabs before Z 21 must be recorded');

            % restore slice 23; change slice 1, which a resume must not read again
            Zarr3SaverResumeTest.writeSlices(sourceFolder, volume, 23);
            imwrite(uint8(255 - volume(:, :, 1)), fullfile(sourceFolder, 's_001.tif'));
            resumedPath = io.savers.Zarr3Saver(struct()).saveStreamResumable( ...
                Zarr3SaverResumeTest.makeProvider(sourceFolder), Zarr3SaverResumeTest.anisotropicMetadata(), ...
                storePath, Zarr3SaverResumeTest.anisotropicOptions(true));

            for L = 1:numel(plan)
                name = num2str(L - 1);
                testCase.verifyEqual(io.zarr.Group(resumedPath).openArray(name).read(), ...
                    io.zarr.Group(freshPath).openArray(name).read(), ...
                    sprintf('level %s of the resumed store must equal an uninterrupted conversion', name));
            end
            testCase.verifyFalse(isfile(fullfile(storePath, '.mib_resume.json')), 'resume files must be removed');
            testCase.verifyFalse(isfile(fullfile(storePath, '.mib_progress.log')));
            attrs = jsondecode(fileread(fullfile(storePath, 'zarr.json')));
            testCase.verifyFalse(isfield(attrs.attributes, 'mibIncomplete'));
        end

        function changedSettingsOrSource_refusedWithoutTouchingTheStore(testCase)
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            sourceFolder = fullfile(tmp.Folder, 'slices'); mkdir(sourceFolder);
            volume = uint8(randi(255, 64, 64, 12));
            Zarr3SaverResumeTest.writeSlices(sourceFolder, volume, 1:12);
            storePath = fullfile(tmp.Folder, 'store.zarr3');
            provider = Zarr3SaverResumeTest.makeProvider(sourceFolder);
            delete(fullfile(sourceFolder, 's_010.tif'));
            testCase.verifyError(@() io.savers.Zarr3Saver(struct()).saveStreamResumable(provider, ...
                Zarr3SaverResumeTest.anisotropicMetadata(), storePath, Zarr3SaverResumeTest.anisotropicOptions(false)), ...
                'io:Zarr3Saver:taskFailed');
            Zarr3SaverResumeTest.writeSlices(sourceFolder, volume, 10);
            progressBefore = fileread(fullfile(storePath, '.mib_progress.log'));

            changedChunk = Zarr3SaverResumeTest.anisotropicOptions(true);
            changedChunk.ChunkSize = [32 32 8];
            testCase.verifyError(@() io.savers.Zarr3Saver(struct()).saveStreamResumable( ...
                Zarr3SaverResumeTest.makeProvider(sourceFolder), Zarr3SaverResumeTest.anisotropicMetadata(), ...
                storePath, changedChunk), 'io:Zarr3Saver:cannotResume');
            changedSource = Zarr3SaverResumeTest.anisotropicOptions(true);
            changedSource.SourceFingerprint = 'another source';
            testCase.verifyError(@() io.savers.Zarr3Saver(struct()).saveStreamResumable( ...
                Zarr3SaverResumeTest.makeProvider(sourceFolder), Zarr3SaverResumeTest.anisotropicMetadata(), ...
                storePath, changedSource), 'io:Zarr3Saver:cannotResume');
            testCase.verifyEqual(fileread(fullfile(storePath, '.mib_progress.log')), progressBefore, ...
                'a refused resume must leave the record as it was');

            % a complete store holds no record to resume from
            completePath = io.savers.Zarr3Saver(struct()).saveStreamResumable( ...
                Zarr3SaverResumeTest.makeProvider(sourceFolder), Zarr3SaverResumeTest.anisotropicMetadata(), ...
                fullfile(tmp.Folder, 'complete.zarr3'), Zarr3SaverResumeTest.anisotropicOptions(false));
            testCase.verifyError(@() io.savers.Zarr3Saver(struct()).saveStreamResumable( ...
                Zarr3SaverResumeTest.makeProvider(sourceFolder), Zarr3SaverResumeTest.anisotropicMetadata(), ...
                completePath, Zarr3SaverResumeTest.anisotropicOptions(true)), 'io:Zarr3Saver:cannotResume');
        end

        function labels_materialNamesCountSkippedSlabs(testCase)
            % the largest label of a slab finished before the interruption is
            % read back from the progress record, not lost with the skip
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            sourceFolder = fullfile(tmp.Folder, 'labels'); mkdir(sourceFolder);
            labels = uint8(randi([0 3], 64, 64, 12));
            labels(10:20, 10:20, 2) = 9;   % the maximum, in the first slab
            Zarr3SaverResumeTest.writeSlices(sourceFolder, labels, 1:12);
            saverOpts = struct('silent', true, 'showWaitbar', false, 'ChunkSize', [32 32 4], 'MinLevelSize', 16, ...
                'layerType', 'labels', 'DownsampleMethod', 'nearest', 'MaterialNamesFromData', true, ...
                'SourceFingerprint', 'labels', 'Resume', false);
            metadata = struct('pixSize', struct('x', 1, 'y', 1, 'z', 1));
            storePath = fullfile(tmp.Folder, 'labels.zarr3');
            provider = Zarr3SaverResumeTest.makeProvider(sourceFolder);
            delete(fullfile(sourceFolder, 's_011.tif'));
            testCase.verifyError(@() io.savers.Zarr3Saver(struct()).saveStreamResumable( ...
                provider, metadata, storePath, saverOpts), 'io:Zarr3Saver:taskFailed');
            Zarr3SaverResumeTest.writeSlices(sourceFolder, labels, 11);

            saverOpts.Resume = true;
            io.savers.Zarr3Saver(struct()).saveStreamResumable( ...
                Zarr3SaverResumeTest.makeProvider(sourceFolder), metadata, storePath, saverOpts);
            attrs = jsondecode(fileread(fullfile(storePath, 'zarr.json')));
            testCase.verifyEqual(numel(attrs.attributes.mibMaterials.materialNames), 9);
            testCase.verifyEqual(io.zarr.Group(storePath).openArray('0').read(), labels);
        end
    end
end
