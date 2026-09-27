classdef ChunkCache
% CHUNKCACHE - In-memory LRU cache of decoded Zarr chunks.
%
% Sits between the virtual loaders and whichever engine actually fetches
% pixels, so a region already held in memory is served without touching the
% store. It works in Zarr's declared C-order index space and knows nothing
% about OME-Zarr, pyramids or MIB axis conventions, which is what lets the
% same instance serve both ``io.loaders.Zarr2VirtualLoader`` (zarr-python) and
% ``io.loaders.Zarr3VirtualLoader`` (native zarrMex).
%
% **Why this exists.** A chunk is the smallest unit a store will give you, and
% published OME-Zarr is routinely chunked for 3D block access rather than for
% browsing one plane at a time. The Janelia C. elegans volume uses
% ``[64, 128, 128]``: showing a single 1137x610 screenful at full resolution
% touches 60 chunks, and each of those carries **64 z-slices**. Without a cache
% that is ~50 MB fetched to display 0.7 MB - 1.1% useful - and stepping one
% slice re-fetches all of it, because the store has no idea it just sent you
% the neighbouring slice. Measured on that volume: reading 64 slices costs the
% same 2.6 s as reading 1, so every z-step inside a chunk block was being paid
% for 64 times over.
%
% **What is cached.** Whole chunks, decoded, keyed by array identity plus chunk
% index. The identity comes from :meth:`storeKey` - the level path plus the
% version of its metadata file - so a store rewritten at the same path starts cold
% instead of being assembled from the replaced store's chunks. Caching whole chunks rather than whole requests is what makes panning
% cheap: a viewport shifted by less than a chunk re-uses everything but the new
% edge. Chunks at the far edge of an array are stored at their true (clipped)
% size, not padded.
%
% **How misses are fetched.** All missing chunks of one request are fetched in a
% *single* call covering their bounding box, never one call per chunk. The
% engines fetch the chunks of one request concurrently, so one call for N chunks
% is far quicker than N calls for one chunk each - on the volume above, ~6x. The
% bounding box may pull in a few chunks that were already cached; they are
% cheap next to a second round trip, and they get refreshed rather than wasted.
%
% **Eviction** is least-recently-used against a byte budget
% (:meth:`setBudgetMB`, default 512 MB). The cache is process-wide and survives
% closing a dataset, so re-opening the same store is warm.
%
% **Example** - wrap an engine read:
%
%   .. code-block:: matlab
%
%      raw = io.zarr.ChunkCache.read(fullPath, bbox, meta.chunkShape, meta.shape, ...
%          @(alignedBbox) io.zarr.PyBackend.readArray(pyArray, alignedBbox, meta));

    methods (Static)
        function raw = read(cacheKey, bbox, chunkShape, arrayShape, readFcn)
            % READ - Serve a region from cached chunks, fetching only what is missing.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      raw = io.zarr.ChunkCache.read(cacheKey, bbox, chunkShape, arrayShape, readFcn)
            %
            % Input Arguments:
            %   - **cacheKey** - [char|string] identity of the array; use
            %     :meth:`storeKey` of the pyramid level path, so a store rewritten
            %     at the same path is not served from the old one's chunks
            %   - **bbox** - [nDims x 2] requested region in Zarr C-order, as
            %     ``[start_1based, end_exclusive]`` - the same form the loaders
            %     already build for the engines
            %   - **chunkShape** - [1 x nDims] chunk size of the array
            %   - **arrayShape** - [1 x nDims] full array shape
            %   - **readFcn** - [function_handle] ``readFcn(alignedBbox)`` fetching
            %     a chunk-aligned region from the engine, in the same bbox form
            %
            % Output Arguments:
            %   - **raw** - [numeric] the requested region, in Zarr C-order, exactly
            %     as ``readFcn`` would have returned it for ``bbox``

            if ~io.zarr.ChunkCache.isEnabled() || isempty(chunkShape) || ...
                    any(chunkShape <= 0) || numel(chunkShape) ~= size(bbox, 1)
                raw = readFcn(bbox);
                return;
            end

            nDims      = size(bbox, 1);
            chunkShape = double(chunkShape(:)');
            arrayShape = double(arrayShape(:)');

            % Chunk index range (0-based) spanned by the request. bbox(:,2) is
            % exclusive, so the last element addressed is bbox(:,2)-1.
            firstChunk = floor((bbox(:, 1)' - 1) ./ chunkShape);
            lastChunk  = floor((bbox(:, 2)' - 2) ./ chunkShape);

            chunkSubs  = io.zarr.ChunkCache.enumerateChunks(firstChunk, lastChunk);
            chunkCount = size(chunkSubs, 1);

            store = io.zarr.ChunkCache.storeAccess();
            keys  = strings(chunkCount, 1);
            found = false(chunkCount, 1);
            for chunkIdx = 1:chunkCount
                keys(chunkIdx)  = io.zarr.ChunkCache.chunkKey(cacheKey, chunkSubs(chunkIdx, :));
                found(chunkIdx) = isKey(store.entries, keys(chunkIdx));
            end

            if any(~found)
                % One fetch for every missing chunk, over their bounding box.
                missingSubs = chunkSubs(~found, :);
                fetchFirst  = min(missingSubs, [], 1);
                fetchLast   = max(missingSubs, [], 1);
                alignedBbox = [ (fetchFirst .* chunkShape + 1)', ...
                                min((fetchLast + 1) .* chunkShape, arrayShape)' + 1 ];

                fetched = readFcn(alignedBbox);
                store   = io.zarr.ChunkCache.splitAndStore(store, cacheKey, fetched, ...
                    alignedBbox, fetchFirst, fetchLast, chunkShape, arrayShape);
                store.misses = store.misses + sum(~found);
                store.hits   = store.hits + sum(found);
            else
                store.hits = store.hits + chunkCount;
            end

            [raw, store] = io.zarr.ChunkCache.assemble(store, keys, chunkSubs, ...
                bbox, chunkShape, nDims);
            store = io.zarr.ChunkCache.evict(store);
            io.zarr.ChunkCache.storeAccess(store);
        end

        function key = storeKey(arrayPath)
            % STOREKEY - Cache identity of one zarr array: its path plus a version of the store.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      key = io.zarr.ChunkCache.storeKey(arrayPath)
            %
            % The cache is process-wide and outlives the datasets that fill it, so a
            % key made of the path alone serves the chunks of a store that has since
            % been replaced at that path - e.g. exporting or converting to BigData
            % over a store opened earlier in the session. When the chunk layout
            % differs the old chunks are assembled into the wrong places and the
            % level shows mostly empty or scrambled tiles.
            %
            % A local array therefore also carries the modification time and size of
            % its metadata file (``zarr.json`` for v3, ``.zarray`` for v2), which every
            % writer rewrites when it creates the array. Only one ``dir`` call, so
            % callers compute it once per opened level, not per read. A remote array
            % (URL) keeps its bare path: a published store is not rewritten under a
            % reader, and probing it would cost a round trip.
            %
            % Input Arguments:
            %   - **arrayPath** - [char|string] full path or URL of the level array
            %
            % Output Arguments:
            %   - **key** - [string] ``arrayPath`` for a remote array or when no
            %     metadata file is found, otherwise ``"<path>@<datenum>:<bytes>"``
            key = string(arrayPath);
            if io.RemoteStore.isRemote(char(arrayPath)); return; end
            for metadataName = {'zarr.json', '.zarray'}
                listing = dir(fullfile(char(arrayPath), metadataName{1}));
                if ~isempty(listing)
                    key = key + "@" + sprintf('%.12g', listing(1).datenum) + ":" + listing(1).bytes;
                    return;
                end
            end
        end

        function clear()
            % CLEAR - Drop every cached chunk and reset the counters.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      io.zarr.ChunkCache.clear()

            io.zarr.ChunkCache.storeAccess(io.zarr.ChunkCache.emptyStore());
        end

        function info = stats()
            % STATS - Current cache occupancy and hit counters.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      info = io.zarr.ChunkCache.stats()
            %
            % Output Arguments:
            %   - **info** - [struct] with ``.chunkCount``, ``.bytes``, ``.budgetBytes``,
            %     ``.hits``, ``.misses``, ``.enabled``

            store = io.zarr.ChunkCache.storeAccess();
            info.chunkCount  = numEntries(store.entries);
            info.bytes       = store.bytes;
            info.budgetBytes = store.budgetBytes;
            info.hits        = store.hits;
            info.misses      = store.misses;
            info.enabled     = store.enabled;
        end

        function setBudgetMB(budgetMB)
            % SETBUDGETMB - Set the memory budget, evicting immediately if needed.
            %
            % A budget of 0 disables caching, which is the escape hatch for a
            % machine short of RAM and the way to measure the uncached cost.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      io.zarr.ChunkCache.setBudgetMB(512)
            %
            % Input Arguments:
            %   - **budgetMB** - [numeric] budget in megabytes

            store = io.zarr.ChunkCache.storeAccess();
            store.budgetBytes = max(0, double(budgetMB)) * 1024 * 1024;
            store.enabled     = store.budgetBytes > 0;
            store = io.zarr.ChunkCache.evict(store);
            io.zarr.ChunkCache.storeAccess(store);
        end

        function tf = isEnabled()
            % ISENABLED - True when chunks are being cached.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      tf = io.zarr.ChunkCache.isEnabled()

            store = io.zarr.ChunkCache.storeAccess();
            tf = store.enabled;
        end
    end

    methods (Static, Access = private)
        function store = storeAccess(newStore)
            % STOREACCESS - Get or replace the process-wide cache state.
            persistent cacheStore
            if nargin > 0
                cacheStore = newStore;
            elseif isempty(cacheStore)
                cacheStore = io.zarr.ChunkCache.emptyStore();
            end
            store = cacheStore;
        end

        function store = emptyStore()
            % EMPTYSTORE - A cache holding nothing, at the default budget.
            store.entries     = configureDictionary("string", "cell");
            store.lastUsed    = configureDictionary("string", "double");
            store.bytes       = 0;
            store.budgetBytes = 512 * 1024 * 1024;
            store.enabled     = true;
            store.clock       = 0;
            store.hits        = 0;
            store.misses      = 0;
        end

        function key = chunkKey(cacheKey, chunkSub)
            % CHUNKKEY - Identity of one chunk of one array.
            key = string(cacheKey) + "|" + strjoin(string(chunkSub), ",");
        end

        function subs = enumerateChunks(firstChunk, lastChunk)
            % ENUMERATECHUNKS - Every chunk index tuple in an inclusive range.
            %
            % Returns [nChunks x nDims] 0-based indices. ndgrid over a cell of
            % ranges keeps this dimension-agnostic, which matters because the
            % axis count varies with the OME-Zarr axis order (zyx, czyx, tczyx).
            nDims  = numel(firstChunk);
            ranges = arrayfun(@(dimIdx) firstChunk(dimIdx):lastChunk(dimIdx), ...
                1:nDims, 'UniformOutput', false);
            grids  = cell(1, nDims);
            [grids{:}] = ndgrid(ranges{:});
            subs = zeros(numel(grids{1}), nDims);
            for dimIdx = 1:nDims
                subs(:, dimIdx) = grids{dimIdx}(:);
            end
        end

        function store = splitAndStore(store, cacheKey, fetched, alignedBbox, ...
                fetchFirst, fetchLast, chunkShape, arrayShape)
            % SPLITANDSTORE - Cut a fetched aligned block into whole chunks.
            %
            % The block starts on a chunk boundary, so chunk k of dimension d
            % begins at a fixed offset inside it. Trailing chunks of the array
            % are stored clipped rather than padded, so a later assemble never
            % has to know whether it is at an edge.
            nDims = numel(chunkShape);
            subs  = io.zarr.ChunkCache.enumerateChunks(fetchFirst, fetchLast);
            blockOrigin = alignedBbox(:, 1)';

            for chunkIdx = 1:size(subs, 1)
                chunkSub    = subs(chunkIdx, :);
                chunkStart  = chunkSub .* chunkShape + 1;
                chunkEnd    = min((chunkSub + 1) .* chunkShape, arrayShape);
                localRanges = cell(1, nDims);
                for dimIdx = 1:nDims
                    localRanges{dimIdx} = (chunkStart(dimIdx) - blockOrigin(dimIdx) + 1): ...
                                          (chunkEnd(dimIdx)   - blockOrigin(dimIdx) + 1);
                end
                chunkData = subsref(fetched, substruct('()', localRanges));
                store = io.zarr.ChunkCache.put(store, ...
                    io.zarr.ChunkCache.chunkKey(cacheKey, chunkSub), chunkData);
            end
        end

        function store = put(store, key, chunkData)
            % PUT - Insert or replace a chunk, keeping the byte count honest.
            if isKey(store.entries, key)
                previous = store.entries{key};
                store.bytes = store.bytes - io.zarr.ChunkCache.byteSize(previous);
            end
            store.entries{key} = chunkData;
            store.bytes = store.bytes + io.zarr.ChunkCache.byteSize(chunkData);
            store.clock = store.clock + 1;
            store.lastUsed(key) = store.clock;
        end

        function [raw, store] = assemble(store, keys, chunkSubs, bbox, chunkShape, nDims)
            % ASSEMBLE - Build the requested region out of cached chunks.
            %
            % Copies each chunk's overlap with the request into the output. Also
            % refreshes the LRU stamps, so chunks that a request actually used
            % outlive chunks that were merely swept up by a bounding box.
            outputSize = (bbox(:, 2) - bbox(:, 1))';
            template   = store.entries{keys(1)};
            raw        = zeros(io.zarr.ChunkCache.sizeVector(outputSize), 'like', template);
            requestStart = bbox(:, 1)';
            requestEnd   = bbox(:, 2)' - 1;

            for chunkIdx = 1:size(chunkSubs, 1)
                key       = keys(chunkIdx);
                chunkData = store.entries{key};
                chunkSub  = chunkSubs(chunkIdx, :);
                chunkStart = chunkSub .* chunkShape + 1;

                sourceRanges = cell(1, nDims);
                targetRanges = cell(1, nDims);
                for dimIdx = 1:nDims
                    chunkExtent = size(chunkData, dimIdx);
                    overlapFrom = max(requestStart(dimIdx), chunkStart(dimIdx));
                    overlapTo   = min(requestEnd(dimIdx), chunkStart(dimIdx) + chunkExtent - 1);
                    sourceRanges{dimIdx} = (overlapFrom - chunkStart(dimIdx) + 1): ...
                                           (overlapTo   - chunkStart(dimIdx) + 1);
                    targetRanges{dimIdx} = (overlapFrom - requestStart(dimIdx) + 1): ...
                                           (overlapTo   - requestStart(dimIdx) + 1);
                end
                raw = subsasgn(raw, substruct('()', targetRanges), ...
                    subsref(chunkData, substruct('()', sourceRanges)));

                store.clock = store.clock + 1;
                store.lastUsed(key) = store.clock;
            end
        end

        function store = evict(store)
            % EVICT - Drop least-recently-used chunks until inside the budget.
            if store.bytes <= store.budgetBytes; return; end

            cacheKeys = keys(store.lastUsed);
            [~, order] = sort(values(store.lastUsed));   % oldest stamp first
            cacheKeys  = cacheKeys(order);

            evictIdx = 1;
            while store.bytes > store.budgetBytes && evictIdx <= numel(cacheKeys)
                victim = cacheKeys(evictIdx);
                if isKey(store.entries, victim)
                    store.bytes = store.bytes - io.zarr.ChunkCache.byteSize(store.entries{victim});
                    store.entries(victim)  = [];
                    store.lastUsed(victim) = [];
                end
                evictIdx = evictIdx + 1;
            end
        end

        function nBytes = byteSize(chunkData)
            % BYTESIZE - Bytes held by one cached chunk.
            %
            % Computed from the class rather than with ``whos``, which is far too
            % slow to call once per chunk on every read, and which the Code
            % Analyzer cannot see through because it names the variable in a string.
            persistent bytesPerElement
            if isempty(bytesPerElement)
                bytesPerElement = dictionary( ...
                    ["uint8", "int8", "logical", "char", "uint16", "int16", ...
                     "uint32", "int32", "single", "uint64", "int64", "double"], ...
                    [1, 1, 1, 2, 2, 2, 4, 4, 4, 8, 8, 8]);
            end
            elementClass = string(class(chunkData));
            if isKey(bytesPerElement, elementClass)
                nBytes = numel(chunkData) * bytesPerElement(elementClass);
            else
                nBytes = numel(chunkData) * 8;   % unknown class, assume the worst
            end
        end

        function sizeVec = sizeVector(outputSize)
            % SIZEVECTOR - zeros() needs at least two dimensions.
            sizeVec = outputSize;
            if numel(sizeVec) < 2; sizeVec = [sizeVec, 1]; end
        end
    end
end
