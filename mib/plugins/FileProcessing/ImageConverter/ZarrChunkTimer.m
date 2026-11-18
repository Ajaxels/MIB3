classdef ZarrChunkTimer < handle
    % ZARRCHUNKTIMER - Time Zarr chunk and shard sizes for browsing a dataset in MIB.
    %
    % Opened from Image converter (``ImageConverter.suggestZarrChunks``). It writes
    % a small test store for every candidate chunk/shard setting into a temporary
    % folder on the drive chosen by the user, reads it back the way the image
    % view of MIB does, and ranks the candidates. **Use selected** hands the chosen
    % chunk and shard back to the caller through ``applyFcn``.
    %
    % **Runs.** Every run gets its own tab (results table and bar plot), titled
    % with its number and test folder, so runs on different drives can be
    % compared side by side. The XY share and the files weight re-rank all runs;
    % Use selected and Remove run act on the shown tab.
    %
    % **Heat map.** ``timeGrid`` (button Heat map...) times, instead of the
    % candidates list, the power-of-2 grid of ``gridCandidates`` (chunk X = Y of
    % ``GridXY``, Z of ``GridZ``, shard options of ``ShardTargetBytes``) less the
    % unreasonable settings, after a dialog that explains the procedure and its
    % expected time. Its tab shows one heat map per shard option (chunk X = Y
    % across, Z up) of a value chosen in a dropdown or by clicking a table
    % column, and the suggestion of ``suggestFromGrid``. A cell or a row click
    % selects a setting for Use selected.
    %
    % **What is timed.** For each candidate the test volume is saved with
    % ``io.savers.Zarr3Saver.save`` (one level, the codec of the conversion) and
    % read with ``io.loaders.Zarr3VirtualLoader.readRegion`` through
    % ``io.zarr.ChunkCache``, the path of a BigData image. Three views of the size
    % of the image view of MIB are read at full resolution: XY (one slice), ZX
    % (one row, all test slices) and ZY (one column, all test slices). For each
    % view the first read after the cache was cleared (``first``) and the median
    % of three repeated reads (``warm``, served from the cache) are recorded.
    %
    % **Test volume.** ``testGeometry``: the view plus ``ViewMargin`` voxels on
    % every side in XY (so the view is not aligned to the chunk grid) and at most
    % ``MaxTestDepth`` slices, fewer when one test volume would exceed
    % ``MaxTestBytes`` (never fewer than 64, or the dataset depth). The data come
    % from up to ``SamplePlanes`` slices of the source cropped from its centre
    % (``readSamplePlanes``) or, without a source, from synthetic planes
    % (``syntheticPlanes``); ``buildTestVolume`` repeats them along Z, flipped in
    % four ways, and for images randomizes the lowest bit of every non-zero voxel,
    % so the repeats do not compress better than real data would. Each test store
    % is deleted right after it was read, the work folder at the end.
    %
    % **Scoring** (``rankCandidates``). Scrolling one slice in a view costs
    % ``warm + (first - warm) / depth``, where ``depth`` is the chunk size along
    % the scroll axis (Z for XY, Y for ZX, X for ZY): a chunk read once serves
    % ``depth`` slices, unless the chunks of one view do not fit in the chunk cache
    % budget, in which case ``depth = 1``. A browse is one jump plus
    % ``StepsPerJump`` scrolled slices, ``first + StepsPerJump * scroll``. The read
    % score is the browse time weighted by the XY share (the rest split equally
    % between ZX and ZY). The score is ``readScore / min(readScore) *
    % (files / min(files)) ^ filesWeight``, normalized to 1 for the best candidate;
    % ``files`` is the number of chunk or shard files of the whole dataset, all
    % pyramid levels and channel groups (``datasetFiles``).
    %
    % **Limits of the measurement.** The store is read right after it was written,
    % so the operating system may serve it from its file cache: the timings show
    % decoding, the per-chunk and per-file costs of MIB and zarrMex, and the
    % latency of opening files, rather than the throughput of the disk. Clearing
    % the chunk cache also drops the cached chunks of the datasets open in MIB;
    % they are read again when shown.
    %
    % Candidates are ``[N x 6]`` rows ``[chunkY chunkX chunkZ shardY shardX
    % shardZ]``, the shard as chunks per shard; ``[1 1 1]`` means no sharding. The
    % window shows them as X, Y, Z like Image converter.

    properties (Constant)
        StepsPerJump = 20       % slices scrolled per jump in the browse model
        ViewMargin = 128        % voxels around the view in XY in the test volume
        MaxTestDepth = 256      % slices of the test volume, at most
        MaxTestBytes = 2^30     % size of one test volume, at most (unless 64 slices need more)
        SamplePlanes = 16       % slices read from the source
        GridXY = 2 .^ (4:10)    % chunk X = Y of the heat map grid
        GridZ = 2 .^ (0:8)      % chunk Z of the heat map grid
        MinChunkBytes = 2^17    % smaller chunks are left out of the grid
        MaxChunkBytes = 2^24    % larger chunks are left out of the grid
        ShardTargetBytes = [0 2^26 2^29]    % shard options of the grid: none, about 64 MB, about 512 MB
        MemoryShare = 0.8       % share of the physical memory a conversion may use, for the grid
        DefaultSecondsPerGB = 10    % time estimate per GB of test store before a run measured it (local SSD: about 9)
    end

    properties
        settings
        % struct, see the constructor
        provider
        % io.savers.SliceProvider of the source, or []
        applyFcn
        % function handle, applyFcn(chunkYXZ, shardYXZ); shardYXZ = [] for no sharding
        runs = struct('tab', {}, 'table', {}, 'plot', {}, 'candidates', {}, 'timings', {}, ...
            'rankedOrder', {}, 'plotColumn', {}, 'selectedRow', {}, 'statusText', {}, ...
            'grid', {}, 'heatAxes', {}, 'metricDropdown', {}, 'suggestedCandidate', {}, 'suggestionLabel', {})
        % one per timing run, each shown in its own tab: the tab, its results
        % table and bar plot, the timed candidates ([N x 6]) and their timings
        % (from timeCandidate), the candidate index of each row of Data (rank
        % order), the column shown in the plot (4 = Score), the row of Data last
        % clicked (used by Use selected) and the text of the status line. A heat
        % map run (timeGrid) also has its grid (gridCandidates), one heat map
        % axes per shard option, the dropdown of the shown column, the suggested
        % candidate (suggestFromGrid) and its label; for a list run these are empty
        runCount = 0
        % runs made so far, numbers the tabs
        secondsPerGB = ZarrChunkTimer.DefaultSecondsPerGB
        % seconds per candidate and GB of test volume, measured by the last run; for the estimate of timeGrid
        figureHandle
        % uifigure of the window
        handles
        % struct with the widgets
    end

    methods
        function obj = ZarrChunkTimer(settings, provider, applyFcn)
            % ZARRCHUNKTIMER - Open the timing window.
            %
            % Input Arguments:
            %   - **settings** - struct:
            %
            %     - ``datasetSize`` - [H W D] of the dataset to convert
            %     - ``channels`` - number of color channels
            %     - ``chunkChannels`` - channels per chunk
            %     - ``dataClass`` - class of the voxels, e.g. ``'uint8'``
            %     - ``isLabels`` - true for a label model (values are not changed)
            %     - ``zarrFormat`` - 2 or 3; v2 has no sharding
            %     - ``compressors`` - codec for ``Zarr3Saver`` (name or struct)
            %     - ``pixSize`` - voxel size struct (``.x .y .z``), for the pyramid
            %     - ``levelOptions`` - ``MinLevelSize``, ``DownsampleStrategy`` for
            %       ``Zarr3Saver.computeLevelPlan``
            %     - ``testFolder`` - default folder for the test stores
            %     - ``viewSize`` - [width height] of the image view, pixels
            %     - ``currentChunk`` - [y x z] chunk set in the caller
            %     - ``currentShard`` - [y x z] chunks per shard, ``[]`` = none
            %     - ``sourceText`` - description of the source, shown at the top
            %     - ``parentFigure`` - figure to place the window next to, or ``[]``
            %     - ``font`` - MIB font struct (``FontName``, ``FontSize``), or ``[]``
            %     - ``numWorkers`` - *(optional)* processes of the conversion, for
            %       the memory limit of the heat map grid; default 1
            %   - **provider** - ``io.savers.SliceProvider`` of the source, or ``[]``
            %     for synthetic test data
            %   - **applyFcn** - ``applyFcn(chunkYXZ, shardYXZ)``, called by Use selected
            obj.settings = settings;
            obj.provider = provider;
            obj.applyFcn = applyFcn;
            obj.buildWindow();
        end

        function closeWindow(obj)
            % CLOSEWINDOW - Close the window.
            if ~isempty(obj.figureHandle) && isvalid(obj.figureHandle)
                delete(obj.figureHandle);
            end
        end

        function timeCandidates(obj)
            % TIMECANDIDATES - Time every candidate of the table and show the ranking.
            %
            % Cancel stops before the next candidate; nothing of the cancelled run
            % is shown and the previous results stay.
            [newCandidates, problem] = obj.readCandidateTable();
            if ~isempty(problem)
                uialert(obj.figureHandle, problem, 'Candidates', 'Icon', 'warning');
                return;
            end
            [geometry, testFolder] = obj.prepareTiming();
            if isempty(geometry); return; end
            obj.runTiming(newCandidates, geometry, testFolder, []);
        end

        function timeGrid(obj, confirmFirst)
            % TIMEGRID - Time the power-of-2 grid of chunk sizes and show it as heat maps.
            %
            % The grid (``gridCandidates``) is every chunk X = Y of ``GridXY`` and Z
            % of ``GridZ``, each with the shard options of ``ShardTargetBytes``,
            % less the settings out of the limits. Before timing, a dialog
            % explains the procedure and gives the number of settings and the
            % expected time (from the speed of the last run in this window, or
            % ``DefaultSecondsPerGB`` per GB of test store without one); No stops.
            %
            % Input Arguments:
            %   - **confirmFirst** - *(optional)* false skips the dialog (tests); default true
            if nargin < 2; confirmFirst = true; end
            [geometry, testFolder] = obj.prepareTiming();
            if isempty(geometry); return; end
            memoryBytes = ZarrChunkTimer.physicalMemoryBytes();
            [newCandidates, grid] = ZarrChunkTimer.gridCandidates(obj.settings, geometry, ...
                io.zarr.ChunkCache.stats().budgetBytes, memoryBytes);
            if isempty(newCandidates)
                uialert(obj.figureHandle, 'No chunk size of the grid is within the limits for this dataset.', ...
                    'Heat map', 'Icon', 'warning');
                return;
            end
            if confirmFirst
                testGB = prod(geometry.testSize) * ZarrChunkTimer.bytesOf(obj.settings.dataClass) / 1e9;
                minutes = ceil(size(newCandidates, 1) * testGB * obj.secondsPerGB / 60);
                answer = uiconfirm(obj.figureHandle, ZarrChunkTimer.gridDescription(grid, size(newCandidates, 1), ...
                    testGB, minutes, testFolder, memoryBytes), 'Heat map of chunk sizes', ...
                    'Options', {'Start', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 2, 'Icon', 'info');
                if ~strcmp(answer, 'Start'); return; end
            end
            obj.runTiming(newCandidates, geometry, testFolder, grid);
        end

        function updateResults(obj)
            % UPDATERESULTS - Rank the candidates of every run with the current weights.
            for runIndex = 1:numel(obj.runs)
                obj.updateRun(runIndex);
            end
        end

        function useSelected(obj)
            % USESELECTED - Hand the chunk and shard of the selected result of the shown run to the caller.
            runIndex = obj.shownRun();
            if isempty(runIndex)
                uialert(obj.figureHandle, 'Time the candidates first.', 'Nothing timed', 'Icon', 'info');
                return;
            end
            run = obj.runs(runIndex);
            % the row of Data last clicked (resultCellSelected), also when the table is shown sorted
            k = run.rankedOrder(run.selectedRow);
            shardYXZ = run.candidates(k, 4:6);
            if all(shardYXZ == 1); shardYXZ = []; end
            obj.applyFcn(run.candidates(k, 1:3), shardYXZ);
            obj.handles.status.Text = sprintf('Chunk %s, shard %s of %s copied to Image converter.', ...
                ZarrChunkTimer.xyzText(run.candidates(k, 1:3)), ZarrChunkTimer.xyzText(run.candidates(k, 4:6)), ...
                run.tab.Title);
        end
    end

    methods (Access = private)
        function [geometry, testFolder] = prepareTiming(obj)
            % PREPARETIMING - Check the view size and the test folder; the test geometry, [] after a warning.
            geometry = [];
            testFolder = obj.handles.testFolder.Value;
            viewSize = str2num(obj.handles.viewSize.Value); %#ok<ST2NM>
            if numel(viewSize) ~= 2 || any(viewSize < 16)
                uialert(obj.figureHandle, 'The view size needs two numbers, the width and the height in pixels, at least 16.', ...
                    'View size', 'Icon', 'warning');
                return;
            end
            if ~isfolder(testFolder)
                uialert(obj.figureHandle, sprintf('The test folder does not exist:\n%s', testFolder), ...
                    'Test folder', 'Icon', 'warning');
                return;
            end
            bytesPerValue = ZarrChunkTimer.bytesOf(obj.settings.dataClass);
            geometry = ZarrChunkTimer.testGeometry(obj.settings.datasetSize, round(viewSize([2 1])), bytesPerValue);
        end

        function runTiming(obj, newCandidates, geometry, testFolder, grid)
            % RUNTIMING - Time the candidates on one test volume and show them in a new run tab.
            %
            % ``grid`` is ``[]`` for the candidate list, or the grid of
            % ``gridCandidates`` for a heat map run. Cancel stops before the next
            % candidate; nothing of the cancelled run is shown and the previous
            % runs stay. The time per candidate and GB of test volume is kept for
            % the estimate of the next heat map.
            wb = uiprogressdlg(obj.figureHandle, 'Title', 'Zarr chunk timing', ...
                'Message', 'Preparing the test data...', 'Cancelable', 'on');
            closeDialog = onCleanup(@() delete(wb));
            newTimings = [];
            testGB = prod(geometry.testSize) * ZarrChunkTimer.bytesOf(obj.settings.dataClass) / 1e9;
            try
                planes = [];
                sampleText = 'synthetic data';
                if ~isempty(obj.provider)
                    wb.Message = 'Reading a sample of the source...';
                    [planes, cancelled] = ZarrChunkTimer.readSamplePlanes(obj.provider, geometry.testSize(1:2), ...
                        ZarrChunkTimer.SamplePlanes, wb);
                    if cancelled
                        obj.handles.status.Text = 'Cancelled, nothing was timed.';
                        return;
                    end
                    sampleText = sprintf('%d slices of the source', size(planes, 3));
                end
                if isempty(planes)
                    planes = ZarrChunkTimer.syntheticPlanes(geometry.testSize(1:2), ZarrChunkTimer.SamplePlanes, ...
                        obj.settings.dataClass, obj.settings.isLabels);
                end
                volume = ZarrChunkTimer.buildTestVolume(planes, geometry.testSize, obj.settings.isLabels);
                clear planes

                workFolder = tempname(testFolder);
                mkdir(workFolder);
                removeWork = onCleanup(@() removeFolder(workFolder));
                numCandidates = size(newCandidates, 1);
                runTimer = tic;
                for candidateIndex = 1:numCandidates
                    if wb.CancelRequested
                        obj.handles.status.Text = sprintf('Cancelled after %d of %d candidates, nothing was kept.', ...
                            candidateIndex - 1, numCandidates);
                        ZarrChunkTimer.clearChunkCache();
                        return;
                    end
                    timeLeftText = '';
                    if candidateIndex > 1
                        secondsLeft = toc(runTimer) / (candidateIndex - 1) * (numCandidates - candidateIndex + 1);
                        timeLeftText = sprintf('\nAbout %s left', ZarrChunkTimer.durationText(secondsLeft));
                    end
                    wb.Message = sprintf('Candidate %d of %d: chunk %s, shard %s%s', candidateIndex, numCandidates, ...
                        ZarrChunkTimer.xyzText(newCandidates(candidateIndex, 1:3)), ...
                        ZarrChunkTimer.xyzText(newCandidates(candidateIndex, 4:6)), timeLeftText);
                    wb.Value = (candidateIndex - 1) / numCandidates;
                    storePath = fullfile(workFolder, sprintf('candidate%d.zarr%d', candidateIndex, obj.settings.zarrFormat));
                    timing = ZarrChunkTimer.timeCandidate(volume, newCandidates(candidateIndex, :), storePath, ...
                        geometry, obj.settings.compressors, obj.settings.zarrFormat);
                    if isempty(newTimings); newTimings = timing; else; newTimings(candidateIndex) = timing; end %#ok<AGROW>
                end
                wb.Value = 1;
                obj.secondsPerGB = toc(runTimer) / numCandidates / max(testGB, eps);
            catch err
                ZarrChunkTimer.clearChunkCache();
                uialert(obj.figureHandle, sprintf('The timing failed:\n%s', err.message), 'Zarr chunk timing');
                obj.handles.status.Text = 'The timing failed, nothing was timed.';
                return;
            end
            ZarrChunkTimer.clearChunkCache();
            statusText = sprintf(['Test volume %d x %d x %d (X x Y x Z) from %s, view %d x %d; ' ...
                'the lowest score is the best.'], geometry.testSize([2 1 3]), sampleText, ...
                diff(geometry.cols) + 1, diff(geometry.rows) + 1);
            if ~isempty(grid)
                statusText = sprintf('Heat map of %d settings. %s', numCandidates, statusText);
            end
            obj.addRun(newCandidates, newTimings, testFolder, statusText, grid);
        end

        function addRun(obj, candidates, timings, testFolder, statusText, grid)
            % ADDRUN - Show the results of a new run in a new tab, which becomes the shown one.
            %
            % The tab is titled with the run number and the test folder (shortened);
            % its tooltip gives the whole folder and the time of the run. A list
            % run (``grid`` empty) shows its table over a bar plot; a heat map run
            % shows a row with the metric dropdown and the suggestion, one heat
            % map per shard option of ``grid`` and the table below.
            obj.runCount = obj.runCount + 1;
            folderText = testFolder;
            if numel(folderText) > 32; folderText = [folderText(1:3) '...' folderText(end-25:end)]; end
            runName = 'Run';
            if ~isempty(grid); runName = 'Heat map'; end
            tab = uitab(obj.handles.runTabs, 'Title', sprintf('%s %d: %s', runName, obj.runCount, folderText), ...
                'Tooltip', sprintf('%s, %s', testFolder, char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm'))));
            columnNames = {'Rank', 'Chunk', 'Shard factors', 'Score', ...
                'XY first, ms', 'XY scroll, ms', 'ZX first, ms', 'ZX scroll, ms', 'ZY first, ms', 'ZY scroll, ms', ...
                'Files', 'File, MB', 'Write, MB/s', 'Memory, GB'};
            plotAxes = [];
            heatAxes = [];
            metricDropdown = [];
            suggestionLabel = [];
            if isempty(grid)
                tabGrid = uigridlayout(tab, [2 1], 'RowHeight', {'1x', '1.2x'});
            else
                tabGrid = uigridlayout(tab, [3 1], 'RowHeight', {'fit', '2x', '1x'});
                controlGrid = uigridlayout(tabGrid, [1 3], 'ColumnWidth', {'fit', 'fit', '1x'}, 'Padding', [0 0 0 0]);
                uilabel(controlGrid, 'Text', 'Show:');
                metricDropdown = uidropdown(controlGrid, 'Items', columnNames(4:end), 'ItemsData', 4:numel(columnNames), ...
                    'Value', 4, 'Tooltip', 'Value shown in the heat maps; clicking a column of the table also selects it');
                suggestionLabel = uilabel(controlGrid, 'Text', '', 'WordWrap', 'on', 'FontWeight', 'bold');
                heatGrid = uigridlayout(tabGrid, [1 numel(grid.shardTargets)], 'Padding', [0 0 0 0]);
                for shardIndex = 1:numel(grid.shardTargets)
                    heatAxes = [heatAxes, uiaxes(heatGrid)]; %#ok<AGROW>
                    heatAxes(end).Toolbar.Visible = 'off';
                    disableDefaultInteractivity(heatAxes(end));
                end
            end
            resultTable = uitable(tabGrid, 'ColumnName', columnNames, ...
                'ColumnFormat', [{'numeric', 'char', 'char'}, repmat({'bank'}, 1, 7), {'numeric', 'bank', 'numeric', 'bank'}], ...
                'ColumnSortable', true, 'SelectionType', 'cell', 'Multiselect', 'off', 'RowName', {}, ...
                'CellSelectionCallback', @(source, event) obj.resultCellSelected(source, event), ...
                'Tooltip', ['Files: chunk or shard files of the whole dataset, all levels; File: average file size; ' ...
                'Memory: memory the conversion needs per process with whole slices']);
            if isempty(grid)
                plotAxes = uiaxes(tabGrid);
                plotAxes.Toolbar.Visible = 'off';
            end
            if isfield(obj.settings, 'font') && ~isempty(obj.settings.font)
                utils.fontSizeUpdate(tab, obj.settings.font);
            end
            obj.runs(end + 1) = struct('tab', tab, 'table', resultTable, 'plot', plotAxes, ...
                'candidates', candidates, 'timings', timings, 'rankedOrder', [], 'plotColumn', 4, ...
                'selectedRow', 1, 'statusText', statusText, 'grid', grid, 'heatAxes', heatAxes, ...
                'metricDropdown', metricDropdown, 'suggestedCandidate', [], 'suggestionLabel', suggestionLabel);
            if ~isempty(metricDropdown)
                metricDropdown.ValueChangedFcn = @(source, ~) obj.metricChanged(source);
            end
            obj.handles.runTabs.SelectedTab = tab;
            obj.handles.status.Text = statusText;
            obj.updateRun(numel(obj.runs));
        end

        function updateRun(obj, runIndex)
            % UPDATERUN - Rank the candidates of one run and fill its table and plot.
            run = obj.runs(runIndex);
            ranking = ZarrChunkTimer.rankCandidates(run.candidates, run.timings, obj.settings, ...
                obj.handles.xyShare.Value, obj.handles.filesWeight.Value, io.zarr.ChunkCache.stats().budgetBytes);
            % numbers, not text, so that a sorted column is in numeric order
            rows = cell(numel(ranking.order), 14);
            for rank = 1:numel(ranking.order)
                k = ranking.order(rank);
                timesMs = round(1000 * [ranking.first(k, 1), ranking.scroll(k, 1), ranking.first(k, 2), ...
                    ranking.scroll(k, 2), ranking.first(k, 3), ranking.scroll(k, 3)], 1);
                rows(rank, :) = [{rank, ZarrChunkTimer.xyzText(run.candidates(k, 1:3)), ...
                    ZarrChunkTimer.xyzText(run.candidates(k, 4:6)), round(ranking.score(k), 2)}, ...
                    num2cell(timesMs), {ranking.files(k), round(ranking.fileMB(k), 1), ...
                    round(ranking.writeMBps(k)), round(ranking.memoryGB(k), 1)}];
            end
            run.table.Data = rows;
            obj.runs(runIndex).rankedOrder = ranking.order;
            selectedRow = 1;
            if ~isempty(run.grid)
                % a heat map run starts on its suggestion
                [suggested, ownScore, neighbourScore] = ZarrChunkTimer.suggestFromGrid(run.grid, ranking.score);
                obj.runs(runIndex).suggestedCandidate = suggested;
                selectedRow = find(ranking.order == suggested, 1);
                run.suggestionLabel.Text = sprintf(['Suggested: chunk %s, shard %s; score %.2f, %.2f around it ' ...
                    '(dashed outline). Click a cell or a row to select another.'], ...
                    ZarrChunkTimer.xyzText(run.candidates(suggested, 1:3)), ...
                    ZarrChunkTimer.xyzText(run.candidates(suggested, 4:6)), ownScore, neighbourScore);
            end
            run.table.Selection = [selectedRow max(4, run.plotColumn)];
            obj.runs(runIndex).selectedRow = selectedRow;
            obj.plotResults(runIndex);
        end

        function resultCellSelected(obj, resultTable, event)
            % RESULTCELLSELECTED - Plot the column of the clicked cell, the candidate of its row highlighted.
            %
            % ``event.Indices`` are rows of ``Data``, also when the table is shown sorted.
            % In a heat map run a click in the Rank, Chunk or Shard column keeps
            % the value shown.
            if isempty(event.Indices); return; end
            runIndex = find(arrayfun(@(run) run.table == resultTable, obj.runs), 1);
            if isempty(runIndex); return; end
            obj.runs(runIndex).selectedRow = event.Indices(end, 1);
            column = event.Indices(end, 2);
            if isempty(obj.runs(runIndex).grid) || column >= 4
                obj.runs(runIndex).plotColumn = column;
            end
            if ~isempty(obj.runs(runIndex).metricDropdown)
                obj.runs(runIndex).metricDropdown.Value = max(4, obj.runs(runIndex).plotColumn);
            end
            obj.plotResults(runIndex);
        end

        function metricChanged(obj, metricDropdown)
            % METRICCHANGED - Show the value chosen in the dropdown of a heat map run.
            runIndex = find(arrayfun(@(run) isequal(run.metricDropdown, metricDropdown), obj.runs), 1);
            if isempty(runIndex); return; end
            obj.runs(runIndex).plotColumn = metricDropdown.Value;
            obj.plotResults(runIndex);
        end

        function heatMapClicked(obj, clickedAxes, shardIndex, event)
            % HEATMAPCLICKED - Select the candidate of the clicked heat map cell.
            %
            % The run is found by its axes, as runs before it may have been removed.
            runIndex = find(arrayfun(@(run) any(arrayfun(@(axesHandle) isequal(axesHandle, clickedAxes), ...
                run.heatAxes)), obj.runs), 1);
            if isempty(runIndex); return; end
            run = obj.runs(runIndex);
            xyIndex = round(event.IntersectionPoint(1));
            zIndex = round(event.IntersectionPoint(2));
            if xyIndex < 1 || zIndex < 1 || xyIndex > numel(run.grid.xyValues) || zIndex > numel(run.grid.zValues)
                return;
            end
            k = run.grid.candidateIndex(zIndex, xyIndex, shardIndex);
            if k == 0; return; end
            selectedRow = find(run.rankedOrder == k, 1);
            obj.runs(runIndex).selectedRow = selectedRow;
            run.table.Selection = [selectedRow max(4, run.plotColumn)];
            obj.plotResults(runIndex);
        end

        function plotResults(obj, runIndex)
            % PLOTRESULTS - Plot the plot column of one run for all its candidates.
            %
            % A list run gets a bar plot, the bars in rank order and the candidate
            % of the row last clicked highlighted; the Rank, Chunk and Shard
            % columns plot the score. A heat map run gets its heat maps
            % (``plotHeatMaps``).
            run = obj.runs(runIndex);
            if ~isempty(run.grid)
                obj.plotHeatMaps(runIndex);
                return;
            end
            axesHandle = run.plot;
            cla(axesHandle);
            data = run.table.Data;
            if isempty(data); return; end
            column = max(4, run.plotColumn);
            selectedRow = run.selectedRow;
            values = cell2mat(data(:, column));
            numCandidates = numel(values);
            bars = bar(axesHandle, values, 'FaceColor', 'flat');
            bars.CData = repmat([0.30 0.50 0.80], numCandidates, 1);
            bars.CData(selectedRow, :) = [0.90 0.50 0.10];
            axesHandle.XTick = 1:numCandidates;
            axesHandle.XTickLabel = cellstr(string(data(:, 2)) + " / " + string(data(:, 3)));
            axesHandle.XTickLabelRotation = 25;
            axesHandle.XLim = [0.4 numCandidates + 0.6];
            title(axesHandle, sprintf('%s; highlighted: chunk %s, shard %s', ...
                run.table.ColumnName{column}, data{selectedRow, 2}, data{selectedRow, 3}));
        end

        function plotHeatMaps(obj, runIndex)
            % PLOTHEATMAPS - One heat map per shard option of a heat map run.
            %
            % Across: chunk X = Y; up: chunk Z; the colour and the number in a cell
            % are the plot column of the table. All maps share the colour limits,
            % on a log scale when the values are positive and span more than a
            % factor 4; the best end of the scale is yellow (for Write, MB/s the
            % highest value, otherwise the lowest). Cells out of the limits of the
            % grid are grey with the reason. The selected candidate has a solid
            % orange outline, the suggestion a dashed black one; a click on a cell
            % selects its candidate (``heatMapClicked``).
            run = obj.runs(runIndex);
            grid = run.grid;
            data = run.table.Data;
            if isempty(data); return; end
            column = max(4, run.plotColumn);
            rowOfCandidate = zeros(1, size(run.candidates, 1));
            rowOfCandidate(run.rankedOrder) = 1:numel(run.rankedOrder);
            values = nan(size(grid.candidateIndex));
            isTimed = grid.candidateIndex > 0;
            values(isTimed) = cell2mat(data(rowOfCandidate(grid.candidateIndex(isTimed)), column));
            finiteValues = values(isfinite(values));
            if isempty(finiteValues); finiteValues = [0 1]; end
            colorLimits = [min(finiteValues) max(finiteValues)];
            if diff(colorLimits) == 0; colorLimits = colorLimits + [-0.5 0.5] * max(1, abs(colorLimits(1))); end
            useLog = colorLimits(1) > 0 && colorLimits(2) / colorLimits(1) > 4;
            colors = parula(256);
            if column ~= 13; colors = flipud(colors); end   % yellow = best
            selectedCandidate = run.rankedOrder(run.selectedRow);
            numXY = numel(grid.xyValues);
            numZ = numel(grid.zValues);
            for shardIndex = 1:numel(grid.shardTargets)
                axesHandle = run.heatAxes(shardIndex);
                cla(axesHandle);
                layer = values(:, :, shardIndex);
                heatImage = imagesc(axesHandle, 1:numXY, 1:numZ, layer);
                heatImage.AlphaData = double(isfinite(layer));
                heatImage.PickableParts = 'all';
                heatImage.ButtonDownFcn = @(~, event) obj.heatMapClicked(axesHandle, shardIndex, event);
                axesHandle.YDir = 'normal';
                axesHandle.Color = [0.88 0.88 0.88];
                axesHandle.XLim = [0.5 numXY + 0.5];
                axesHandle.YLim = [0.5 numZ + 0.5];
                axesHandle.XTick = 1:numXY;
                axesHandle.XTickLabel = string(grid.xyValues);
                axesHandle.YTick = 1:numZ;
                axesHandle.YTickLabel = string(grid.zValues);
                axesHandle.CLim = colorLimits;
                if useLog; axesHandle.ColorScale = 'log'; else; axesHandle.ColorScale = 'linear'; end
                colormap(axesHandle, colors);
                xlabel(axesHandle, 'Chunk X = Y');
                if shardIndex == 1; ylabel(axesHandle, 'Chunk Z'); end
                title(axesHandle, grid.shardNames{shardIndex});
                hold(axesHandle, 'on');
                for xyIndex = 1:numXY
                    for zIndex = 1:numZ
                        value = layer(zIndex, xyIndex);
                        if isfinite(value)
                            if useLog
                                position = log(value / colorLimits(1)) / log(colorLimits(2) / colorLimits(1));
                            else
                                position = (value - colorLimits(1)) / diff(colorLimits);
                            end
                            cellColor = colors(max(1, min(256, round(position * 255) + 1)), :);
                            textColor = [0 0 0];
                            if cellColor * [0.299; 0.587; 0.114] < 0.5; textColor = [1 1 1]; end
                            cellText = sprintf('%.3g', value);
                        else
                            reasonCode = grid.reason(zIndex, xyIndex, shardIndex);
                            if reasonCode == 0; continue; end
                            textColor = [0.45 0.45 0.45];
                            cellText = grid.reasonNames{reasonCode};
                        end
                        text(axesHandle, xyIndex, zIndex, cellText, 'HorizontalAlignment', 'center', ...
                            'FontSize', 8, 'Color', textColor, 'PickableParts', 'none', 'Clipping', 'on');
                    end
                end
                [zSuggested, xySuggested] = find(grid.candidateIndex(:, :, shardIndex) == run.suggestedCandidate);
                if ~isempty(zSuggested)
                    rectangle(axesHandle, 'Position', [xySuggested - 0.5, zSuggested - 0.5, 1, 1], ...
                        'EdgeColor', [0 0 0], 'LineStyle', '--', 'LineWidth', 1.5, 'PickableParts', 'none');
                end
                [zSelected, xySelected] = find(grid.candidateIndex(:, :, shardIndex) == selectedCandidate);
                if ~isempty(zSelected)
                    rectangle(axesHandle, 'Position', [xySelected - 0.45, zSelected - 0.45, 0.9, 0.9], ...
                        'EdgeColor', [0.90 0.50 0.10], 'LineWidth', 2.5, 'PickableParts', 'none');
                end
                hold(axesHandle, 'off');
            end
            colorbar(run.heatAxes(end));
        end

        function runIndex = shownRun(obj)
            % SHOWNRUN - Index of the run of the shown tab, [] without runs.
            runIndex = [];
            if isempty(obj.runs); return; end
            runIndex = find(arrayfun(@(run) run.tab == obj.handles.runTabs.SelectedTab, obj.runs), 1);
        end

        function runTabChanged(obj)
            % RUNTABCHANGED - Show the status line of the run of the selected tab.
            runIndex = obj.shownRun();
            if ~isempty(runIndex); obj.handles.status.Text = obj.runs(runIndex).statusText; end
        end

        function removeRun(obj)
            % REMOVERUN - Delete the shown run and its tab.
            runIndex = obj.shownRun();
            if isempty(runIndex); return; end
            delete(obj.runs(runIndex).tab);
            obj.runs(runIndex) = [];
            if isempty(obj.runs)
                obj.handles.status.Text = 'Press Time candidates to start.';
            else
                obj.runTabChanged();
            end
        end

        function buildWindow(obj)
            % BUILDWINDOW - Create the window and its widgets.
            figureSize = [1100 900];
            position = [100 100 figureSize];
            parentFigure = obj.settings.parentFigure;
            if ~isempty(parentFigure) && isvalid(parentFigure)
                parentPosition = parentFigure.Position;
                position(1:2) = max([20 40], parentPosition(1:2) + (parentPosition(3:4) - figureSize) / 2);
            end
            fig = uifigure('Name', 'Zarr chunk timing', 'Position', position, 'Visible', 'off');
            fig.CloseRequestFcn = @(~, ~) obj.closeWindow();
            obj.figureHandle = fig;
            mainGrid = uigridlayout(fig, [6 1], 'RowHeight', {'fit', 'fit', '1x', '3x', 'fit', 'fit'});

            obj.handles.source = uilabel(mainGrid, 'Text', obj.settings.sourceText, 'WordWrap', 'on');

            settingsGrid = uigridlayout(mainGrid, [5 3], 'ColumnWidth', {'fit', '1x', 'fit'}, ...
                'RowHeight', repmat({'fit'}, 1, 5), 'Padding', [0 0 0 0]);
            uilabel(settingsGrid, 'Text', 'Test folder:');
            obj.handles.testFolder = uieditfield(settingsGrid, 'Value', obj.settings.testFolder, ...
                'Tooltip', 'Folder on the drive that will hold the dataset; the test files are deleted afterwards');
            uibutton(settingsGrid, 'Text', '...', 'ButtonPushedFcn', @(~, ~) obj.selectTestFolder());
            uilabel(settingsGrid, 'Text', 'View size, px (X, Y):');
            obj.handles.viewSize = uieditfield(settingsGrid, 'Value', ...
                sprintf('%d, %d', round(obj.settings.viewSize)), ...
                'Tooltip', 'Size of the image view of MIB in screen pixels');
            obj.handles.viewSize.Layout.Column = [2 3];
            uilabel(settingsGrid, 'Text', 'Use case:');
            obj.handles.useCase = uidropdown(settingsGrid, ...
                'Items', {'2D: XY only', 'Hybrid: mostly XY, sometimes ZX/ZY', '3D: all directions'}, ...
                'ItemsData', [100 80 34], 'Value', 80, ...
                'Tooltip', 'Sets the XY share and fills the candidates for this use case', ...
                'ValueChangedFcn', @(~, ~) obj.useCaseChanged());
            obj.handles.useCase.Layout.Column = [2 3];
            uilabel(settingsGrid, 'Text', 'XY share, %:');
            obj.handles.xyShare = uispinner(settingsGrid, 'Limits', [0 100], 'Step', 5, 'Value', 80, ...
                'RoundFractionalValues', 'on', ...
                'Tooltip', 'Share of browsing done in XY; the rest is split between ZX and ZY', ...
                'ValueChangedFcn', @(~, ~) obj.updateResults());
            obj.handles.xyShare.Layout.Column = [2 3];
            uilabel(settingsGrid, 'Text', 'Files weight:');
            obj.handles.filesWeight = uispinner(settingsGrid, 'Limits', [0 2], 'Step', 0.1, 'Value', 0.3, ...
                'Tooltip', sprintf(['0 = ignore the number of files; 0.3 = 10 times more files count as 2 times slower; ' ...
                '1 = as 10 times slower']), ...
                'ValueChangedFcn', @(~, ~) obj.updateResults());
            obj.handles.filesWeight.Layout.Column = [2 3];

            candidatePanel = uipanel(mainGrid, 'Title', 'Candidates (X, Y, Z); shard factors 1, 1, 1 = no sharding');
            candidateGrid = uigridlayout(candidatePanel, [1 2], 'ColumnWidth', {'1x', 'fit'});
            obj.handles.candidates = uitable(candidateGrid, 'ColumnName', {'Chunk', 'Shard factors'}, ...
                'ColumnEditable', [true true], 'SelectionType', 'row', 'Multiselect', 'off');
            buttonGrid = uigridlayout(candidateGrid, [4 1], 'RowHeight', {'fit', 'fit', 'fit', '1x'}, 'Padding', [0 0 0 0]);
            uibutton(buttonGrid, 'Text', 'Add', 'ButtonPushedFcn', @(~, ~) obj.addCandidate());
            uibutton(buttonGrid, 'Text', 'Remove', 'ButtonPushedFcn', @(~, ~) obj.removeCandidate());
            uibutton(buttonGrid, 'Text', 'Defaults', 'Tooltip', 'Candidates of the selected use case', ...
                'ButtonPushedFcn', @(~, ~) obj.fillDefaultCandidates());

            resultPanel = uipanel(mainGrid, 'Title', ['Results, one tab per run: time to show a view after a jump ' ...
                '(first) and per scrolled slice; click a column header to sort, a cell to plot its column']);
            resultGrid = uigridlayout(resultPanel, [1 1], 'Padding', [0 0 0 0]);
            obj.handles.runTabs = uitabgroup(resultGrid, 'SelectionChangedFcn', @(~, ~) obj.runTabChanged());

            obj.handles.status = uilabel(mainGrid, 'Text', 'Press Time candidates to start.', 'WordWrap', 'on');

            bottomGrid = uigridlayout(mainGrid, [1 6], 'ColumnWidth', {'fit', '1x', 'fit', 'fit', 'fit', 'fit'}, ...
                'Padding', [0 0 0 0]);
            uibutton(bottomGrid, 'Text', 'Remove run', 'Tooltip', 'Remove the shown run and its tab', ...
                'ButtonPushedFcn', @(~, ~) obj.removeRun());
            uilabel(bottomGrid, 'Text', '');
            uibutton(bottomGrid, 'Text', 'Heat map...', 'Tooltip', ['Time all reasonable chunk sizes of a ' ...
                'power-of-2 grid and show them as heat maps; ignores the candidates list, takes several minutes'], ...
                'ButtonPushedFcn', @(~, ~) obj.timeGrid());
            uibutton(bottomGrid, 'Text', 'Time candidates', 'ButtonPushedFcn', @(~, ~) obj.timeCandidates());
            uibutton(bottomGrid, 'Text', 'Use selected', 'Tooltip', 'Copy the chunk and shard of the selected result to Image converter', ...
                'ButtonPushedFcn', @(~, ~) obj.useSelected());
            uibutton(bottomGrid, 'Text', 'Close', 'ButtonPushedFcn', @(~, ~) obj.closeWindow());

            datasetDepth = obj.settings.datasetSize(3);
            if datasetDepth < 16
                % no side views: a thin stack is browsed in XY only
                obj.handles.useCase.Value = 100;
                obj.handles.useCase.Enable = 'off';
                obj.handles.xyShare.Enable = 'off';
            end
            obj.handles.xyShare.Value = obj.handles.useCase.Value;
            obj.fillDefaultCandidates();
            if isfield(obj.settings, 'font') && ~isempty(obj.settings.font)
                utils.fontSizeUpdate(fig, obj.settings.font);
            end
            fig.Visible = 'on';
        end

        function selectTestFolder(obj)
            % SELECTTESTFOLDER - Choose the folder for the test stores.
            startFolder = obj.handles.testFolder.Value;
            if ~isfolder(startFolder); startFolder = pwd; end
            selected = uigetdir(startFolder, 'Folder on the drive of the dataset');
            figure(obj.figureHandle);
            if isequal(selected, 0); return; end
            obj.handles.testFolder.Value = selected;
        end

        function useCaseChanged(obj)
            % USECASECHANGED - Set the XY share and the candidates of the chosen use case.
            obj.handles.xyShare.Value = obj.handles.useCase.Value;
            obj.fillDefaultCandidates();
            obj.updateResults();
        end

        function fillDefaultCandidates(obj)
            % FILLDEFAULTCANDIDATES - Fill the table with the candidates of the use case and the current setting.
            defaults = ZarrChunkTimer.defaultCandidates(obj.handles.useCase.Value, obj.settings.datasetSize, ...
                obj.settings.zarrFormat);
            current = [obj.settings.currentChunk(:)', ones(1, 3)];
            if ~isempty(obj.settings.currentShard) && obj.settings.zarrFormat == 3
                current(4:6) = obj.settings.currentShard(:)';
            end
            current(1:3) = max(1, min(current(1:3), obj.settings.datasetSize));
            rows = unique([current; defaults], 'rows', 'stable');
            data = cell(size(rows, 1), 2);
            for k = 1:size(rows, 1)
                data{k, 1} = ZarrChunkTimer.xyzText(rows(k, 1:3));
                data{k, 2} = ZarrChunkTimer.xyzText(rows(k, 4:6));
            end
            obj.handles.candidates.Data = data;
        end

        function addCandidate(obj)
            % ADDCANDIDATE - Add a row to the candidates.
            obj.handles.candidates.Data(end + 1, :) = {'256, 256, 16', '1, 1, 1'};
        end

        function removeCandidate(obj)
            % REMOVECANDIDATE - Remove the selected candidate.
            selectedRow = obj.handles.candidates.Selection;
            if isempty(selectedRow); return; end
            obj.handles.candidates.Data(selectedRow(1), :) = [];
        end

        function [rows, problem] = readCandidateTable(obj)
            % READCANDIDATETABLE - The candidates of the table as [N x 6] [y x z] rows.
            data = obj.handles.candidates.Data;
            rows = zeros(size(data, 1), 6);
            problem = '';
            if isempty(data); problem = 'Add at least one candidate.'; return; end
            for k = 1:size(data, 1)
                chunkXYZ = str2num(data{k, 1}); %#ok<ST2NM>
                shardXYZ = str2num(data{k, 2}); %#ok<ST2NM>
                if isempty(shardXYZ); shardXYZ = [1 1 1]; end
                if numel(chunkXYZ) ~= 3 || numel(shardXYZ) ~= 3 || any([chunkXYZ shardXYZ] < 1) || ...
                        any(mod([chunkXYZ shardXYZ], 1) ~= 0)
                    problem = sprintf('Row %d: the chunk and the shard factors need three whole numbers each, 1 or more.', k);
                    return;
                end
                if obj.settings.zarrFormat == 2 && any(shardXYZ > 1)
                    problem = sprintf('Row %d: Zarr v2 has no sharding, set the shard factors to 1, 1, 1.', k);
                    return;
                end
                rows(k, :) = [chunkXYZ([2 1 3]), shardXYZ([2 1 3])];
            end
            rows(:, 1:3) = min(rows(:, 1:3), repmat(obj.settings.datasetSize, size(rows, 1), 1));
            rows = unique(rows, 'rows', 'stable');
        end
    end

    methods (Static)
        function candidates = defaultCandidates(xyShare, datasetSize, zarrFormat)
            % DEFAULTCANDIDATES - Candidate chunk/shard settings for a use case.
            %
            % ``xyShare`` of 90 or more gives the 2D list (chunks one or a few
            % slices deep, large XY shards), 40 or less the 3D list (cubes) and
            % anything between the hybrid list (Z of 4 to 64, shards one chunk deep:
            % a conversion holds whole slices of a shard depth per process, so large
            % slices need a small Z). Chunks are clipped to
            % ``datasetSize`` [H W D], a shard Z factor to the slices available;
            % for Zarr v2 every shard becomes ``[1 1 1]`` (no sharding). Duplicates
            % made by the clipping are removed.
            %
            % Output Arguments:
            %   - **candidates** - [N x 6] ``[chunkY chunkX chunkZ shardY shardX shardZ]``
            if xyShare >= 90
                candidates = [512 512 1 4 4 1; 256 256 1 8 8 1; 1024 1024 1 2 2 1; ...
                    256 256 4 8 8 1; 256 256 16 4 4 1; 512 512 1 1 1 1];
            elseif xyShare <= 40
                candidates = [64 64 64 8 8 4; 128 128 128 4 4 1; 128 128 128 4 4 2; ...
                    128 128 64 4 4 2; 256 256 64 2 2 1; 128 128 32 8 8 1];
            else
                % thin Z first: a conversion holds whole slices of a shard depth per
                % process, so large slices need a small Z
                candidates = [256 256 4 4 4 1; 512 512 4 4 4 1; 256 256 8 4 4 1; 128 128 8 8 8 1; ...
                    256 256 16 4 4 1; 128 128 16 8 8 1; 256 256 32 4 4 1; 128 128 32 8 8 1; ...
                    256 256 64 2 2 1; 128 128 64 4 4 1];
            end
            datasetSize = datasetSize(:)';
            candidates(:, 1:3) = min(candidates(:, 1:3), repmat(datasetSize, size(candidates, 1), 1));
            candidates(:, 6) = max(1, min(candidates(:, 6), floor(datasetSize(3) ./ candidates(:, 3))));
            if zarrFormat == 2; candidates(:, 4:6) = 1; end
            candidates = unique(candidates, 'rows', 'stable');
        end

        function geometry = testGeometry(datasetSize, viewYX, bytesPerValue)
            % TESTGEOMETRY - Size of the test volume and position of the three views in it.
            %
            % Input Arguments:
            %   - **datasetSize** - [H W D] of the dataset
            %   - **viewYX** - [rows columns] of the image view
            %   - **bytesPerValue** - bytes per voxel
            %
            % Output Arguments:
            %   - **geometry** - struct with ``testSize`` [H W D], ``rows`` and
            %     ``cols`` [first last] of the view, ``zView`` (slice of the XY view),
            %     ``yView`` (row of the ZX view), ``xView`` (column of the ZY view)
            %     and ``hasSideViews`` (at least 16 test slices). The views are a few
            %     voxels off the centre so that they are not aligned to chunks.
            datasetSize = datasetSize(:)';
            margin = ZarrChunkTimer.ViewMargin;
            viewRows = min(datasetSize(1), viewYX(1));
            viewCols = min(datasetSize(2), viewYX(2));
            testH = min(datasetSize(1), viewRows + 2 * margin);
            testW = min(datasetSize(2), viewCols + 2 * margin);
            offsetY = floor((testH - viewRows) / 2);
            offsetX = floor((testW - viewCols) / 2);
            planeBytes = testH * testW * bytesPerValue;
            testD = min([datasetSize(3), ZarrChunkTimer.MaxTestDepth, ...
                max(64, floor(ZarrChunkTimer.MaxTestBytes / planeBytes))]);
            geometry.testSize = [testH, testW, testD];
            geometry.rows = offsetY + [1 viewRows];
            geometry.cols = offsetX + [1 viewCols];
            geometry.zView = min(testD, floor(testD / 2) + 3);
            geometry.yView = offsetY + min(viewRows, floor(viewRows / 2) + 3);
            geometry.xView = offsetX + min(viewCols, floor(viewCols / 2) + 3);
            geometry.hasSideViews = testD >= 16;
        end

        function [planes, cancelled] = readSamplePlanes(provider, testHW, maxPlanes, wb)
            % READSAMPLEPLANES - Read up to ``maxPlanes`` slices of the source, cropped from their centre.
            %
            % Slices are spread evenly over the stack; for a source of volume files
            % they are consecutive slices from the middle, so that a single volume
            % is read. TIFF slices are read in rows when the provider can
            % (``SupportsRowReads``). Only the first channel is kept; logical data
            % becomes ``uint8``.
            %
            % Input Arguments:
            %   - **provider** - ``io.savers.SliceProvider``
            %   - **testHW** - [rows columns] to crop, at most the slice size
            %   - **maxPlanes** - slices to read, at most
            %   - **wb** - ``uiprogressdlg`` checked for cancel, or ``[]``
            %
            % Output Arguments:
            %   - **planes** - [rows columns n] of the source class
            %   - **cancelled** - true when ``wb`` was cancelled; ``planes`` is then empty
            cancelled = false;
            sourceSize = provider.OutputSize;
            depth = sourceSize(3);
            numPlanes = min(maxPlanes, depth);
            isVolumeSource = isprop(provider, 'LargestFileDepth') && provider.LargestFileDepth > 1;
            if isVolumeSource
                firstSlice = max(1, floor((depth - numPlanes) / 2) + 1);
                sliceList = firstSlice:firstSlice + numPlanes - 1;
            else
                sliceList = unique(round(linspace(1, depth, numPlanes)));
            end
            rowFirst = floor((sourceSize(1) - testHW(1)) / 2) + 1;
            colFirst = floor((sourceSize(2) - testHW(2)) / 2) + 1;
            rowRange = rowFirst:rowFirst + testHW(1) - 1;
            colRange = colFirst:colFirst + testHW(2) - 1;
            useRows = isprop(provider, 'SupportsRowReads') && provider.SupportsRowReads;
            outputClass = provider.DataClass;
            if strcmp(outputClass, 'logical'); outputClass = 'uint8'; end
            planes = zeros([testHW, numel(sliceList)], outputClass);
            for planeIndex = 1:numel(sliceList)
                if ~isempty(wb) && wb.CancelRequested
                    planes = [];
                    cancelled = true;
                    return;
                end
                if useRows
                    band = provider.getSliceRows(sliceList(planeIndex), rowRange(1), rowRange(end));
                else
                    slice = provider.getSlice(sliceList(planeIndex), 1);
                    band = slice(rowRange, :, :);
                end
                planes(:, :, planeIndex) = cast(band(:, colRange, 1), outputClass);
            end
        end

        function planes = syntheticPlanes(testHW, numPlanes, dataClass, isLabels)
            % SYNTHETICPLANES - Planes of smooth structure plus noise, or of labelled blobs.
            %
            % Images: a Gaussian-filtered random field (sigma 6) over the middle half
            % of the range, plus noise of 6% of the range. Labels: connected blobs of
            % the same field, numbered. Repeatable (a fixed seed of a local stream).
            stream = RandStream('twister', 'Seed', 1);
            planes = zeros([testHW, numPlanes], dataClass);
            if isinteger(planes); classMax = double(intmax(dataClass)); else; classMax = 1; end
            for planeIndex = 1:numPlanes
                structure = imgaussfilt(rand(stream, testHW), 6);
                structure = (structure - min(structure(:))) / max(eps, max(structure(:)) - min(structure(:)));
                if isLabels
                    objects = double(labelmatrix(bwconncomp(structure > 0.6)));
                    objects(objects > 0) = mod(objects(objects > 0) - 1, min(classMax, 1000)) + 1;
                    planes(:, :, planeIndex) = cast(objects, dataClass);
                else
                    value = 0.25 + 0.5 * structure + 0.06 * randn(stream, testHW);
                    planes(:, :, planeIndex) = cast(min(max(value, 0), 1) * classMax, dataClass);
                end
            end
        end

        function volume = buildTestVolume(planes, testSize, isLabels)
            % BUILDTESTVOLUME - Stack the sample planes to ``testSize`` [H W D].
            %
            % Plane ``z`` is sample ``mod(z - 1, n) + 1``, flipped left-right,
            % up-down or both on every next pass through the samples. For images of
            % an integer class the lowest bit of every non-zero voxel is randomized
            % (fixed seed), so a repeated plane is not an exact copy the codec could
            % match; zeros stay zeros. Labels are stacked unchanged.
            numPlanes = size(planes, 3);
            volume = zeros(testSize, 'like', planes);
            stream = RandStream('twister', 'Seed', 2);
            randomizeBit = ~isLabels && isinteger(planes);
            for z = 1:testSize(3)
                plane = planes(:, :, mod(z - 1, numPlanes) + 1);
                switch mod(floor((z - 1) / numPlanes), 4)
                    case 1; plane = fliplr(plane);
                    case 2; plane = flipud(plane);
                    case 3; plane = rot90(plane, 2);
                end
                if randomizeBit
                    isSignal = plane > 0;
                    plane(isSignal) = bitxor(plane(isSignal), cast(randi(stream, [0 1], nnz(isSignal), 1), class(plane)));
                end
                volume(:, :, z) = plane;
            end
        end

        function timing = timeCandidate(volume, candidate, storePath, geometry, compressors, zarrFormat)
            % TIMECANDIDATE - Write ``volume`` with one chunk/shard setting and time the three views.
            %
            % Input Arguments:
            %   - **volume** - [H W D] test volume (``geometry.testSize``)
            %   - **candidate** - [1 x 6] ``[chunkY chunkX chunkZ shardY shardX shardZ]``
            %   - **storePath** - path of the test store; deleted when done
            %   - **geometry** - from ``testGeometry``
            %   - **compressors** - codec for ``Zarr3Saver``
            %   - **zarrFormat** - 2 or 3
            %
            % Output Arguments:
            %   - **timing** - struct with ``writeSeconds``, ``rawBytes``,
            %     ``storeBytes`` (on disk), ``first`` and ``warm`` [XY ZX ZY] in
            %     seconds and ``viewChunkBytes`` [XY ZX ZY] (decoded bytes of the
            %     chunks a view touches); side views are ``NaN`` without
            %     ``geometry.hasSideViews``
            chunk = candidate(1:3);
            shardFactors = candidate(4:6);
            options = struct('Levels', 1, 'ChunkSize', chunk, 'Compressors', compressors, ...
                'ZarrFormat', zarrFormat, 'silent', true, 'reportDone', false);
            if any(shardFactors > 1); options.ShardSize = shardFactors; end
            metadata = struct('pixSize', struct('x', 1, 'y', 1, 'z', 1, 'units', 'um'));
            removeStore = onCleanup(@() removeFolder(storePath));
            saver = io.savers.Zarr3Saver();
            writeTimer = tic;
            saver.save(volume, metadata, storePath, options);
            timing.writeSeconds = toc(writeTimer);
            bytesPerValue = ZarrChunkTimer.bytesOf(class(volume));
            timing.rawBytes = numel(volume) * bytesPerValue;
            storeFiles = dir(fullfile(storePath, '**', '*'));
            storeFiles = storeFiles(~[storeFiles.isdir]);
            timing.storeBytes = sum([storeFiles.bytes]);

            dataClass = class(volume);
            testDepth = geometry.testSize(3);
            loader = io.loaders.Zarr3VirtualLoader(storePath, 'yxz');
            loader.readRegion('0', [1 1], [1 1], [1 1], [1 1], [1 1], dataClass);   % opens the array
            views = {geometry.rows, geometry.cols, [geometry.zView geometry.zView]; ...
                [geometry.yView geometry.yView], geometry.cols, [1 testDepth]; ...
                geometry.rows, [geometry.xView geometry.xView], [1 testDepth]};
            effectiveChunk = min(chunk, geometry.testSize);   % as the saver clamps it
            timing.first = nan(1, 3);
            timing.warm = nan(1, 3);
            timing.viewChunkBytes = nan(1, 3);
            for viewIndex = 1:3
                if viewIndex > 1 && ~geometry.hasSideViews; continue; end
                readView = @() loader.readRegion('0', views{viewIndex, :}, [1 1], [1 1], dataClass);
                ZarrChunkTimer.clearChunkCache();
                readTimer = tic;
                readView();
                timing.first(viewIndex) = toc(readTimer);
                warmTimes = zeros(1, 3);
                for repeat = 1:3
                    readTimer = tic;
                    readView();
                    warmTimes(repeat) = toc(readTimer);
                end
                timing.warm(viewIndex) = median(warmTimes);
                ranges = vertcat(views{viewIndex, :});
                chunksTouched = prod(floor((ranges(:, 2) - 1) ./ effectiveChunk(:)) - ...
                    floor((ranges(:, 1) - 1) ./ effectiveChunk(:)) + 1);
                timing.viewChunkBytes(viewIndex) = chunksTouched * prod(effectiveChunk) * bytesPerValue;
            end
            ZarrChunkTimer.clearChunkCache();
            loader = []; %#ok<NASGU> released before the store is deleted
            clear removeStore
        end

        function ranking = rankCandidates(candidates, timings, settings, xyShare, filesWeight, cacheBudgetBytes)
            % RANKCANDIDATES - Score the timed candidates; see the class help for the model.
            %
            % Input Arguments:
            %   - **candidates** - [N x 6], as timed
            %   - **timings** - [1 x N] struct array from ``timeCandidate``
            %   - **settings** - struct of the constructor (``datasetSize``,
            %     ``channels``, ``chunkChannels``, ``dataClass``, ``pixSize``,
            %     ``levelOptions``)
            %   - **xyShare** - percent of browsing in XY, 0-100
            %   - **filesWeight** - exponent of the file count ratio, 0 = ignore files
            %   - **cacheBudgetBytes** - budget of ``io.zarr.ChunkCache``
            %
            % Output Arguments:
            %   - **ranking** - struct with [N x 1] ``score`` (1 = best),
            %     ``readScore`` (seconds per browse), ``files``, ``fileMB``
            %     (average file at level 0, with the measured compression),
            %     ``writeMBps``, ``memoryGB`` (memory of a conversion with whole
            %     slices, per process: ``2.5 x writeDepth + 2`` slices) and [N x 3]
            %     ``first`` and ``scroll`` in seconds; ``order`` lists the
            %     candidates from the best
            numCandidates = size(candidates, 1);
            first = vertcat(timings.first);
            warm = vertcat(timings.warm);
            viewChunkBytes = vertcat(timings.viewChunkBytes);
            scrollDepth = candidates(:, [3 1 2]);   % XY scrolls along Z, ZX along Y, ZY along X
            scrollDepth(viewChunkBytes > cacheBudgetBytes) = 1;
            scroll = warm + max(0, first - warm) ./ scrollDepth;
            browse = first + ZarrChunkTimer.StepsPerJump * scroll;
            share = xyShare / 100;
            shares = [share, (1 - share) / 2, (1 - share) / 2];
            if any(isnan(first(:, 2:3)), 'all'); shares = [1 0 0]; end
            browse(isnan(browse)) = 0;
            readScore = browse * shares';

            datasetSize = settings.datasetSize(:)';
            bytesPerValue = ZarrChunkTimer.bytesOf(settings.dataClass);
            files = zeros(numCandidates, 1);
            fileVoxels = zeros(numCandidates, 1);
            for k = 1:numCandidates
                [files(k), fileVoxels(k)] = ZarrChunkTimer.datasetFiles(candidates(k, 1:3), candidates(k, 4:6), settings);
            end
            compression = [timings.rawBytes]' ./ max(1, [timings.storeBytes]');
            channelsPerChunk = min(settings.channels, max(1, settings.chunkChannels));
            ranking.fileMB = fileVoxels * bytesPerValue * channelsPerChunk ./ compression / 1e6;
            ranking.score = (readScore / min(readScore)) .* (files / min(files)) .^ filesWeight;
            ranking.score = ranking.score / min(ranking.score);
            [~, ranking.order] = sort(ranking.score);
            ranking.readScore = readScore;
            ranking.files = files;
            ranking.first = first;
            ranking.scroll = scroll;
            ranking.writeMBps = [timings.rawBytes]' / 1e6 ./ max(eps, [timings.writeSeconds]');
            writeDepth = min(datasetSize(3), candidates(:, 3) .* candidates(:, 6));
            ranking.memoryGB = (2.5 * writeDepth + 2) * datasetSize(1) * datasetSize(2) * ...
                settings.channels * bytesPerValue / 1e9;
        end

        function [files, level0FileVoxels] = datasetFiles(chunkYXZ, shardFactorsYXZ, settings)
            % DATASETFILES - Chunk or shard files of the whole dataset, all pyramid levels.
            %
            % The levels come from ``Zarr3Saver.computeLevelPlan`` with
            % ``settings.levelOptions``; on each level the chunk is clamped to the
            % level as the saver does, the shard is ``Zarr3Saver.computeShard`` of
            % it, and every group of ``chunkChannels`` channels has its own files.
            % Every chunk is counted, also those the writer may leave out as empty.
            %
            % Output Arguments:
            %   - **files** - number of files
            %   - **level0FileVoxels** - voxels of one file of level 0
            datasetSize = settings.datasetSize(:)';
            plan = io.savers.Zarr3Saver.computeLevelPlan(datasetSize(1), datasetSize(2), datasetSize(3), ...
                settings.pixSize, settings.levelOptions);
            channelGroups = ceil(settings.channels / max(1, settings.chunkChannels));
            files = 0;
            level0FileVoxels = 0;
            for level = 1:numel(plan)
                levelShape = [plan(level).Yl, plan(level).Xl, plan(level).Zl];
                fileShape = max(1, min(chunkYXZ(:)', levelShape));
                if any(shardFactorsYXZ > 1)
                    fileShape = io.savers.Zarr3Saver.computeShard(fileShape, shardFactorsYXZ, levelShape);
                end
                files = files + prod(ceil(levelShape ./ fileShape)) * channelGroups;
                if level == 1; level0FileVoxels = prod(min(fileShape, levelShape)); end
            end
        end

        function [candidates, grid] = gridCandidates(settings, geometry, cacheBudgetBytes, memoryBytes)
            % GRIDCANDIDATES - The power-of-2 grid of chunk sizes for the heat map, without the unreasonable ones.
            %
            % Every chunk ``[xy xy z]`` with ``xy`` of ``GridXY`` and ``z`` of
            % ``GridZ`` is tested against these limits, in this order; the first
            % one that fails is its reason (``grid.reason``, a code into
            % ``grid.reasonNames``):
            %
            %   1. ``size`` - the next smaller value already covers the dataset or
            %      the test volume (``xy / 2`` at least the larger of H and W, or
            %      ``z / 2`` at least the depth), so it would time the same chunk;
            %   2. ``small`` - the chunk (clipped to the dataset, all channels of a
            %      chunk) is smaller than ``MinChunkBytes``: the per-chunk cost of
            %      reading dominates;
            %   3. ``large`` - larger than ``MaxChunkBytes``: a view decodes far
            %      more than it shows;
            %   4. ``RAM`` - a conversion with ``settings.numWorkers`` processes,
            %      each holding ``2.5 z + 2`` whole slices (as ``rankCandidates``
            %      estimates its memory), needs more than ``MemoryShare`` of
            %      ``memoryBytes``; skipped when ``memoryBytes`` is 0;
            %   5. ``cache`` - the chunks under the XY view of ``geometry`` exceed
            %      ``cacheBudgetBytes``, so every scrolled slice would be read again.
            %
            % A chunk within the limits gets one candidate per shard option of
            % ``ShardTargetBytes`` (only the first, no sharding, for Zarr v2): no
            % shard, or a shard one chunk deep of ``f x f`` chunks, ``f`` the power
            % of 2 that brings the uncompressed shard closest to the target, at
            % most what covers the larger of H and W. When ``f`` is not larger than
            % that of the option before (1 for no sharding), the option would time
            % the same setting again and is left out with reason 6, ``-``.
            % Shards one chunk deep keep the memory of a conversion as low as the
            % chunk depth allows.
            %
            % Input Arguments:
            %   - **settings** - struct of the constructor (``datasetSize``,
            %     ``channels``, ``chunkChannels``, ``dataClass``, ``zarrFormat``,
            %     optional ``numWorkers``)
            %   - **geometry** - from ``testGeometry``
            %   - **cacheBudgetBytes** - budget of ``io.zarr.ChunkCache``
            %   - **memoryBytes** - physical memory, 0 = unknown
            %
            % Output Arguments:
            %   - **candidates** - [N x 6] ``[chunkY chunkX chunkZ shardY shardX shardZ]``,
            %     the chunk clipped to the dataset
            %   - **grid** - struct with ``xyValues``, ``zValues``, ``shardTargets``,
            %     ``shardNames``, ``candidateIndex`` [nZ x nXY x nShard] (row of
            %     ``candidates``, 0 = left out), ``reason`` (same size, 0 = timed),
            %     ``reasonNames``, ``maxDepth`` (deepest chunk the memory allows,
            %     ``Inf`` when not limited) and ``numWorkers`` (as used)
            datasetSize = settings.datasetSize(:)';
            bytesPerValue = ZarrChunkTimer.bytesOf(settings.dataClass);
            channelsPerChunk = min(settings.channels, max(1, settings.chunkChannels));
            numWorkers = 1;
            if isfield(settings, 'numWorkers') && ~isempty(settings.numWorkers)
                numWorkers = max(1, settings.numWorkers);
            end
            xyValues = ZarrChunkTimer.GridXY;
            zValues = ZarrChunkTimer.GridZ;
            shardTargets = ZarrChunkTimer.ShardTargetBytes;
            if settings.zarrFormat == 2; shardTargets = shardTargets(1); end
            numXY = numel(xyValues);
            numZ = numel(zValues);
            numShards = numel(shardTargets);

            limitXY = min(max(datasetSize(1:2)), max(geometry.testSize(1:2)));
            limitZ = min(datasetSize(3), geometry.testSize(3));
            sliceBytes = datasetSize(1) * datasetSize(2) * settings.channels * bytesPerValue;
            maxDepth = Inf;
            if memoryBytes > 0
                maxDepth = (ZarrChunkTimer.MemoryShare * memoryBytes / numWorkers / sliceBytes - 2) / 2.5;
            end
            maxShardFactorXY = @(xy) 2 ^ nextpow2(ceil(max(datasetSize(1:2)) / xy));

            candidates = zeros(numZ * numXY * numShards, 6);
            numCandidates = 0;
            candidateIndex = zeros(numZ, numXY, numShards);
            reason = zeros(numZ, numXY, numShards);
            for xyIndex = 1:numXY
                xy = xyValues(xyIndex);
                for zIndex = 1:numZ
                    z = zValues(zIndex);
                    chunkYXZ = min([xy xy z], datasetSize);
                    chunkBytes = prod(chunkYXZ) * bytesPerValue * channelsPerChunk;
                    viewChunks = prod(floor(([geometry.rows(2) geometry.cols(2)] - 1) ./ xy) - ...
                        floor(([geometry.rows(1) geometry.cols(1)] - 1) ./ xy) + 1);
                    if xy / 2 >= limitXY || z / 2 >= limitZ
                        reason(zIndex, xyIndex, :) = 1;
                    elseif chunkBytes < ZarrChunkTimer.MinChunkBytes
                        reason(zIndex, xyIndex, :) = 2;
                    elseif chunkBytes > ZarrChunkTimer.MaxChunkBytes
                        reason(zIndex, xyIndex, :) = 3;
                    elseif z > maxDepth
                        reason(zIndex, xyIndex, :) = 4;
                    elseif viewChunks * xy * xy * z * bytesPerValue > cacheBudgetBytes
                        reason(zIndex, xyIndex, :) = 5;
                    else
                        previousFactor = 1;
                        for shardIndex = 1:numShards
                            shardFactors = [1 1 1];
                            if shardTargets(shardIndex) > 0
                                factor = 2 ^ max(0, round(0.5 * log2(shardTargets(shardIndex) / chunkBytes)));
                                factor = min(factor, maxShardFactorXY(xy));
                                if factor <= previousFactor
                                    % the same shard as the option before (no sharding, or capped by the dataset)
                                    reason(zIndex, xyIndex, shardIndex) = 6;
                                    continue;
                                end
                                previousFactor = factor;
                                shardFactors = [factor factor 1];
                            end
                            numCandidates = numCandidates + 1;
                            candidates(numCandidates, :) = [chunkYXZ shardFactors];
                            candidateIndex(zIndex, xyIndex, shardIndex) = numCandidates;
                        end
                    end
                end
            end
            candidates = candidates(1:numCandidates, :);
            shardNames = cell(1, numShards);
            for shardIndex = 1:numShards
                if shardTargets(shardIndex) == 0
                    shardNames{shardIndex} = 'No shards';
                else
                    shardNames{shardIndex} = sprintf('Shards of about %d MB', round(shardTargets(shardIndex) / 2^20));
                end
            end
            grid = struct('xyValues', xyValues, 'zValues', zValues, 'shardTargets', shardTargets, ...
                'shardNames', {shardNames}, 'candidateIndex', candidateIndex, 'reason', reason, ...
                'reasonNames', {{'size', 'small', 'large', 'RAM', 'cache', '-'}}, 'maxDepth', maxDepth, ...
                'numWorkers', numWorkers);
        end

        function [suggested, ownScore, neighbourScore] = suggestFromGrid(grid, score)
            % SUGGESTFROMGRID - The best timed cell of the grid, judged with its neighbours.
            %
            % Timings of neighbouring settings differ by 10-20% between runs, so the
            % single lowest score is often noise. Each timed cell is rated
            % ``(own + mean of its timed neighbours) / 2``, the neighbours being
            % the cells one step along X = Y or Z in the same shard option; a cell
            % without timed neighbours is rated by its own score. The lowest
            % rating wins.
            %
            % Input Arguments:
            %   - **grid** - from ``gridCandidates``
            %   - **score** - [N x 1] score of each candidate (``rankCandidates``)
            %
            % Output Arguments:
            %   - **suggested** - row of the candidates
            %   - **ownScore** - its score
            %   - **neighbourScore** - mean score of its timed neighbours (its own
            %     score without any)
            [numZ, numXY, numShards] = size(grid.candidateIndex);
            bestRating = Inf;
            suggested = 0;
            ownScore = NaN;
            neighbourScore = NaN;
            steps = [-1 0; 1 0; 0 -1; 0 1];
            for shardIndex = 1:numShards
                for xyIndex = 1:numXY
                    for zIndex = 1:numZ
                        k = grid.candidateIndex(zIndex, xyIndex, shardIndex);
                        if k == 0; continue; end
                        neighbours = [];
                        for stepIndex = 1:4
                            zNext = zIndex + steps(stepIndex, 1);
                            xyNext = xyIndex + steps(stepIndex, 2);
                            if zNext < 1 || zNext > numZ || xyNext < 1 || xyNext > numXY; continue; end
                            kNext = grid.candidateIndex(zNext, xyNext, shardIndex);
                            if kNext > 0; neighbours(end + 1) = score(kNext); end %#ok<AGROW>
                        end
                        around = score(k);
                        if ~isempty(neighbours); around = mean(neighbours); end
                        rating = (score(k) + around) / 2;
                        if rating < bestRating
                            bestRating = rating;
                            suggested = k;
                            ownScore = score(k);
                            neighbourScore = around;
                        end
                    end
                end
            end
        end

        function message = gridDescription(grid, numCandidates, testGB, minutes, testFolder, memoryBytes)
            % GRIDDESCRIPTION - Text of the dialog shown before a heat map run.
            shardText = 'without shards';
            if numel(grid.shardTargets) > 1
                shardText = sprintf('without shards and with shards of about %s MB, one chunk deep', ...
                    strjoin(string(round(grid.shardTargets(2:end) / 2^20)), ' and '));
            end
            memoryText = '';
            if isfinite(grid.maxDepth) && memoryBytes > 0
                memoryText = sprintf(['chunks deeper than %d slices (RAM: the conversion needs whole slices of a ' ...
                    'chunk depth, here with %d process(es) on %d GB), '], max(0, floor(grid.maxDepth)), ...
                    grid.numWorkers, round(memoryBytes / 1e9));
            end
            message = sprintf(['The heat map times every chunk size of a power-of-2 grid: X = Y from %d to %d and ' ...
                'Z from %d to %d, each %s.\n\n' ...
                'Left out and shown grey with the reason: chunks smaller than %d KB (small) or larger than %d MB ' ...
                '(large), %schunks whose image view does not fit in the chunk cache (cache) and sizes beyond ' ...
                'the dataset (size).\n\n' ...
                '%d settings will be timed. Each writes a test store of %.2f GB to\n%s\nreads it back and ' ...
                'deletes it. This takes about %s, longer on a network drive. Cancel stops the run and keeps ' ...
                'nothing.\n\nThe result opens in a new tab with one heat map per shard option and the setting ' ...
                'it suggests: the best one whose neighbours are also good.'], ...
                grid.xyValues(1), grid.xyValues(end), grid.zValues(1), grid.zValues(end), shardText, ...
                ZarrChunkTimer.MinChunkBytes / 2^10, ZarrChunkTimer.MaxChunkBytes / 2^20, memoryText, ...
                numCandidates, testGB, testFolder, ZarrChunkTimer.durationText(60 * minutes));
        end

        function bytes = physicalMemoryBytes()
            % PHYSICALMEMORYBYTES - Physical memory of the computer, 0 when it cannot be read.
            bytes = 0;
            try
                [~, systemMemory] = memory();
                bytes = systemMemory.PhysicalMemory.Total;
            catch
            end
        end

        function text = durationText(seconds)
            % DURATIONTEXT - '45 s', '12 min' or '1.5 h'.
            if seconds < 90
                text = sprintf('%d s', round(seconds));
            elseif seconds < 90 * 60
                text = sprintf('%d min', round(seconds / 60));
            else
                text = sprintf('%.1f h', seconds / 3600);
            end
        end

        function clearChunkCache()
            % CLEARCHUNKCACHE - Empty ``io.zarr.ChunkCache`` and keep its budget.
            %
            % ``ChunkCache.clear`` resets the budget to its default, so the budget
            % set in the preferences is put back.
            budgetBytes = io.zarr.ChunkCache.stats().budgetBytes;
            io.zarr.ChunkCache.clear();
            io.zarr.ChunkCache.setBudgetMB(budgetBytes / 2^20);
        end

        function text = xyzText(valuesYXZ)
            % XYZTEXT - '[x, y, z]' text of a [y x z] vector.
            text = sprintf('%d, %d, %d', round(valuesYXZ([2 1 3])));
        end

        function bytes = bytesOf(dataClass)
            % BYTESOF - Bytes per value of a numeric or logical class.
            if strcmp(dataClass, 'logical'); bytes = 1; return; end
            bytes = numel(typecast(cast(0, dataClass), 'uint8'));
        end
    end
end

function removeFolder(folderPath)
% remove a test folder; a folder that cannot be removed is left
if isfolder(folderPath)
    try
        rmdir(folderPath, 's');
    catch
    end
end
end

