classdef OmeZarrGroupResolutionTest < matlab.unittest.TestCase
% OMEZARRGROUPRESOLUTIONTEST - Finding the image group inside a zarr container.
%
% Covers io.loaders.OmeZarrMetadataUtils.readGroupAttributes / listChildGroups /
% findMultiscalesGroups, and the ZarrGroupPath override in the two setup loaders.
%
% Real containers nest the image group: the OpenOrganelle / MoBIE layout puts it
% at <store>.zarr/recon-1/em/fibsem-uint8. The walk used to bail out entirely on
% a URL, because plain HTTP cannot list a directory - S3 can, through
% ListObjectsV2, which is what io.RemoteStore provides.
%
% Two behaviours are asserted deliberately and are NOT the same locally and
% remotely:
%
%   * Locally the walk collects every match up to maxDepth, because each step is
%     a dir() call and costs nothing.
%   * Remotely it stops at the shallowest level that yields a match, because
%     each step is a network round trip and the subtree below an image group can
%     be enormous - OpenOrganelle's labels/groundtruth holds 42 crops of ~40
%     class groups each.
%
% The remote walk also tests a whole level before expanding any of it. Expanding
% and testing in one pass would list the siblings of a match before the match is
% known about, which measured at roughly 60 requests instead of 15.

    properties (Constant, Access = private)
        JanelialRoot = ['https://janelia-cosem-datasets.s3.amazonaws.com/' ...
            'jrc_mus-liver-zon-1/jrc_mus-liver-zon-1.zarr'];
        JanelialHost = 'janelia-cosem-datasets.s3.amazonaws.com';
        ImageGroupRelativePath = 'recon-1/em/fibsem-uint8';
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function findMultiscalesGroups_collectsEveryDepthLocally(testCase)
            % The remote early-stop must not leak into the local walk.
            root = testCase.makeContainer({'shallow', 'branch', 'branch/deep'}, ...
                {'shallow', 'branch/deep'});

            found = io.loaders.OmeZarrMetadataUtils.findMultiscalesGroups(root, 2);
            relative = testCase.toRelative(root, found);

            testCase.verifyNumElements(found, 2, ...
                'a local walk collects matches at every depth');
            testCase.verifyTrue(ismember('shallow', relative));
            testCase.verifyTrue(ismember('branch/deep', relative));
            testCase.verifyEqual(relative{1}, 'shallow', ...
                'breadth-first order puts the shallowest match first');
        end

        function findMultiscalesGroups_neverDescendsIntoAMatch(testCase)
            % The children of an image group are its pyramid level arrays.
            root = testCase.makeContainer({'image', 'image/inner'}, {'image', 'image/inner'});

            found = io.loaders.OmeZarrMetadataUtils.findMultiscalesGroups(root, 2);
            relative = testCase.toRelative(root, found);

            testCase.verifyEqual(relative, {'image'}, ...
                'the nested group below a match must not be reported');
        end

        function findMultiscalesGroups_honoursMaxDepth(testCase)
            root = testCase.makeContainer({'a', 'a/b', 'a/b/c'}, {'a/b/c'});

            testCase.verifyEmpty(io.loaders.OmeZarrMetadataUtils.findMultiscalesGroups(root, 2, 1), ...
                'a match at depth 3 is out of reach with maxDepth 1');
            testCase.verifyNumElements( ...
                io.loaders.OmeZarrMetadataUtils.findMultiscalesGroups(root, 2, 3), 1);
        end

        function findMultiscalesGroups_returnsEmptyForAnUnusableRoot(testCase)
            testCase.verifyEmpty(io.loaders.OmeZarrMetadataUtils.findMultiscalesGroups( ...
                fullfile(tempdir, 'no-such-container-xyz'), 2));

            % Not listable, so nothing can be walked - and this must be decided
            % without touching the network, hence a Unit test.
            testCase.verifyEmpty(io.loaders.OmeZarrMetadataUtils.findMultiscalesGroups( ...
                'https://example.org/data/store.zarr', 2));
        end

        function listChildGroups_excludesArrays(testCase)
            % An array in a dimension_separator="/" store owns a huge chunk tree
            % that must never be walked into.
            root = testCase.makeContainer({'realGroup'}, {});
            arrayPath = fullfile(root, 'levelArray');
            mkdir(arrayPath);
            testCase.writeFile(fullfile(arrayPath, '.zarray'), '{"zarr_format":2,"shape":[4,4]}');

            children = io.loaders.OmeZarrMetadataUtils.listChildGroups(root, 2);
            relative = testCase.toRelative(root, children);

            testCase.verifyEqual(relative, {'realGroup'});
        end

        function loadImages_opensANestedLocalGroupViaRelativeZarrGroupPath(testCase)
            % BatchOpt.ZarrGroupPath is not only for remote stores: it lets a
            % batch protocol open a nested group of a LOCAL container without
            % the picker dialog. Offline, so it runs as a Unit test.
            root = testCase.makeContainer( ...
                {'recon-1', 'recon-1/em', 'recon-1/em/fibsem-uint8'}, {});
            imageGroup = fullfile(root, 'recon-1', 'em', 'fibsem-uint8');
            testCase.writeArrayLevel(imageGroup, 's0', [32 64 96]);   % z, y, x

            mibModel = mibtest.helpers.buildSyntheticModel();
            mibModel.preferences.System.DeveloperMode = false;
            datasetId = mibModel.getActiveId();
            placeholder = {fullfile(mibModel.mibPath, 'assets', 'images', 'default.h5')};
            testCase.assertEqual(mibModel.I{datasetId}.switchDatasetMode(3, ...
                mibModel.preferences.System.EnableSelection, placeholder), 3);

            loadOptions = struct();
            loadOptions.Mode          = {'Combine datasets'};
            loadOptions.Filenames     = {root};
            loadOptions.DirectoryName = {mibModel.currentDirectory};
            loadOptions.Reader        = {'Default'};
            loadOptions.showWaitbar   = false;
            loadOptions.ZarrGroupPath = 'recon-1/em/fibsem-uint8';
            loadOptions.id            = datasetId;
            mibModel.loadImages('Combine datasets', loadOptions);

            image = mibModel.I{datasetId}.image;
            testCase.verifyEqual(image.dim_yxzct(1:3), [64 96 32], ...
                'the [z y x] store shape must map to MIB [y x z]');
            testCase.verifyEqual(image.filePaths{1}, imageGroup, ...
                'a relative group path must resolve against the container root');
        end

        function readGroupAttributes_toleratesAMissingOrBrokenFile(testCase)
            root = testCase.makeContainer({'plain'}, {});
            testCase.verifyEmpty(fieldnames( ...
                io.loaders.OmeZarrMetadataUtils.readGroupAttributes(fullfile(root, 'plain'), 2)), ...
                'a group with no .zattrs simply has no attributes');

            brokenPath = fullfile(root, 'broken');
            mkdir(brokenPath);
            testCase.writeFile(fullfile(brokenPath, '.zattrs'), '{not valid json');
            testCase.verifyEmpty(fieldnames( ...
                io.loaders.OmeZarrMetadataUtils.readGroupAttributes(brokenPath, 2)), ...
                'unparsable metadata must not throw');
        end
    end

    methods (Test, TestTags = {'Integration', 'RequiresNetwork'})

        function findMultiscalesGroups_findsTheNestedJanelialImageGroup(testCase)
            testCase.assumeTrue(mibtest.helpers.hasNetwork(testCase.JanelialHost), ...
                'skipped: the OpenOrganelle bucket is not reachable');

            io.RemoteStore.clearCache();
            testCase.addTeardown(@() io.RemoteStore.clearCache());

            found = io.loaders.OmeZarrMetadataUtils.findMultiscalesGroups(testCase.JanelialRoot, 2);

            testCase.verifyNumElements(found, 1, ...
                'the walk must stop at the image group, not descend into labels/groundtruth');
            testCase.verifyEqual( ...
                io.loaders.OmeZarrMetadataUtils.relativeGroupPath(testCase.JanelialRoot, found{1}), ...
                testCase.ImageGroupRelativePath);
        end

        function remoteHelpers_classifyGroupsAndArrays(testCase)
            testCase.assumeTrue(mibtest.helpers.hasNetwork(testCase.JanelialHost), ...
                'skipped: the OpenOrganelle bucket is not reachable');

            root = testCase.JanelialRoot;
            imageGroup = io.RemoteStore.join(root, testCase.ImageGroupRelativePath);

            children = io.loaders.OmeZarrMetadataUtils.listChildGroups( ...
                io.RemoteStore.join(root, 'recon-1'), 2);
            childNames = cellfun(@(p) io.RemoteStore.relativePath( ...
                io.RemoteStore.join(root, 'recon-1'), p), children, 'UniformOutput', false);
            testCase.verifyEqual(sort(childNames), {'em', 'labels'});

            testCase.verifyEmpty( ...
                io.loaders.OmeZarrMetadataUtils.listChildGroups(imageGroup, 2), ...
                's0..s14 are arrays, so the image group has no child GROUPS');

            attributes = io.loaders.OmeZarrMetadataUtils.readGroupAttributes(imageGroup, 2);
            testCase.verifyTrue(isfield(attributes, 'multiscales'));
            testCase.verifyNumElements(attributes.multiscales(1).datasets, 15);
        end

        function loader_acceptsARelativeZarrGroupPath(testCase)
            % The batch-friendly form: the protocol carries the short readable
            % path, not the whole URL a second time.
            testCase.assumeTrue(mibtest.helpers.hasNetwork(testCase.JanelialHost), ...
                'skipped: the OpenOrganelle bucket is not reachable');
            testCase.assumeTrue(io.zarr.PyBackend.hasRemoteSupport(), ...
                'skipped: the Python environment cannot reach remote stores');

            options = struct('datasetMode', 'BigData', 'ParentFigure', [], 'waitbar', false, ...
                'ZarrGroupPath', testCase.ImageGroupRelativePath);
            loader = io.loaders.Zarr2VirtualSetupLoader(options);
            imageInfo = loader.loadMetadata({testCase.JanelialRoot}, options);

            testCase.verifyEqual(imageInfo{'Height'}, 21451);
            testCase.verifyEqual(imageInfo{'Width'},  23601);
            testCase.verifyEqual(imageInfo{'Depth'},  49645);
        end

        function loader_resolvesTheImageGroupFromTheStoreRoot(testCase)
            % No ZarrGroupPath at all: the loader has to find it by itself.
            testCase.assumeTrue(mibtest.helpers.hasNetwork(testCase.JanelialHost), ...
                'skipped: the OpenOrganelle bucket is not reachable');
            testCase.assumeTrue(io.zarr.PyBackend.hasRemoteSupport(), ...
                'skipped: the Python environment cannot reach remote stores');

            io.RemoteStore.clearCache();
            testCase.addTeardown(@() io.RemoteStore.clearCache());

            options = struct('datasetMode', 'BigData', 'ParentFigure', [], 'waitbar', false);
            loader = io.loaders.Zarr2VirtualSetupLoader(options);
            imageInfo = loader.loadMetadata({testCase.JanelialRoot}, options);

            testCase.verifyEqual(imageInfo{'Height'}, 21451);
            testCase.verifyEqual(imageInfo{'Depth'},  49645);
        end
    end

    methods (Access = private)
        function root = makeContainer(testCase, groupRelativePaths, multiscalesRelativePaths)
            % MAKECONTAINER - Build a temporary zarr v2 group tree.
            %
            % Every listed relative path becomes a group carrying .zgroup; those
            % also listed in multiscalesRelativePaths get a minimal multiscales
            % .zattrs so they read as image groups.

            root = [tempname, '.zarr'];
            mkdir(root);
            testCase.addTeardown(@() rmdir(root, 's'));
            testCase.writeFile(fullfile(root, '.zgroup'), '{"zarr_format":2}');

            for pathIndex = 1:numel(groupRelativePaths)
                groupPath = fullfile(root, groupRelativePaths{pathIndex});
                if ~isfolder(groupPath); mkdir(groupPath); end
                testCase.writeFile(fullfile(groupPath, '.zgroup'), '{"zarr_format":2}');
            end

            multiscalesJson = ['{"multiscales":[{"axes":[{"name":"y"},{"name":"x"}],' ...
                '"datasets":[{"path":"0","coordinateTransformations":' ...
                '[{"type":"scale","scale":[1,1]}]}]}]}'];
            for pathIndex = 1:numel(multiscalesRelativePaths)
                testCase.writeFile( ...
                    fullfile(root, multiscalesRelativePaths{pathIndex}, '.zattrs'), multiscalesJson);
            end
        end

        function writeArrayLevel(testCase, groupPath, levelName, storeShape)
            % WRITEARRAYLEVEL - Add a multiscales attribute plus one level array.
            %
            % Only metadata: BigData and Virtual modes never read pixels at open
            % time, so a .zarray is enough to describe the level.

            multiscalesJson = ['{"multiscales":[{"axes":[' ...
                '{"name":"z","type":"space","unit":"nanometer"},' ...
                '{"name":"y","type":"space","unit":"nanometer"},' ...
                '{"name":"x","type":"space","unit":"nanometer"}],' ...
                '"datasets":[{"path":"' levelName '","coordinateTransformations":' ...
                '[{"type":"scale","scale":[8,8,8]}]}]}]}'];
            testCase.writeFile(fullfile(groupPath, '.zattrs'), multiscalesJson);

            levelPath = fullfile(groupPath, levelName);
            mkdir(levelPath);
            arrayJson = sprintf(['{"chunks":[8,16,16],"compressor":null,"dtype":"|u1",' ...
                '"fill_value":0,"filters":null,"order":"C","shape":[%d,%d,%d],' ...
                '"zarr_format":2,"dimension_separator":"/"}'], ...
                storeShape(1), storeShape(2), storeShape(3));
            testCase.writeFile(fullfile(levelPath, '.zarray'), arrayJson);
        end

        function writeFile(testCase, filePath, contents)
            fileId = fopen(filePath, 'w');
            testCase.assertGreaterThan(fileId, 0, sprintf('could not create %s', filePath));
            fprintf(fileId, '%s', contents);
            fclose(fileId);
        end

        function relative = toRelative(~, root, absolutePaths)
            % Separators are normalised to '/' so the same expectations hold for
            % a local Windows path and for a URL.
            relative = cellfun( ...
                @(p) strrep(io.loaders.OmeZarrMetadataUtils.relativeGroupPath(root, p), '\', '/'), ...
                absolutePaths, 'UniformOutput', false);
        end
    end
end
