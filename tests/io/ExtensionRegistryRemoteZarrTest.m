classdef ExtensionRegistryRemoteZarrTest < matlab.unittest.TestCase
% EXTENSIONREGISTRYREMOTEZARRTEST - Zarr version detection and loader routing.
%
% Covers io.ExtensionRegistryLoad.detectZarrFormatExtension,
% io.ExtensionRegistryLoad.probeRemoteZarr and the resolveLoader branch that
% uses them.
%
% The bug being guarded: detectZarrFormatExtension probes with isfile(), which
% cannot see a URL, so before probeRemoteZarr existed every remote store fell
% through to the 'zarr3' default. An OME-Zarr **v2** store served over HTTPS -
% which is what OpenOrganelle, MoBIE and most published NGFF v0.4 data are -
% was therefore handed to the v3-only loader, which cannot read it.
%
% Local detection is asserted alongside so the remote branch cannot regress it.

    properties (Constant, Access = private)
        JanelialRoot = ['https://janelia-cosem-datasets.s3.amazonaws.com/' ...
            'jrc_mus-liver-zon-1/jrc_mus-liver-zon-1.zarr'];
        JanelialHost = 'janelia-cosem-datasets.s3.amazonaws.com';
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (TestMethodSetup)
        function startFromColdCaches(testCase)
            % The probe and the listing are both memoised for the session, so a
            % test that ran earlier could otherwise answer for this one.
            io.ExtensionRegistryLoad.clearRemoteProbeCache();
            io.RemoteStore.clearCache();
            testCase.addTeardown(@() io.ExtensionRegistryLoad.clearRemoteProbeCache());
            testCase.addTeardown(@() io.RemoteStore.clearCache());
        end
    end

    methods (Test, TestTags = {'Unit'})

        function detect_readsLocalMarkerFiles(testCase)
            v2Store = testCase.makeStore('.zgroup', '{"zarr_format":2}');
            v3Store = testCase.makeStore('zarr.json', '{"zarr_format":3,"node_type":"group"}');

            testCase.verifyEqual(io.ExtensionRegistryLoad.detectZarrFormatExtension(v2Store), 'zarr2');
            testCase.verifyEqual(io.ExtensionRegistryLoad.detectZarrFormatExtension(v3Store), 'zarr3');
        end

        function detect_acceptsAnyV2Marker(testCase)
            % A node may be a group (.zgroup), a bare attribute holder (.zattrs)
            % or an array (.zarray) - all three identify zarr v2.
            for marker = {'.zgroup', '.zattrs', '.zarray'}
                store = testCase.makeStore(marker{1}, '{}');
                testCase.verifyEqual(io.ExtensionRegistryLoad.detectZarrFormatExtension(store), ...
                    'zarr2', sprintf('marker %s must identify v2', marker{1}));
            end
        end

        function detect_keepsV3DefaultForAnUnprobeableLocalPath(testCase)
            emptyFolder = testCase.makeStore('', '');
            testCase.verifyEqual(io.ExtensionRegistryLoad.detectZarrFormatExtension(emptyFolder), ...
                'zarr3', 'the legacy fallback must be preserved');
            testCase.verifyEqual(io.ExtensionRegistryLoad.detectZarrFormatExtension( ...
                fullfile(tempdir, 'no-such-store-xyz.zarr')), 'zarr3');
        end

        function probeRemoteZarr_returnsEmptyForLocalPaths(testCase)
            % The tri-state return is what lets resolveLoader tell "not a zarr"
            % apart from "a v3 zarr"; a local path is simply not its business.
            store = testCase.makeStore('.zgroup', '{"zarr_format":2}');
            testCase.verifyEmpty(io.ExtensionRegistryLoad.probeRemoteZarr(store));
            testCase.verifyEmpty(io.ExtensionRegistryLoad.probeRemoteZarr(''));
        end

        function resolveLoader_routesLocalZarrByVersion(testCase)
            registry = io.ExtensionRegistryLoad();

            v2Store = testCase.makeStore('.zgroup', '{"zarr_format":2}');
            route = registry.resolveLoader(v2Store, 'BigData', 'Default');
            testCase.verifyEqual(route.extension, 'zarr2');
            testCase.verifyEqual(char(route.loaderId), 'OmeZarrV2');

            v3Store = testCase.makeStore('zarr.json', '{"zarr_format":3,"node_type":"group"}');
            route = registry.resolveLoader(v3Store, 'BigData', 'Default');
            testCase.verifyEqual(route.extension, 'zarr3');
            testCase.verifyEqual(char(route.loaderId), 'OmeZarr');
        end

        function resolveLoader_leavesOrdinaryLocalFormatsAlone(testCase)
            registry = io.ExtensionRegistryLoad();

            route = registry.resolveLoader('C:\data\stack.tif', 'Standard', 'Default');
            testCase.verifyEqual(route.extension, 'tif');
            testCase.verifyEqual(char(route.loaderId), 'imread');

            route = registry.resolveLoader('C:\data\stack.zarr3', 'Virtual', 'Default');
            testCase.verifyEqual(char(route.loaderId), 'OmeZarr', ...
                'an explicit .zarr3 suffix must not trigger a probe');
        end

        function resolveLoader_stillRejectsAnIncompatibleModeAndReader(testCase)
            registry = io.ExtensionRegistryLoad();
            v2Store  = testCase.makeStore('.zgroup', '{"zarr_format":2}');
            outcome  = registry.resolveLoader(v2Store, 'Standard', 'BioFormats');
            testCase.verifyClass(outcome, 'char', ...
                'an incompatible combination still returns an error message, not a route');
        end
    end

    methods (Test, TestTags = {'Integration', 'RequiresNetwork'})

        function probeRemoteZarr_identifiesTheJanelialStoreAsV2(testCase)
            testCase.assumeTrue(mibtest.helpers.hasNetwork(testCase.JanelialHost), ...
                'skipped: the OpenOrganelle bucket is not reachable');

            root  = testCase.JanelialRoot;
            group = io.RemoteStore.join(root, 'recon-1/em/fibsem-uint8');

            testCase.verifyEqual(io.ExtensionRegistryLoad.probeRemoteZarr(root), 'zarr2', ...
                'the store root carries a .zgroup marker');
            testCase.verifyEqual(io.ExtensionRegistryLoad.probeRemoteZarr(group), 'zarr2', ...
                'a nested image group with no filename extension must still be probed');
            testCase.verifyEqual(io.ExtensionRegistryLoad.probeRemoteZarr( ...
                io.RemoteStore.join(group, 's7')), 'zarr2', ...
                'an array node carries .zarray');

            % This is the regression the whole step exists for.
            testCase.verifyEqual(io.ExtensionRegistryLoad.detectZarrFormatExtension(root), 'zarr2', ...
                'before the remote branch this returned the zarr3 default');
        end

        function probeRemoteZarr_returnsEmptyForANonZarrLocation(testCase)
            testCase.assumeTrue(mibtest.helpers.hasNetwork(testCase.JanelialHost), ...
                'skipped: the OpenOrganelle bucket is not reachable');

            notAStore = ['https://janelia-cosem-datasets.s3.amazonaws.com/' ...
                'jrc_mus-liver-zon-1/neuroglancer'];
            testCase.verifyEmpty(io.ExtensionRegistryLoad.probeRemoteZarr(notAStore), ...
                'a prefix with no zarr marker must not be claimed as a store');
        end

        function resolveLoader_routesTheRemoteGroupToTheV2Loader(testCase)
            testCase.assumeTrue(mibtest.helpers.hasNetwork(testCase.JanelialHost), ...
                'skipped: the OpenOrganelle bucket is not reachable');

            registry = io.ExtensionRegistryLoad();
            group = io.RemoteStore.join(testCase.JanelialRoot, 'recon-1/em/fibsem-uint8');

            for mode = {'BigData', 'Virtual', 'Standard'}
                route = registry.resolveLoader(group, mode{1}, 'Default');
                context = sprintf('mode %s', mode{1});
                testCase.verifyClass(route, 'struct', context);
                testCase.verifyEqual(route.extension, 'zarr2', context);
                testCase.verifyEqual(char(route.loaderId), 'OmeZarrV2', context);
            end
        end

        function resolveLoader_leavesARemoteOrdinaryImageOnImread(testCase)
            testCase.assumeTrue(mibtest.helpers.hasNetwork('mib.helsinki.fi'), ...
                'skipped: mib.helsinki.fi is not reachable');

            % A known filename extension short-circuits the probe, so this must
            % also be answered without any network traffic at all.
            registry = io.ExtensionRegistryLoad();
            route = registry.resolveLoader( ...
                'https://mib.helsinki.fi/images/im_browser_splash.jpg', 'Standard', 'Default');
            testCase.verifyEqual(route.extension, 'jpg');
            testCase.verifyEqual(char(route.loaderId), 'imread');
        end
    end

    methods (Access = private)
        function storePath = makeStore(testCase, markerName, markerContent)
            % MAKESTORE - Temporary "*.zarr" folder holding one marker file.
            %
            % The folder has to end in .zarr for resolveLoader to reach the
            % version probe at all, which is how real stores are named.

            storePath = [tempname, '.zarr'];
            mkdir(storePath);
            testCase.addTeardown(@() rmdir(storePath, 's'));

            if ~isempty(markerName)
                fileId = fopen(fullfile(storePath, markerName), 'w');
                testCase.assertGreaterThan(fileId, 0, 'could not create the marker file');
                fprintf(fileId, '%s', markerContent);
                fclose(fileId);
            end
        end
    end
end
