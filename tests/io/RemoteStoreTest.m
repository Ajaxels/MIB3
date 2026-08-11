classdef RemoteStoreTest < matlab.unittest.TestCase
% REMOTESTORETEST - Tests for io.RemoteStore URL handling and S3 listing.
%
% The listing tests run offline by injecting options.fetchFcn, so the whole
% Unit block is network-free; a single Integration test exercises the real
% Janelia OpenOrganelle bucket and self-skips when it cannot be resolved.
%
% The sample XML deliberately reproduces two things the real S3 response does
% and that the parser has to survive: the default xmlns on ListBucketResult,
% and the top-level <Prefix> element echoing the request prefix. The latter
% shares a tag name with the child prefixes inside <CommonPrefixes>, so a
% parser that scans for bare <Prefix> tags reports the node as a child of
% itself.

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

    methods (Test, TestTags = {'Unit'})

        function isRemote_acceptsSchemesAndRejectsLocalPaths(testCase)
            testCase.verifyTrue(io.RemoteStore.isRemote('https://host/key'));
            testCase.verifyTrue(io.RemoteStore.isRemote('http://host/key'));
            testCase.verifyTrue(io.RemoteStore.isRemote('s3://bucket/key'));
            testCase.verifyTrue(io.RemoteStore.isRemote("  https://host/key  "), ...
                'leading or trailing whitespace must not defeat detection');

            testCase.verifyFalse(io.RemoteStore.isRemote('C:\data\local.zarr'));
            testCase.verifyFalse(io.RemoteStore.isRemote('/mnt/data/local.zarr'));
            testCase.verifyFalse(io.RemoteStore.isRemote(''));
            testCase.verifyFalse(io.RemoteStore.isRemote([]));
        end

        function normalise_rewritesS3SchemeAndStripsTrailingSlash(testCase)
            testCase.verifyEqual(io.RemoteStore.normalise('s3://bucket/a/b.zarr'), ...
                'https://bucket.s3.amazonaws.com/a/b.zarr');
            testCase.verifyEqual(io.RemoteStore.normalise('s3://bucket/a/b.zarr/'), ...
                'https://bucket.s3.amazonaws.com/a/b.zarr');
            testCase.verifyEqual(io.RemoteStore.normalise('https://host/a///'), 'https://host/a');
            testCase.verifyEqual(io.RemoteStore.normalise('C:\data\local.zarr'), ...
                'C:\data\local.zarr', 'local paths must pass through untouched');
        end

        function parse_recognisesEveryS3UrlShape(testCase)
            expected = {
                's3://bkt/a/b.zarr',                              'bkt', 'a/b.zarr', ''
                'https://bkt.s3.amazonaws.com/a/b.zarr',          'bkt', 'a/b.zarr', ''
                'https://bkt.s3.us-west-2.amazonaws.com/a/b.zarr','bkt', 'a/b.zarr', 'us-west-2'
                'https://bkt.s3-us-west-2.amazonaws.com/a/b.zarr','bkt', 'a/b.zarr', 'us-west-2'
                'https://s3.us-west-2.amazonaws.com/bkt/a/b.zarr','bkt', 'a/b.zarr', 'us-west-2'
                'https://s3.amazonaws.com/bkt/a/b.zarr',          'bkt', 'a/b.zarr', ''};

            for rowIdx = 1:size(expected, 1)
                info = io.RemoteStore.parse(expected{rowIdx, 1});
                context = sprintf('parsing %s', expected{rowIdx, 1});
                testCase.verifyEqual(info.bucket,   expected{rowIdx, 2}, context);
                testCase.verifyEqual(info.key,      expected{rowIdx, 3}, context);
                testCase.verifyEqual(info.region,   expected{rowIdx, 4}, context);
                testCase.verifyEqual(info.flavour,  's3', context);
                testCase.verifyTrue(info.listable, context);
                testCase.verifyTrue(endsWith(info.listEndpoint, '/'), ...
                    'listEndpoint must keep its trailing slash so query args append cleanly');
            end
        end

        function parse_handlesBucketNamesContainingDots(testCase)
            % A lazy match up to the '.s3' label is what makes this work; a
            % "single label" pattern would take only the first segment.
            info = io.RemoteStore.parse('https://my.dotted.bucket.s3.amazonaws.com/a/b');
            testCase.verifyEqual(info.bucket, 'my.dotted.bucket');
            testCase.verifyEqual(info.key, 'a/b');

            info = io.RemoteStore.parse('s3://my.dotted.bucket/a/b');
            testCase.verifyEqual(info.bucket, 'my.dotted.bucket');
        end

        function parse_readsAnyOtherHostAsPathStyle(testCase)
            % Nothing about ListObjectsV2 is Amazon-specific: MinIO and Ceph
            % deployments serve it from their own domain. The AWS patterns exist
            % only to tell Amazon's two spellings apart, so a host that matches
            % none of them must still be tried, with the endpoint taken from the
            % URL rather than from a hardcoded one.
            pathStyle = io.RemoteStore.parse('https://s3.example.org/my-bucket/my-dataset.zarr');
            testCase.verifyEqual(pathStyle.flavour, 's3compatible');
            testCase.verifyEqual(pathStyle.bucket, 'my-bucket');
            testCase.verifyEqual(pathStyle.key, 'my-dataset.zarr');
            testCase.verifyEqual(pathStyle.listEndpoint, 'https://s3.example.org/my-bucket/');
            testCase.verifyTrue(pathStyle.listable);
            testCase.verifyFalse(contains(pathStyle.listEndpoint, 'amazonaws'), ...
                'the endpoint must come from the pasted URL, never from a default');

            % The guess is unconfirmed, hence its own flavour: callers that care
            % about the difference check that rather than listable.
            plain = io.RemoteStore.parse('https://example.org/data/b.zarr');
            testCase.verifyEqual(plain.flavour, 's3compatible');
            testCase.verifyEqual(plain.bucket, 'data');
        end

        function parse_marksHostsWithNoUsableListingApi(testCase)
            gcs = io.RemoteStore.parse('https://storage.googleapis.com/bkt/a/b.zarr');
            testCase.verifyEqual(gcs.flavour, 'gcs');
            testCase.verifyEqual(gcs.bucket, 'bkt');
            testCase.verifyFalse(gcs.listable, 'the GCS v1 marker API is not implemented');

            % No path segment, so there is no bucket to name.
            bare = io.RemoteStore.parse('https://example.org');
            testCase.verifyEqual(bare.flavour, 'plain');
            testCase.verifyFalse(bare.listable);

            local = io.RemoteStore.parse('C:\data\local.zarr');
            testCase.verifyEqual(local.flavour, 'local');
            testCase.verifyFalse(local.listable);
        end

        function parse_bucketRootHasEmptyKey(testCase)
            info = io.RemoteStore.parse('https://bkt.s3.amazonaws.com/');
            testCase.verifyEqual(info.bucket, 'bkt');
            testCase.verifyEmpty(info.key, ...
                'an empty key means the bucket root and must not become a "/" prefix');
        end

        function join_usesForwardSlashesOnly(testCase)
            % fullfile would produce a backslash here on Windows and corrupt the URL.
            joined = io.RemoteStore.join('https://host/root', 'a/b');
            testCase.verifyEqual(joined, 'https://host/root/a/b');
            testCase.verifyFalse(contains(joined, '\'), 'a URL must never contain a backslash');

            testCase.verifyEqual(io.RemoteStore.join('https://host/root/', '/a/b/'), ...
                'https://host/root/a/b', 'redundant slashes on either side must collapse');
            testCase.verifyEqual(io.RemoteStore.join('https://host/root', ''), ...
                'https://host/root', 'an empty relative path returns the base');
            testCase.verifyEqual(io.RemoteStore.join('https://host/root', 'a\b'), ...
                'https://host/root/a/b', 'a Windows-style separator must be rewritten');
        end

        function join_passesThroughAnAbsoluteUrl(testCase)
            % Lets a caller accept either a relative group path or a full URL
            % from the user without having to tell them apart first.
            testCase.verifyEqual(io.RemoteStore.join('https://host/root', 's3://bkt/key'), ...
                'https://bkt.s3.amazonaws.com/key');
        end

        function relativePath_invertsJoin(testCase)
            root = 'https://host/root';
            testCase.verifyEqual(io.RemoteStore.relativePath(root, ...
                io.RemoteStore.join(root, 'recon-1/em/fibsem-uint8')), 'recon-1/em/fibsem-uint8');
            testCase.verifyEqual(io.RemoteStore.relativePath(root, root), '', ...
                'the root itself is the empty relative path');
            testCase.verifyEqual(io.RemoteStore.relativePath(root, 'https://host/other/x'), ...
                'https://host/other/x', 'a URL outside the root is returned unchanged');
            testCase.verifyEqual(io.RemoteStore.relativePath(root, 'https://host/rootlike/x'), ...
                'https://host/rootlike/x', 'a shared string prefix is not a shared path prefix');
        end

        function listChildren_separatesChildGroupsFromFiles(testCase)
            options = testCase.offlineOptions(testCase.singlePageListing());
            [childUrls, childNames, fileNames] = io.RemoteStore.listChildren( ...
                'https://bkt.s3.amazonaws.com/root', options);

            testCase.verifyEqual(childNames, {'child-a', 'child-b'});
            testCase.verifyEqual(fileNames,  {'.zattrs', '.zgroup'});
            testCase.verifyEqual(childUrls, { ...
                'https://bkt.s3.amazonaws.com/root/child-a', ...
                'https://bkt.s3.amazonaws.com/root/child-b'});
        end

        function listChildren_ignoresTheEchoedRequestPrefix(testCase)
            % ListBucketResult repeats the request prefix in a top-level <Prefix>
            % element. Scanning for bare <Prefix> tags would report the node as
            % its own child, which is the specific bug this guards.
            options = testCase.offlineOptions(testCase.singlePageListing());
            [~, childNames] = io.RemoteStore.listChildren( ...
                'https://bkt.s3.amazonaws.com/root', options);

            testCase.verifyNotEmpty(childNames);
            testCase.verifyFalse(any(cellfun(@isempty, childNames)), ...
                'the echoed request prefix must not appear as an empty-named child');
            testCase.verifyFalse(ismember('root', childNames));
        end

        function listChildren_followsTheContinuationToken(testCase)
            % Two pages, so the continuation loop must run exactly twice and
            % concatenate. Also asserts the token from page 1 is sent back.
            pages = {testCase.truncatedFirstPage(), testCase.finalSecondPage()};
            requestedTokens = {};

            fetchFcn = @(listEndpoint, prefix, continuationToken, timeout, maxKeys) ...
                recordAndServe(continuationToken);

            options = struct('useCache', false, 'fetchFcn', fetchFcn);
            [~, childNames] = io.RemoteStore.listChildren( ...
                'https://bkt.s3.amazonaws.com/root', options);

            testCase.verifyEqual(childNames, {'child-a', 'child-b', 'child-c'});
            testCase.verifyEqual(numel(requestedTokens), 2, 'expected exactly two requests');
            testCase.verifyEmpty(requestedTokens{1}, 'the first request carries no token');
            testCase.verifyEqual(requestedTokens{2}, 'TOKEN-PAGE-2');

            function xmlText = recordAndServe(continuationToken)
                requestedTokens{end+1} = continuationToken;
                xmlText = pages{numel(requestedTokens)};
            end
        end

        function listChildren_unescapesXmlEntitiesInNames(testCase)
            options = testCase.offlineOptions(testCase.entityListing());
            [~, childNames, fileNames] = io.RemoteStore.listChildren( ...
                'https://bkt.s3.amazonaws.com/root', options);

            testCase.verifyEqual(childNames, {'a&b'});
            testCase.verifyEqual(fileNames,  {'x<y>.txt'});
        end

        function listChildren_returnsEmptyForAHostThatCannotBeListed(testCase)
            % Not an error: the caller degrades to asking for an explicit path.
            [childUrls, childNames, fileNames] = io.RemoteStore.listChildren( ...
                'https://example.org/data/b.zarr');
            testCase.verifyEmpty(childUrls);
            testCase.verifyEmpty(childNames);
            testCase.verifyEmpty(fileNames);
        end

        function listChildren_returnsEmptyWhenTheFetchFails(testCase)
            options = struct('useCache', false, ...
                'fetchFcn', @(varargin) error('io:test:networkDown', 'simulated failure'));
            [~, childNames] = io.RemoteStore.listChildren( ...
                'https://bkt.s3.amazonaws.com/root', options);
            testCase.verifyEmpty(childNames, ...
                'a listing failure must degrade quietly, not propagate');
        end

        function listChildren_returnsEmptyForNonXmlBody(testCase)
            % A captive portal or proxy can answer with HTML.
            options = testCase.offlineOptions('<html><body>403 Forbidden</body></html>');
            [~, childNames] = io.RemoteStore.listChildren( ...
                'https://bkt.s3.amazonaws.com/root', options);
            testCase.verifyEmpty(childNames);
        end

        function listChildren_cachesPerUrlAndClearCacheDropsIt(testCase)
            callCount = 0;
            pageXml = testCase.singlePageListing();
            options = struct('useCache', true, 'fetchFcn', @countingFetch);
            url = 'https://bkt.s3.amazonaws.com/cache-probe';

            io.RemoteStore.clearCache();
            testCase.addTeardown(@() io.RemoteStore.clearCache());

            io.RemoteStore.listChildren(url, options);
            io.RemoteStore.listChildren(url, options);
            testCase.verifyEqual(callCount, 1, 'the second call must be served from cache');

            io.RemoteStore.clearCache();
            io.RemoteStore.listChildren(url, options);
            testCase.verifyEqual(callCount, 2, 'clearCache must force a refetch');

            function xmlText = countingFetch(varargin)
                callCount = callCount + 1;
                xmlText = pageXml;
            end
        end
    end

    methods (Test, TestTags = {'Integration', 'RequiresNetwork'})

        function listChildren_walksTheRealJanelialStore(testCase)
            testCase.assumeTrue(mibtest.helpers.hasNetwork(testCase.JanelialHost), ...
                'skipped: the OpenOrganelle bucket is not reachable');

            root = testCase.JanelialRoot;
            io.RemoteStore.clearCache();
            testCase.addTeardown(@() io.RemoteStore.clearCache());

            [~, rootChildren, rootFiles] = io.RemoteStore.listChildren(root);
            testCase.verifyEqual(rootChildren, {'recon-1'});
            testCase.verifyTrue(ismember('.zgroup', rootFiles), ...
                'a zarr v2 group must expose a .zgroup marker');

            [~, reconChildren] = io.RemoteStore.listChildren(io.RemoteStore.join(root, 'recon-1'));
            testCase.verifyTrue(all(ismember({'em', 'labels'}, reconChildren)));

            imageGroup = io.RemoteStore.join(root, 'recon-1/em/fibsem-uint8');
            [~, levelNames] = io.RemoteStore.listChildren(imageGroup);
            testCase.verifyEqual(numel(levelNames), 15, 'the EM pyramid has 15 levels');
            testCase.verifyTrue(all(startsWith(levelNames, 's')));

            % exists() is the primitive the zarr version probe is built on, so
            % assert it separates a v2 store from a v3 one.
            testCase.verifyTrue(io.RemoteStore.exists([root '/.zgroup']));
            testCase.verifyFalse(io.RemoteStore.exists([root '/zarr.json']));

            attributes = io.RemoteStore.readJson([imageGroup '/.zattrs']);
            testCase.verifyNotEmpty(attributes);
            testCase.verifyTrue(isfield(attributes, 'multiscales'));
            testCase.verifyEmpty(io.RemoteStore.readJson([root '/does-not-exist']), ...
                'a missing metadata file returns empty rather than throwing');
        end

        function listChildren_walksAnS3CompatibleHostThatIsNotAws(testCase)
            % The point of the generic path-style rule: a MinIO or Ceph endpoint
            % serves ListObjectsV2 from its own domain, so it matches none of the
            % AWS host patterns yet must browse identically. Offline parsing
            % cannot prove the endpoint answers - only this can.
            %
            % No store URL is hardcoded here on purpose. The stores this rule was
            % developed against are not public, and a test file is the wrong place
            % to publish one. Point the test at any path-style S3 host holding an
            % OME-Zarr store::
            %
            %   setenv('MIB3_S3COMPATIBLE_ZARR_URL', 'https://HOST/BUCKET/store.zarr')
            root = getenv('MIB3_S3COMPATIBLE_ZARR_URL');
            testCase.assumeNotEmpty(root, ...
                'skipped: set MIB3_S3COMPATIBLE_ZARR_URL to a path-style S3 OME-Zarr store');

            hostName = regexprep(root, '^https?://([^/]+)/.*$', '$1');
            testCase.assumeTrue(mibtest.helpers.hasNetwork(hostName), ...
                sprintf('skipped: %s is not reachable', hostName));

            io.RemoteStore.clearCache();
            testCase.addTeardown(@() io.RemoteStore.clearCache());

            info = io.RemoteStore.parse(root);
            testCase.verifyEqual(info.flavour, 's3compatible');
            testCase.verifyTrue(info.listable);
            testCase.verifyFalse(contains(info.listEndpoint, 'amazonaws'), ...
                'the endpoint must be taken from the URL, not from an AWS default');

            % Assert the shape of the result, not the contents of one store: a
            % listing that comes back at all is what proves the endpoint answered.
            [childUrls, childNames, rootFiles] = io.RemoteStore.listChildren(root);
            testCase.verifyNotEmpty(childNames, ...
                'a path-style host must return a listing, not an empty degradation');
            testCase.verifyEqual(numel(childUrls), numel(childNames));
            testCase.verifyTrue(any(ismember({'.zgroup', 'zarr.json'}, rootFiles)), ...
                'the store root must expose zarr group metadata');
            testCase.verifyTrue(ismember(io.ExtensionRegistryLoad.probeRemoteZarr(root), ...
                {'zarr2', 'zarr3'}));
        end
    end

    methods (Access = private)
        function options = offlineOptions(~, xmlText)
            % OFFLINEOPTIONS - listChildren options serving fixed XML, cache off.
            options = struct('useCache', false, 'fetchFcn', @(varargin) xmlText);
        end

        function xmlText = singlePageListing(~)
            xmlText = [ ...
                '<?xml version="1.0" encoding="UTF-8"?>' newline ...
                '<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">' newline ...
                '<Name>bkt</Name>' newline ...
                '<Prefix>root/</Prefix>' newline ...
                '<Delimiter>/</Delimiter>' newline ...
                '<IsTruncated>false</IsTruncated>' newline ...
                '<Contents><Key>root/.zattrs</Key><Size>2</Size></Contents>' newline ...
                '<Contents><Key>root/.zgroup</Key><Size>24</Size></Contents>' newline ...
                '<CommonPrefixes><Prefix>root/child-a/</Prefix></CommonPrefixes>' newline ...
                '<CommonPrefixes><Prefix>root/child-b/</Prefix></CommonPrefixes>' newline ...
                '</ListBucketResult>'];
        end

        function xmlText = truncatedFirstPage(~)
            xmlText = [ ...
                '<?xml version="1.0" encoding="UTF-8"?>' newline ...
                '<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">' newline ...
                '<Prefix>root/</Prefix>' newline ...
                '<IsTruncated>true</IsTruncated>' newline ...
                '<NextContinuationToken>TOKEN-PAGE-2</NextContinuationToken>' newline ...
                '<CommonPrefixes><Prefix>root/child-a/</Prefix></CommonPrefixes>' newline ...
                '<CommonPrefixes><Prefix>root/child-b/</Prefix></CommonPrefixes>' newline ...
                '</ListBucketResult>'];
        end

        function xmlText = finalSecondPage(~)
            xmlText = [ ...
                '<?xml version="1.0" encoding="UTF-8"?>' newline ...
                '<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">' newline ...
                '<Prefix>root/</Prefix>' newline ...
                '<IsTruncated>false</IsTruncated>' newline ...
                '<CommonPrefixes><Prefix>root/child-c/</Prefix></CommonPrefixes>' newline ...
                '</ListBucketResult>'];
        end

        function xmlText = entityListing(~)
            xmlText = [ ...
                '<?xml version="1.0" encoding="UTF-8"?>' newline ...
                '<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">' newline ...
                '<Prefix>root/</Prefix>' newline ...
                '<IsTruncated>false</IsTruncated>' newline ...
                '<Contents><Key>root/x&lt;y&gt;.txt</Key></Contents>' newline ...
                '<CommonPrefixes><Prefix>root/a&amp;b/</Prefix></CommonPrefixes>' newline ...
                '</ListBucketResult>'];
        end
    end
end
