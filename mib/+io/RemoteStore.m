classdef RemoteStore
% REMOTESTORE - Helpers for object-store URLs (HTTP / HTTPS / Amazon S3).
%
% Pure URL and listing plumbing with no knowledge of Zarr or of any other
% format: it recognises the common S3 URL spellings, rewrites ``s3://`` into an
% anonymous HTTPS URL, lists the children of a "folder" through the S3
% ``ListObjectsV2`` REST API, and fetches small metadata files. Consumers are
% ``io.ExtensionRegistryLoad`` (probing a remote store for its zarr version),
% the OME-Zarr setup loaders, and ``controllers.SelectFromUrl``.
%
% **Why not s3fs / AWS credentials.** Public buckets answer ordinary anonymous
% HTTPS ``GET`` requests, and ``ListObjectsV2`` is likewise anonymous on a
% public bucket. Normalising ``s3://bucket/key`` to
% ``https://bucket.s3.amazonaws.com/key`` therefore removes any need for
% credentials, region configuration or an extra Python dependency. Private and
% requester-pays buckets are out of scope.
%
% **Listing needs the S3 REST API, not Amazon.** Any endpoint that answers
% ``ListObjectsV2`` can be browsed - MinIO and Ceph deployments do, which is how
% ``https://HOST/BUCKET/KEY`` works. A URL that matches none of the
% AWS spellings is read as path style and *tried*; a host that turns out not to
% speak the API simply returns no listing, and ``listChildren`` reports that as
% empty rather than as an error. Callers must degrade to asking the user for an
% explicit path rather than failing.
%
% **Example** - walk down to the image group of a Janelia OpenOrganelle store:
%
%   .. code-block:: matlab
%
%      root = 'https://janelia-cosem-datasets.s3.amazonaws.com/jrc_mus-liver-zon-1/jrc_mus-liver-zon-1.zarr';
%      [childUrls, childNames] = io.RemoteStore.listChildren(root);
%      % childNames -> {'recon-1'}
%      emGroup = io.RemoteStore.join(root, 'recon-1/em/fibsem-uint8');
%      attrs   = io.RemoteStore.readJson([emGroup '/.zattrs']);

    methods (Static)
        function tf = isRemote(path)
            % ISREMOTE - True when the path is an http, https or s3 URL.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      tf = io.RemoteStore.isRemote(path)
            %
            % Input Arguments:
            %   - **path** - [char|string] path or URL to test
            %
            % Output Arguments:
            %   - **tf** - [logical] true for a remote URL, false for a local path
            %     and for any empty or non-text input

            tf = false;
            if isempty(path); return; end
            if isstring(path) && ~isscalar(path); return; end
            if ~(ischar(path) || isstring(path)); return; end
            tf = startsWith(lower(strtrim(char(path))), {'http://', 'https://', 's3://'});
        end

        function url = normalise(path)
            % NORMALISE - Canonical HTTPS form of a store URL.
            %
            % Rewrites ``s3://bucket/key`` into ``https://bucket.s3.amazonaws.com/key``
            % so the rest of MIB only ever sees an anonymous HTTPS URL, and strips
            % any trailing slash so joins and prefix comparisons are stable.
            % Local paths are returned unchanged.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      url = io.RemoteStore.normalise(path)
            %
            % Input Arguments:
            %   - **path** - [char|string] path or URL
            %
            % Output Arguments:
            %   - **url** - [char] normalised URL, or the input path unchanged

            url = char(strtrim(string(path)));
            if isempty(url); return; end
            if ~io.RemoteStore.isRemote(url); return; end

            s3Tokens = regexp(url, '^[sS]3://([^/]+)/?(.*)$', 'tokens', 'once');
            if ~isempty(s3Tokens)
                bucket = s3Tokens{1};
                key    = s3Tokens{2};
                url    = ['https://', bucket, '.s3.amazonaws.com/', key];
            end

            while endsWith(url, '/'); url = url(1:end-1); end
        end

        function info = parse(path)
            % PARSE - Decompose a store URL into bucket, key and listing endpoint.
            %
            % Recognised spellings, tried in this order (regional forms first, as
            % they are the more specific match)::
            %
            %   s3://BUCKET/KEY
            %   https://BUCKET.s3.<region>.amazonaws.com/KEY     (also s3-<region>)
            %   https://BUCKET.s3.amazonaws.com/KEY
            %   https://s3.<region>.amazonaws.com/BUCKET/KEY     (also s3-<region>)
            %   https://s3.amazonaws.com/BUCKET/KEY
            %   https://storage.googleapis.com/BUCKET/KEY        (parsed, not listable)
            %   https://ANYHOST/BUCKET/KEY                       (assumed path style)
            %
            % The ``amazonaws.com`` patterns are here only to tell AWS's two
            % spellings apart - the bucket sits in the host in one and in the path
            % in the other. They are **not** what makes a store listable: any other
            % host falls through to the last rule and is read as path style, with
            % the endpoint taken from the URL itself. That is what reaches a MinIO
            % or Ceph deployment addressed as ``https://HOST/BUCKET/KEY``.
            %
            % Bucket names may contain dots, so the host patterns use a lazy
            % match up to the ``.s3`` label rather than "one label".
            %
            % Google Cloud Storage exposes only the marker-based v1 XML API, which
            % this class does not implement, so it is parsed but reported as not
            % listable, ahead of the generic rule.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      info = io.RemoteStore.parse(path)
            %
            % Input Arguments:
            %   - **path** - [char|string] path or URL
            %
            % Output Arguments:
            %   - **info** - [struct] with fields:
            %
            %     - ``.url`` - [char] normalised URL (see ``normalise``)
            %     - ``.bucket`` - [char] bucket name, ``''`` when not an object store
            %     - ``.key`` - [char] object key of the node, without a trailing slash
            %     - ``.region`` - [char] region when the URL carried one, else ``''``
            %     - ``.listEndpoint`` - [char] bucket root to issue ListObjectsV2
            %       against, including the trailing slash; ``''`` when not listable
            %     - ``.listable`` - [logical] whether ``listChildren`` may be tried
            %     - ``.flavour`` - [char] ``'s3'`` (an AWS spelling, known to list),
            %       ``'s3compatible'`` (assumed path style, listing unconfirmed),
            %       ``'gcs'``, ``'plain'`` or ``'local'``

            url = io.RemoteStore.normalise(path);

            info = struct('url', url, 'bucket', '', 'key', '', 'region', '', ...
                'listEndpoint', '', 'listable', false, 'flavour', 'local');

            if ~io.RemoteStore.isRemote(url); return; end
            info.flavour = 'plain';

            % --- virtual-host style with an explicit region -------------------
            tokens = regexp(url, '^https?://(.+?)\.s3[.-]([a-z0-9-]+)\.amazonaws\.com/?(.*)$', ...
                'tokens', 'once', 'ignorecase');
            if ~isempty(tokens)
                info.bucket = tokens{1};
                info.region = tokens{2};
                info.key    = io.RemoteStore.stripSlashes(tokens{3});
                info.listEndpoint = sprintf('https://%s.s3.%s.amazonaws.com/', info.bucket, info.region);
                info.listable = true;
                info.flavour  = 's3';
                return;
            end

            % --- virtual-host style, global endpoint --------------------------
            tokens = regexp(url, '^https?://(.+?)\.s3\.amazonaws\.com/?(.*)$', ...
                'tokens', 'once', 'ignorecase');
            if ~isempty(tokens)
                info.bucket = tokens{1};
                info.key    = io.RemoteStore.stripSlashes(tokens{2});
                info.listEndpoint = sprintf('https://%s.s3.amazonaws.com/', info.bucket);
                info.listable = true;
                info.flavour  = 's3';
                return;
            end

            % --- path style, with or without a region -------------------------
            tokens = regexp(url, '^https?://s3[.-]([a-z0-9-]+)\.amazonaws\.com/([^/]+)/?(.*)$', ...
                'tokens', 'once', 'ignorecase');
            if ~isempty(tokens)
                info.region = tokens{1};
                info.bucket = tokens{2};
                info.key    = io.RemoteStore.stripSlashes(tokens{3});
                info.listEndpoint = sprintf('https://s3.%s.amazonaws.com/%s/', info.region, info.bucket);
                info.listable = true;
                info.flavour  = 's3';
                return;
            end

            tokens = regexp(url, '^https?://s3\.amazonaws\.com/([^/]+)/?(.*)$', ...
                'tokens', 'once', 'ignorecase');
            if ~isempty(tokens)
                info.bucket = tokens{1};
                info.key    = io.RemoteStore.stripSlashes(tokens{2});
                info.listEndpoint = sprintf('https://s3.amazonaws.com/%s/', info.bucket);
                info.listable = true;
                info.flavour  = 's3';
                return;
            end

            % --- Google Cloud Storage: parsed, but the v1 API is not wired ----
            tokens = regexp(url, '^https?://storage\.googleapis\.com/([^/]+)/?(.*)$', ...
                'tokens', 'once', 'ignorecase');
            if ~isempty(tokens)
                info.bucket  = tokens{1};
                info.key     = io.RemoteStore.stripSlashes(tokens{2});
                info.flavour = 'gcs';
                return;
            end

            % --- any other host, read as path style and assumed listable ------
            % MinIO and Ceph installations serve the same ListObjectsV2 API from
            % their own domain, so the AWS host patterns above miss them - such a
            % store is addressed as https://HOST/BUCKET/KEY. There is
            % nothing in a URL that distinguishes such an endpoint from an
            % ordinary web server, so this is a guess, marked as one by its own
            % flavour. The cost of guessing wrong is a single request that returns
            % no listing, which every caller already treats as "cannot list".
            tokens = regexp(url, '^https?://([^/]+)/([^/]+)/?(.*)$', ...
                'tokens', 'once', 'ignorecase');
            if ~isempty(tokens)
                info.bucket = tokens{2};
                info.key    = io.RemoteStore.stripSlashes(tokens{3});
                info.listEndpoint = sprintf('https://%s/%s/', tokens{1}, info.bucket);
                info.listable = true;
                info.flavour  = 's3compatible';
            end
        end

        function [childUrls, childNames, fileNames] = listChildren(url, options)
            % LISTCHILDREN - Enumerate the immediate children of a store "folder".
            %
            % One ``ListObjectsV2`` request per call (plus one per extra page when
            % the result is truncated), issued anonymously with ``delimiter='/'``
            % so only the immediate level is returned. Results are memoised for
            % the session, so re-expanding a node in a browser costs nothing.
            %
            % Returns empty for a host that cannot be listed and for any network
            % or parse failure - it never throws, because the caller is expected
            % to degrade to manual path entry rather than abort.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [childUrls, childNames, fileNames] = io.RemoteStore.listChildren(url)
            %      [childUrls, childNames, fileNames] = io.RemoteStore.listChildren(url, options)
            %
            % Input Arguments:
            %   - **url** - [char|string] URL of the group / prefix to list
            %   - **options** - *(optional)* [struct] with optional fields:
            %
            %     - ``.timeout`` - [numeric] request timeout in seconds (default: 30)
            %     - ``.maxKeys`` - [numeric] keys per request (default: 1000)
            %     - ``.useCache`` - [logical] reuse the session cache (default: true)
            %     - ``.fetchFcn`` - [function_handle] listing fetcher, used by the
            %       tests to run offline; called as
            %       ``fetchFcn(listEndpoint, prefix, continuationToken, timeout, maxKeys)``
            %       and expected to return the response body as [char]
            %
            % Output Arguments:
            %   - **childUrls** - [1xN cell] full URLs of the child groups
            %   - **childNames** - [1xN cell] child group names, no trailing slash
            %   - **fileNames** - [1xM cell] names of the files directly in this node,
            %     e.g. ``{'.zattrs', '.zgroup'}``

            if nargin < 2 || isempty(options); options = struct(); end
            timeout  = io.RemoteStore.getOption(options, 'timeout', 30);
            maxKeys  = io.RemoteStore.getOption(options, 'maxKeys', 1000);
            useCache = io.RemoteStore.getOption(options, 'useCache', true);
            fetchFcn = io.RemoteStore.getOption(options, 'fetchFcn', @io.RemoteStore.fetchListing);

            childUrls = {}; childNames = {}; fileNames = {};

            info = io.RemoteStore.parse(url);
            if ~info.listable; return; end

            cacheKey = string(info.url);
            cache = io.RemoteStore.listingCache();
            if useCache && isKey(cache, cacheKey)
                cached     = cache{cacheKey};
                childUrls  = cached.childUrls;
                childNames = cached.childNames;
                fileNames  = cached.fileNames;
                return;
            end

            % The prefix always ends in '/' so S3 treats it as a folder. An empty
            % key means the bucket root, where the prefix must stay empty.
            if isempty(info.key); prefix = ''; else; prefix = [info.key, '/']; end

            continuationToken = '';
            prefixList = {};
            keyList    = {};
            try
                while true
                    xmlText = fetchFcn(info.listEndpoint, prefix, continuationToken, timeout, maxKeys);
                    if isempty(xmlText); return; end
                    [pagePrefixes, pageKeys, continuationToken] = io.RemoteStore.parseListing(xmlText);
                    prefixList = [prefixList, pagePrefixes]; %#ok<AGROW>
                    keyList    = [keyList, pageKeys];        %#ok<AGROW>
                    if isempty(continuationToken); break; end
                end
            catch
                % Access denied, a redirect that dropped the query, a non-XML body
                % from a proxy - all mean "cannot list", which is not an error.
                return;
            end

            childNames = io.RemoteStore.namesUnderPrefix(prefixList, prefix, true);
            fileNames  = io.RemoteStore.namesUnderPrefix(keyList, prefix, false);
            childUrls  = cellfun(@(name) io.RemoteStore.join(info.url, name), childNames, ...
                'UniformOutput', false);

            if useCache
                % Built field by field: struct('f', someCell) would expand into a
                % struct ARRAY the size of the cell instead of storing it.
                cacheEntry.childUrls  = childUrls;
                cacheEntry.childNames = childNames;
                cacheEntry.fileNames  = fileNames;
                cache{cacheKey} = cacheEntry;
                io.RemoteStore.listingCache(cache);
            end
        end

        function clearCache()
            % CLEARCACHE - Drop the memoised listings.
            %
            % Listings are cached for the whole MATLAB session, so a store that
            % changed on the server keeps showing its old contents until this is
            % called. Nothing else in MIB depends on the cache being warm.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      io.RemoteStore.clearCache()

            io.RemoteStore.listingCache(configureDictionary("string", "cell"));
        end

        function tf = exists(url)
            % EXISTS - True when a remote object can be fetched.
            %
            % Tries ``HEAD`` first and falls back to a one-byte ranged ``GET``,
            % because some object stores and CDNs reject ``HEAD``. Used to probe
            % for marker files such as ``zarr.json`` or ``.zgroup`` without
            % downloading anything meaningful.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      tf = io.RemoteStore.exists(url)
            %
            % Input Arguments:
            %   - **url** - [char|string] full URL of the object
            %
            % Output Arguments:
            %   - **tf** - [logical] true when the object responded; false on any
            %     error, timeout or non-success status

            tf = false;
            url = char(strtrim(string(url)));
            if isempty(url); return; end

            httpOptions = matlab.net.http.HTTPOptions('ConnectTimeout', 5, ...
                'ResponseTimeout', 10, 'ConvertResponse', false);

            try
                request  = matlab.net.http.RequestMessage(matlab.net.http.RequestMethod.HEAD);
                response = request.send(url, httpOptions);
                statusClass = floor(double(response.StatusCode) / 100);
                if statusClass == 2; tf = true; return; end

                % A clean 404/403 is a definitive answer - retrying it as a GET
                % would double the cost of every negative probe, and the group
                % walk issues a lot of those. Only retry when the server refused
                % the method itself.
                headRefused = ismember(double(response.StatusCode), [400 405 501]);
                if ~headRefused; tf = false; return; end
            catch
                headRefused = true;   % transport-level failure, worth one retry
            end

            if ~headRefused; return; end

            try
                header   = matlab.net.http.HeaderField('Range', 'bytes=0-0');
                request  = matlab.net.http.RequestMessage(matlab.net.http.RequestMethod.GET, header);
                response = request.send(url, httpOptions);
                tf = floor(double(response.StatusCode) / 100) == 2;
            catch
                tf = false;
            end
        end

        function data = readJson(url, timeoutSeconds)
            % READJSON - Fetch and decode a small JSON metadata file.
            %
            % Fetched as **text** and decoded here rather than asking webread for
            % JSON: object stores commonly serve ``.zattrs`` / ``.zgroup`` /
            % ``zarr.json`` as ``binary/octet-stream``, and a json-then-text
            % retry would make every miss cost two requests. The group walk
            % issues many misses, so one request per call matters.
            %
            % Returns ``[]`` rather than throwing when the file is absent, which is
            % the normal outcome when probing for a marker.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      data = io.RemoteStore.readJson(url)
            %      data = io.RemoteStore.readJson(url, timeoutSeconds)
            %
            % Input Arguments:
            %   - **url** - [char|string] full URL of the JSON file
            %   - **timeoutSeconds** - *(optional)* [numeric] request timeout (default: 15)
            %
            % Output Arguments:
            %   - **data** - [struct] decoded JSON, or ``[]`` when unavailable

            if nargin < 2 || isempty(timeoutSeconds); timeoutSeconds = 15; end
            url = char(strtrim(string(url)));

            try
                rawText = webread(url, weboptions('ContentType', 'text', 'Timeout', timeoutSeconds));
                data = jsondecode(char(rawText));
            catch
                data = [];
            end
        end

        function url = join(baseUrl, relativePath)
            % JOIN - Append a relative path to a URL with forward slashes.
            %
            % ``fullfile`` must never be used on a URL: on Windows it inserts a
            % backslash and turns ``https://host/group`` into ``https://host\group``.
            % An already absolute ``relativePath`` is returned normalised, so a
            % caller can accept either form from the user.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      url = io.RemoteStore.join(baseUrl, relativePath)
            %
            % Input Arguments:
            %   - **baseUrl** - [char|string] base URL
            %   - **relativePath** - [char|string] path relative to the base, or an
            %     absolute URL
            %
            % Output Arguments:
            %   - **url** - [char] joined URL, without a trailing slash

            baseUrl      = io.RemoteStore.normalise(baseUrl);
            relativePath = char(strtrim(string(relativePath)));

            if isempty(relativePath); url = baseUrl; return; end
            if io.RemoteStore.isRemote(relativePath)
                url = io.RemoteStore.normalise(relativePath);
                return;
            end

            relativePath = strrep(relativePath, '\', '/');
            relativePath = io.RemoteStore.stripSlashes(relativePath);
            if isempty(relativePath); url = baseUrl; return; end

            url = [baseUrl, '/', relativePath];
        end

        function relative = relativePath(rootUrl, url)
            % RELATIVEPATH - Path of a URL relative to a store root.
            %
            % Inverse of ``join``. When the URL does not sit under the root it is
            % returned unchanged, so the caller can pass it on as an absolute
            % location instead.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      relative = io.RemoteStore.relativePath(rootUrl, url)
            %
            % Input Arguments:
            %   - **rootUrl** - [char|string] store root URL
            %   - **url** - [char|string] URL at or below the root
            %
            % Output Arguments:
            %   - **relative** - [char] path relative to the root, ``''`` when the
            %     two are the same node

            rootUrl = io.RemoteStore.normalise(rootUrl);
            url     = io.RemoteStore.normalise(url);

            if strcmp(rootUrl, url); relative = ''; return; end

            if startsWith(url, [rootUrl, '/'])
                relative = url(numel(rootUrl)+2:end);
            else
                relative = url;
            end
        end
    end

    methods (Static, Access = private)
        function xmlText = fetchListing(listEndpoint, prefix, continuationToken, timeoutSeconds, maxKeys)
            % FETCHLISTING - One anonymous ListObjectsV2 request.
            %
            % The query values are passed to webread as name/value pairs so MATLAB
            % does the percent-encoding; S3 accepts its encoding of '/' as '%2F'.

            queryArgs = {'list-type', '2', 'delimiter', '/', ...
                'max-keys', num2str(maxKeys)};
            if ~isempty(prefix)
                queryArgs = [queryArgs, {'prefix', prefix}];
            end
            if ~isempty(continuationToken)
                queryArgs = [queryArgs, {'continuation-token', continuationToken}];
            end

            xmlText = webread(listEndpoint, queryArgs{:}, ...
                weboptions('ContentType', 'text', 'Timeout', timeoutSeconds));
            xmlText = char(xmlText);
        end

        function [commonPrefixes, keys, continuationToken] = parseListing(xmlText)
            % PARSELISTING - Extract child prefixes, keys and the next page token.
            %
            % Uses the DOM parser rather than regular expressions so that XML
            % entities in object names are unescaped for free. Child folders are
            % read from the ``CommonPrefixes`` elements, never from the bare
            % ``Prefix`` tag: the response echoes the request prefix under that
            % same tag name at the top level, which would otherwise be picked up
            % as a phantom child of itself.

            commonPrefixes    = {};
            keys              = {};
            continuationToken = '';

            document = matlab.io.xml.dom.Parser().parseString(xmlText);

            prefixParents = document.getElementsByTagName('CommonPrefixes');
            for elementIdx = 0:prefixParents.getLength-1
                prefixNodes = prefixParents.item(elementIdx).getElementsByTagName('Prefix');
                if prefixNodes.getLength > 0
                    commonPrefixes{end+1} = char(string(prefixNodes.item(0).getTextContent)); %#ok<AGROW>
                end
            end

            contentNodes = document.getElementsByTagName('Contents');
            for elementIdx = 0:contentNodes.getLength-1
                keyNodes = contentNodes.item(elementIdx).getElementsByTagName('Key');
                if keyNodes.getLength > 0
                    keys{end+1} = char(string(keyNodes.item(0).getTextContent)); %#ok<AGROW>
                end
            end

            truncatedNodes = document.getElementsByTagName('IsTruncated');
            if truncatedNodes.getLength > 0 && ...
                    strcmpi(strtrim(char(string(truncatedNodes.item(0).getTextContent))), 'true')
                tokenNodes = document.getElementsByTagName('NextContinuationToken');
                if tokenNodes.getLength > 0
                    continuationToken = char(string(tokenNodes.item(0).getTextContent));
                end
            end
        end

        function names = namesUnderPrefix(fullPaths, prefix, isFolder)
            % NAMESUNDERPREFIX - Reduce full object keys to immediate child names.
            %
            % Drops the shared prefix and, for folders, the trailing slash. Also
            % drops the prefix itself, which S3 returns as a zero-byte object when
            % the "folder" was created explicitly by some clients.

            names = {};
            for pathIdx = 1:numel(fullPaths)
                name = fullPaths{pathIdx};
                if ~isempty(prefix)
                    if ~startsWith(name, prefix); continue; end
                    name = name(numel(prefix)+1:end);
                end
                if isFolder
                    name = io.RemoteStore.stripSlashes(name);
                end
                if isempty(name); continue; end     % the prefix marker object
                names{end+1} = name; %#ok<AGROW>
            end
        end

        function text = stripSlashes(text)
            % STRIPSLASHES - Remove leading and trailing forward slashes.

            text = char(text);
            while ~isempty(text) && text(1) == '/';   text = text(2:end);   end
            while ~isempty(text) && text(end) == '/'; text = text(1:end-1); end
        end

        function value = getOption(options, fieldName, defaultValue)
            % GETOPTION - Read an optional struct field with a default.

            if isstruct(options) && isfield(options, fieldName) && ~isempty(options.(fieldName))
                value = options.(fieldName);
            else
                value = defaultValue;
            end
        end

        function cache = listingCache(newCache)
            % LISTINGCACHE - Session-persistent store of listing results.
            %
            % This caches directory listings only, never pixel chunks, so it does
            % not conflict with the deliberate decision not to cache chunk data.

            persistent cachedListings
            if isempty(cachedListings)
                cachedListings = configureDictionary("string", "cell");
            end
            if nargin > 0
                cachedListings = newCache;
            end
            cache = cachedListings;
        end
    end
end
