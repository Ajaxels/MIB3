classdef PyBackendRemoteSupportTest < matlab.unittest.TestCase
% PYBACKENDREMOTESUPPORTTEST - Remote-dependency detection in io.zarr.PyBackend.
%
% zarr-python reaches http(s) stores through fsspec's HTTPFileSystem, which
% imports "aiohttp" and "requests" lazily. Neither is a dependency of "zarr",
% so an environment that reads local v2 stores perfectly well fails on the
% first remote chunk read with:
%
%   ImportError: HTTPFileSystem requires "requests" and "aiohttp" to be installed
%
% hasRemoteSupport / ensureRemoteSupport move that discovery to open time.
%
% These tests assert the **contract** rather than one particular environment,
% so they stay green whether or not the packages are installed and whether or
% not the Python interpreter is alive. The point being guarded is that the two
% failure modes stay distinguishable: a dead interpreter and a missing package
% both make the check fail, but only one is fixed by installing something, and
% telling someone to pip install when the Python process has exited sends them
% after the wrong problem.

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function ensureRemoteSupport_isANoOpForLocalPaths(testCase)
            % Callers place this next to ensureLoaded and call it unconditionally,
            % so a local path must never throw - whatever state Python is in.
            testCase.verifyNoError(@() io.zarr.PyBackend.ensureRemoteSupport('C:\data\local.zarr'));
            testCase.verifyNoError(@() io.zarr.PyBackend.ensureRemoteSupport('/mnt/data/local.zarr'));
        end

        function ensureRemoteSupport_isANoOpForEmptyInput(testCase)
            testCase.verifyNoError(@() io.zarr.PyBackend.ensureRemoteSupport(''));
            testCase.verifyNoError(@() io.zarr.PyBackend.ensureRemoteSupport([]));
        end

        function hasRemoteSupport_answersWithoutThrowing(testCase)
            % It is used to enable or disable a control, so it must not throw
            % even when Python is missing, dead, or unusable.
            [isSupported, diagnostic] = io.zarr.PyBackend.hasRemoteSupport();

            testCase.verifyClass(isSupported, 'logical');
            testCase.verifyTrue(isscalar(isSupported));
            testCase.verifyTrue(ischar(diagnostic) || isstring(diagnostic));

            if isSupported
                testCase.verifyEmpty(char(diagnostic), ...
                    'a successful check reports no diagnostic');
            else
                testCase.verifyNotEmpty(char(diagnostic), ...
                    'a failed check must say why, so the caller can tell the failure modes apart');
            end
        end

        function ensureRemoteSupport_matchesWhatHasRemoteSupportReports(testCase)
            % The two must not disagree: whatever hasRemoteSupport says is what
            % ensureRemoteSupport acts on.
            remoteUrl = 'https://bucket.s3.amazonaws.com/store.zarr';
            [isSupported, diagnostic] = io.zarr.PyBackend.hasRemoteSupport();

            if isSupported
                testCase.verifyNoError(@() io.zarr.PyBackend.ensureRemoteSupport(remoteUrl));
                return;
            end

            raisedError = testCase.captureError(@() io.zarr.PyBackend.ensureRemoteSupport(remoteUrl));
            testCase.assertNotEmpty(raisedError, ...
                'a remote path must fail when support is absent');

            testCase.verifyTrue(ismember(raisedError.identifier, ...
                {'io:zarr:PyBackend:remoteDepsMissing', 'io:zarr:PyBackend:pythonTerminated'}), ...
                sprintf('unexpected identifier: %s', raisedError.identifier));

            if contains(diagnostic, 'terminated', 'IgnoreCase', true) || ...
                    contains(diagnostic, 'Python process', 'IgnoreCase', true)
                % This is the case that must NOT be reported as missing packages.
                testCase.verifyEqual(raisedError.identifier, 'io:zarr:PyBackend:pythonTerminated');
                testCase.verifySubstring(raisedError.message, 'not running');
                testCase.verifyFalse(contains(raisedError.message, 'pip install'), ...
                    'a dead interpreter must not be blamed on missing packages');
            else
                testCase.verifyEqual(raisedError.identifier, 'io:zarr:PyBackend:remoteDepsMissing');
            end
        end

        function remoteDepsMessage_namesThePackagesAndAnInstallCommand(testCase)
            % Only reachable when support is genuinely absent; skip otherwise
            % rather than faking the interpreter state.
            [isSupported, diagnostic] = io.zarr.PyBackend.hasRemoteSupport();
            testCase.assumeFalse(isSupported, ...
                'skipped: aiohttp and requests are installed, so the message cannot be raised');
            testCase.assumeFalse( ...
                contains(diagnostic, 'terminated', 'IgnoreCase', true) || ...
                contains(diagnostic, 'Python process', 'IgnoreCase', true), ...
                'skipped: the interpreter is dead, which raises the other message');

            raisedError = testCase.captureError( ...
                @() io.zarr.PyBackend.ensureRemoteSupport('https://bucket.s3.amazonaws.com/store.zarr'));
            testCase.assertNotEmpty(raisedError);
            testCase.assertEqual(raisedError.identifier, 'io:zarr:PyBackend:remoteDepsMissing');

            testCase.verifySubstring(raisedError.message, 'aiohttp');
            testCase.verifySubstring(raisedError.message, 'requests');
            testCase.verifySubstring(raisedError.message, 'pip install aiohttp requests');
            testCase.verifySubstring(raisedError.message, 'Python installation path', ...
                'the message must point at the preference that selects the interpreter');
            testCase.verifySubstring(raisedError.message, 'v3', ...
                'the message should note that remote zarr v3 needs no Python');
        end
    end

    methods (Access = private)
        function raisedError = captureError(~, functionToRun)
            % CAPTUREERROR - run a function and return its MException, or empty.
            %
            % verifyError cannot be used here: it does not return the exception,
            % and it invokes the handle requesting an output, which a function
            % declaring none rejects with MATLAB:TooManyOutputs.

            raisedError = MException.empty;
            try
                functionToRun();
            catch caughtError
                raisedError = caughtError;
            end
        end

        function verifyNoError(testCase, functionToRun)
            % VERIFYNOERROR - fail with the offending identifier if it throws.

            raisedError = testCase.captureError(functionToRun);
            if ~isempty(raisedError)
                testCase.verifyFail(sprintf('expected no error, but got %s: %s', ...
                    raisedError.identifier, raisedError.message));
            end
        end
    end

    methods (Test, TestTags = {'Integration', 'RequiresNetwork'})

        function openArray_readsARemoteV2ArrayWhenSupportIsPresent(testCase)
            % The end-to-end proof that the packages actually do their job: a
            % real read from the public OpenOrganelle store through PyBackend.
            testCase.assumeTrue(io.zarr.PyBackend.hasRemoteSupport(), ...
                'skipped: the Python environment has no aiohttp/requests, or is not running');
            testCase.assumeTrue(mibtest.helpers.hasNetwork('janelia-cosem-datasets.s3.amazonaws.com'), ...
                'skipped: the OpenOrganelle bucket is not reachable');

            % s7 is a small pyramid level - 387 x 167 x 184 voxels.
            arrayUrl = ['https://janelia-cosem-datasets.s3.amazonaws.com/jrc_mus-liver-zon-1/' ...
                'jrc_mus-liver-zon-1.zarr/recon-1/em/fibsem-uint8/s7'];

            pyArray  = io.zarr.PyBackend.openArray(arrayUrl, 'r');
            metadata = io.zarr.PyBackend.arrayMeta(pyArray);

            testCase.verifyEqual(metadata.shape, [387 167 184], ...
                'the declared shape is z, y, x in C order');
            testCase.verifyEqual(metadata.mtype, 'uint8');

            block = io.zarr.PyBackend.readArray(pyArray, [1 3; 1 65; 1 65], metadata);
            testCase.verifySize(block, [2 64 64]);
            testCase.verifyClass(block, 'uint8');
            testCase.verifyGreaterThan(max(block(:)), 0, ...
                'the sampled region should carry real image data, not only fill value');
        end
    end
end
