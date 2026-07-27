classdef StitchLayoutTest < matlab.unittest.TestCase
% STITCHLAYOUTTEST - Unit tests for utils.stitch layout builders and helpers.
%
% Covers:
%   utils.stitch.naturalSortFiles       — alphanumeric sort correctness
%   utils.stitch.buildLayoutGrid        — all four TileOrder modes, auto rows/cols
%   utils.stitch.buildLayoutPositionFile — space/tab/comma delimiters,
%                                          repeated spaces, Z column, relative paths
%   utils.stitch.buildLayoutFilenamePattern — _Z##-X##-Y## token parsing
%   utils.stitch.findNeighborPairs      — x/y/z directions, minOverlap filtering
%   utils.stitch.saveProject / loadProject — JSON round-trip

    methods (TestClassSetup)
        function addPaths(testCase)
            % Bootstrap: ensure tests/ is on the path before MibPathFixture is resolved.
            % The mcp__matlab__run_matlab_test_file tool does not pre-add tests/ to the path.
            testsFolder = fileparts(fileparts(mfilename('fullpath')));  % tests/utils/ -> tests/
            if ~any(strcmp(testsFolder, strsplit(path, pathsep)))
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testsFolder));
            end
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    % =====================================================================
    methods (Test, TestTags = {'Unit'})

        % -----------------------------------------------------------------
        % naturalSortFiles
        % -----------------------------------------------------------------

        function naturalSort_numbersBeforeAlpha(testCase)
            % 'tile2' must sort before 'tile10'
            input = {'tile10.tif', 'tile2.tif', 'tile1.tif'};
            sorted = utils.stitch.naturalSortFiles(input);
            testCase.verifyEqual(sorted{1}, 'tile1.tif');
            testCase.verifyEqual(sorted{2}, 'tile2.tif');
            testCase.verifyEqual(sorted{3}, 'tile10.tif');
        end

        function naturalSort_emptyInputReturnsEmpty(testCase)
            sorted = utils.stitch.naturalSortFiles({});
            testCase.verifyEmpty(sorted);
        end

        function naturalSort_singleElementUnchanged(testCase)
            input = {'only_tile.png'};
            sorted = utils.stitch.naturalSortFiles(input);
            testCase.verifyEqual(sorted, input);
        end

        % -----------------------------------------------------------------
        % buildLayoutGrid — origin formulas
        % -----------------------------------------------------------------

        function buildGrid_horizontal2x3_correctOrigins(testCase)
            % 2-row, 3-column Horizontal grid, no overlap
            tileFolder = testCase.makeSyntheticTiles(6, [40 60]);
            files = utils.stitch.naturalSortFiles(tileFolder.files);

            opts.rows      = 2;  opts.cols = 3;
            opts.tileOrder = 'Horizontal';
            opts.overlapX  = 0;  opts.overlapY = 0;
            layout = utils.stitch.buildLayoutGrid(files, opts);

            testCase.verifyEqual(numel(layout), 6);

            % Tile 1 → row 1 col 1
            testCase.verifyEqual(layout(1).gridRC, [1 1]);
            testCase.verifyEqual(layout(1).nomOrigin, [1 1 1]);
            % Tile 2 → row 1 col 2
            testCase.verifyEqual(layout(2).gridRC, [1 2]);
            testCase.verifyEqual(layout(2).nomOrigin(2), 1 + 60, 'AbsTol', 0.5);
            % Tile 4 → row 2 col 1
            testCase.verifyEqual(layout(4).gridRC, [2 1]);
            testCase.verifyEqual(layout(4).nomOrigin(1), 1 + 40, 'AbsTol', 0.5);
        end

        function buildGrid_folderTiles_carrySliceStack(testCase)
            % Each grid entry is a FOLDER holding a Z-stack; buildLayoutGrid must
            % record the folder as the tile, list its slices in .sliceFiles, and
            % set tileSize depth to the slice count — while arranging the folders
            % on the same XY grid as single-image tiles.
            tmpFixture = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            numSlices = 5;
            folderPaths = cell(1, 4);
            for tileIdx = 1:4
                folderPaths{tileIdx} = fullfile(tmpFixture.Folder, sprintf('tile_%02d', tileIdx));
                mkdir(folderPaths{tileIdx});
                for z = 1:numSlices
                    img = uint8(ones(40, 60, 'uint8') * 100 + tileIdx);
                    imwrite(img, fullfile(folderPaths{tileIdx}, sprintf('s%02d.png', z)));
                end
            end

            opts.rows = 2; opts.cols = 2;
            opts.tileOrder = 'Horizontal'; opts.overlapX = 0; opts.overlapY = 0;
            layout = utils.stitch.buildLayoutGrid(folderPaths, opts);

            testCase.verifyEqual(numel(layout), 4);
            testCase.verifyEqual(layout(1).tileSize, [40 60 numSlices 1]);
            testCase.verifyNumElements(layout(1).sliceFiles, numSlices);
            testCase.verifyEqual(layout(1).gridRC, [1 1]);
            testCase.verifyEqual(layout(4).gridRC, [2 2]);
            % Grid geometry identical to single-image tiles.
            testCase.verifyEqual(layout(2).nomOrigin(2), 1 + 60, 'AbsTol', 0.5);
            testCase.verifyEqual(layout(3).nomOrigin(1), 1 + 40, 'AbsTol', 0.5);
        end

        function buildGrid_horizontalSnake_rowsAlternate(testCase)
            % Snake: row 0 goes L→R, row 1 goes R→L
            tileFolder = testCase.makeSyntheticTiles(4, [40 60]);
            files = utils.stitch.naturalSortFiles(tileFolder.files);

            opts.rows = 2; opts.cols = 2;
            opts.tileOrder = 'Horizontal snake';
            opts.overlapX  = 0; opts.overlapY = 0;
            layout = utils.stitch.buildLayoutGrid(files, opts);

            % Tile 1 → (r=1,c=1); tile 2 → (r=1,c=2)
            testCase.verifyEqual(layout(1).gridRC, [1 1]);
            testCase.verifyEqual(layout(2).gridRC, [1 2]);
            % Tile 3 → (r=2,c=2) [reversed]; tile 4 → (r=2,c=1)
            testCase.verifyEqual(layout(3).gridRC, [2 2]);
            testCase.verifyEqual(layout(4).gridRC, [2 1]);
        end

        function buildGrid_vertical2x3_correctOrder(testCase)
            % Vertical: top-to-bottom first, then next column
            tileFolder = testCase.makeSyntheticTiles(6, [40 60]);
            files = utils.stitch.naturalSortFiles(tileFolder.files);

            opts.rows = 2; opts.cols = 3;
            opts.tileOrder = 'Vertical';
            opts.overlapX  = 0; opts.overlapY = 0;
            layout = utils.stitch.buildLayoutGrid(files, opts);

            % Tile 1 → (r=1,c=1); tile 2 → (r=2,c=1); tile 3 → (r=1,c=2)
            testCase.verifyEqual(layout(1).gridRC, [1 1]);
            testCase.verifyEqual(layout(2).gridRC, [2 1]);
            testCase.verifyEqual(layout(3).gridRC, [1 2]);
        end

        function buildGrid_verticalSnake_colsAlternate(testCase)
            % Snake vertical: col 0 top→bottom, col 1 bottom→top
            tileFolder = testCase.makeSyntheticTiles(4, [40 60]);
            files = utils.stitch.naturalSortFiles(tileFolder.files);

            opts.rows = 2; opts.cols = 2;
            opts.tileOrder = 'Vertical snake';
            opts.overlapX  = 0; opts.overlapY = 0;
            layout = utils.stitch.buildLayoutGrid(files, opts);

            % Tile 1 → (r=1,c=1); tile 2 → (r=2,c=1)
            testCase.verifyEqual(layout(1).gridRC, [1 1]);
            testCase.verifyEqual(layout(2).gridRC, [2 1]);
            % Tile 3 → (r=2,c=2) [reversed]; tile 4 → (r=1,c=2)
            testCase.verifyEqual(layout(3).gridRC, [2 2]);
            testCase.verifyEqual(layout(4).gridRC, [1 2]);
        end

        function buildGrid_autoRowsCols_nearSquare(testCase)
            % 9 tiles → 3x3 auto
            tileFolder = testCase.makeSyntheticTiles(9, [32 32]);
            files = utils.stitch.naturalSortFiles(tileFolder.files);

            opts.rows = 0; opts.cols = 0;
            opts.tileOrder = 'Horizontal';
            opts.overlapX  = 0; opts.overlapY = 0;
            layout = utils.stitch.buildLayoutGrid(files, opts);

            testCase.verifyEqual(numel(layout), 9);
            allRows = [layout.gridRC];
            allRows = allRows(1:2:end);  % odd indices = row
            testCase.verifyLessThanOrEqual(max(allRows), 3);
        end

        function buildGrid_autoRowsCols_exactFactorNoHoles(testCase)
            % Auto grid must tile the count EXACTLY (closest divisor pair to
            % square, rows <= cols): 3 tiles -> 1x3, NOT 2x2 with a hole —
            % a hole breaks the neighbour graph (phantom pairs measure
            % garbage, the real 2-3 neighbours are never paired).
            tileFolder = testCase.makeSyntheticTiles(3, [32 32]);
            files = utils.stitch.naturalSortFiles(tileFolder.files);

            opts.rows = 0; opts.cols = 0;
            opts.tileOrder = 'Horizontal';
            opts.overlapX  = 0; opts.overlapY = 0;
            layout = utils.stitch.buildLayoutGrid(files, opts);

            gridRC = reshape([layout.gridRC], 2, []).';
            testCase.verifyEqual(max(gridRC(:, 1)), 1, '3 tiles must form a single row');
            testCase.verifyEqual(sort(gridRC(:, 2)).', 1:3);

            % 12 tiles -> 3x4 (not ceil(sqrt) = 4x3 with ambiguity, and
            % never a holed grid).
            tileFolder12 = testCase.makeSyntheticTiles(12, [32 32]);
            files12 = utils.stitch.naturalSortFiles(tileFolder12.files);
            layout12 = utils.stitch.buildLayoutGrid(files12, opts);
            gridRC12 = reshape([layout12.gridRC], 2, []).';
            testCase.verifyEqual(max(gridRC12(:, 1)), 3);
            testCase.verifyEqual(max(gridRC12(:, 2)), 4);

            % The tile order states the preferred orientation: Vertical must
            % give the TALL arrangement (3 tiles -> 3x1, 12 -> 4x3).
            optsV = opts; optsV.tileOrder = 'Vertical';
            layoutV = utils.stitch.buildLayoutGrid(files, optsV);
            gridRCV = reshape([layoutV.gridRC], 2, []).';
            testCase.verifyEqual(max(gridRCV(:, 1)), 3, ...
                'Vertical order: 3 tiles must form a single column');
            testCase.verifyEqual(max(gridRCV(:, 2)), 1);

            layout12V = utils.stitch.buildLayoutGrid(files12, optsV);
            gridRC12V = reshape([layout12V.gridRC], 2, []).';
            testCase.verifyEqual(max(gridRC12V(:, 1)), 4);
            testCase.verifyEqual(max(gridRC12V(:, 2)), 3);
        end

        function buildGrid_withOverlap_reducedStep(testCase)
            % 10% overlap in X → step = 60 * 0.9 = 54
            tileFolder = testCase.makeSyntheticTiles(2, [40 60]);
            files = utils.stitch.naturalSortFiles(tileFolder.files);

            opts.rows = 1; opts.cols = 2;
            opts.tileOrder = 'Horizontal';
            opts.overlapX  = 10; opts.overlapY = 0;
            layout = utils.stitch.buildLayoutGrid(files, opts);

            expectedX2 = 1 + 60 * (1 - 10/100);
            testCase.verifyEqual(layout(2).nomOrigin(2), expectedX2, 'AbsTol', 0.01);
        end

        % -----------------------------------------------------------------
        % buildLayoutPositionFile
        % -----------------------------------------------------------------

        function positionFile_spaceDelimiter(testCase)
            tmpDir  = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tileFolder = testCase.makeSyntheticTiles(2, [32 32], tmpDir.Folder);

            posContent = sprintf('%s 0 0\n%s 32 0\n', ...
                tileFolder.files{1}, tileFolder.files{2});
            posFile = fullfile(tmpDir.Folder, 'pos_space.txt');
            fid = fopen(posFile, 'w'); fprintf(fid, '%s', posContent); fclose(fid);

            layout = utils.stitch.buildLayoutPositionFile(posFile);

            testCase.verifyEqual(numel(layout), 2);
            testCase.verifyEqual(layout(1).nomOrigin(2), 1);   % X=0 → 1-based
            testCase.verifyEqual(layout(2).nomOrigin(2), 33);  % X=32 → 33
        end

        function positionFile_tabDelimiter(testCase)
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tileFolder = testCase.makeSyntheticTiles(2, [32 32], tmpDir.Folder);

            posContent = sprintf('%s\t0\t0\n%s\t0\t32\n', ...
                tileFolder.files{1}, tileFolder.files{2});
            posFile = fullfile(tmpDir.Folder, 'pos_tab.txt');
            fid = fopen(posFile, 'w'); fprintf(fid, '%s', posContent); fclose(fid);

            layout = utils.stitch.buildLayoutPositionFile(posFile);

            testCase.verifyEqual(numel(layout), 2);
            testCase.verifyEqual(layout(2).nomOrigin(1), 33);  % Y=32 → 33
        end

        function positionFile_commaDelimiter(testCase)
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tileFolder = testCase.makeSyntheticTiles(2, [32 32], tmpDir.Folder);

            posContent = sprintf('%s,0,0\n%s,64,0\n', ...
                tileFolder.files{1}, tileFolder.files{2});
            posFile = fullfile(tmpDir.Folder, 'pos_comma.txt');
            fid = fopen(posFile, 'w'); fprintf(fid, '%s', posContent); fclose(fid);

            layout = utils.stitch.buildLayoutPositionFile(posFile);

            testCase.verifyEqual(layout(2).nomOrigin(2), 65);  % X=64 → 65
        end

        function positionFile_repeatedSpaces(testCase)
            % Multiple consecutive spaces must be treated as one delimiter
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tileFolder = testCase.makeSyntheticTiles(1, [32 32], tmpDir.Folder);

            posContent = sprintf('%s    0    0\n', tileFolder.files{1});
            posFile = fullfile(tmpDir.Folder, 'pos_spaces.txt');
            fid = fopen(posFile, 'w'); fprintf(fid, '%s', posContent); fclose(fid);

            layout = utils.stitch.buildLayoutPositionFile(posFile);

            testCase.verifyEqual(numel(layout), 1);
            testCase.verifyEqual(layout(1).nomOrigin(2), 1);
        end

        function positionFile_zColumnMapsToZLayer(testCase)
            % Z column: distinct Z values → zLayer 1, 2, 3 in ascending order
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tileFolder = testCase.makeSyntheticTiles(3, [32 32], tmpDir.Folder);

            posContent = sprintf('%s 0 0 100\n%s 0 0 200\n%s 0 0 50\n', ...
                tileFolder.files{1}, tileFolder.files{2}, tileFolder.files{3});
            posFile = fullfile(tmpDir.Folder, 'pos_z.txt');
            fid = fopen(posFile, 'w'); fprintf(fid, '%s', posContent); fclose(fid);

            layout = utils.stitch.buildLayoutPositionFile(posFile);

            % Z=50 → zLayer 1, Z=100 → zLayer 2, Z=200 → zLayer 3
            zLayers = [layout.zLayer];
            testCase.verifyEqual(zLayers(3), 1);  % file 3 has smallest Z
            testCase.verifyEqual(zLayers(1), 2);  % file 1 has middle Z
            testCase.verifyEqual(zLayers(2), 3);  % file 2 has largest Z
        end

        function positionFile_relativeFilenames(testCase)
            % Relative filenames in the file should be resolved relative to pos file folder
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tileFolder = testCase.makeSyntheticTiles(2, [32 32], tmpDir.Folder);

            % Write relative names (basename only)
            [~, name1, ext1] = fileparts(tileFolder.files{1});
            [~, name2, ext2] = fileparts(tileFolder.files{2});
            posContent = sprintf('%s 0 0\n%s 32 0\n', [name1 ext1], [name2 ext2]);
            posFile = fullfile(tmpDir.Folder, 'pos_rel.txt');
            fid = fopen(posFile, 'w'); fprintf(fid, '%s', posContent); fclose(fid);

            layout = utils.stitch.buildLayoutPositionFile(posFile);

            testCase.verifyEqual(numel(layout), 2);
            % Resolved filenames should be absolute
            testCase.verifyTrue(isfile(layout(1).filename) || ~isempty(layout(1).filename));
        end

        % -----------------------------------------------------------------
        % buildLayoutFilenamePattern
        % -----------------------------------------------------------------

        function filenamePattern_parsesZXY(testCase)
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            filenames = createChopFiles(tmpDir.Folder, [1 1 1; 1 2 1; 2 1 1; 2 2 1], [32 32]);

            layout = utils.stitch.buildLayoutFilenamePattern(filenames);

            testCase.verifyEqual(numel(layout), 4);
            % All zLayer values should be 1 or 2
            zLayers = sort(unique([layout.zLayer]));
            testCase.verifyEqual(zLayers, [1 2]);
        end

        function filenamePattern_abutOrigins(testCase)
            % Tiles abut: origin of (Y=2,X=1,Z=1) should be at (height+1, 1, 1)
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            filenames = createChopFiles(tmpDir.Folder, [1 1 1; 2 1 1], [32 48]);

            layout = utils.stitch.buildLayoutFilenamePattern(filenames);

            % Find the tile with Y=2
            for tileIdx = 1:numel(layout)
                if layout(tileIdx).gridRC(1) == 2
                    testCase.verifyEqual(layout(tileIdx).nomOrigin(1), 33);  % 32+1
                end
            end
        end

        function filenamePattern_overlapShrinksStep(testCase)
            % With overlapX/overlapY the XY step shrinks like the Grid source, so
            % overlapping pattern-named acquisitions get honest nominal positions.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            filenames = createChopFiles(tmpDir.Folder, [1 1 1; 1 2 1; 2 1 1; 2 2 1], [40 40]);

            layout = utils.stitch.buildLayoutFilenamePattern(filenames, ...
                struct('overlapX', 25, 'overlapY', 25));   % step = 40 * 0.75 = 30

            for tileIdx = 1:numel(layout)
                if isequal(layout(tileIdx).gridRC, [2 1])       % Y=2, X=1
                    testCase.verifyEqual(layout(tileIdx).nomOrigin(1), 31);   % (2-1)*30+1
                elseif isequal(layout(tileIdx).gridRC, [1 2])   % Y=1, X=2
                    testCase.verifyEqual(layout(tileIdx).nomOrigin(2), 31);
                end
            end
        end

        % -----------------------------------------------------------------
        % findNeighborPairs
        % -----------------------------------------------------------------

        function findPairs_2x2_findsXYPairs(testCase)
            % 2x2 grid with 20% overlap on 200x160 tiles.
            % X overlap = 0.2 * 160 = 32 px; Y overlap = 0.2 * 200 = 40 px → both > minOverlapPx=16.
            % Expected pairs: (1,2) x-direction, (1,3) y-direction, (2,4) y-direction, (3,4) x-direction = 4 pairs.
            tileFolder = testCase.makeSyntheticTiles(4, [200 160]);
            files = utils.stitch.naturalSortFiles(tileFolder.files);
            opts.rows = 2; opts.cols = 2;
            opts.tileOrder = 'Horizontal'; opts.overlapX = 20; opts.overlapY = 20;
            layout = utils.stitch.buildLayoutGrid(files, opts);

            pairs = utils.stitch.findNeighborPairs(layout);

            testCase.verifyGreaterThan(numel(pairs), 0);
            directions = {pairs.direction};
            testCase.verifyTrue(any(strcmp(directions, 'x')));
            testCase.verifyTrue(any(strcmp(directions, 'y')));
        end

        function findPairs_adjacentZLayers_findsZPairs(testCase)
            % Two tiles in different Z layers with same XY footprint → z pair
            layout = makeSimpleTwoLayerLayout([100 80]);
            pairs = utils.stitch.findNeighborPairs(layout);

            testCase.verifyEqual(numel(pairs), 1);
            testCase.verifyEqual(pairs(1).direction, 'z');
        end

        function findPairs_nonOverlapping_noPairs(testCase)
            % Tiles far apart → no pairs
            tileFolder = testCase.makeSyntheticTiles(2, [40 40]);
            files = utils.stitch.naturalSortFiles(tileFolder.files);
            opts.rows = 1; opts.cols = 2;
            opts.tileOrder = 'Horizontal'; opts.overlapX = 0; opts.overlapY = 0;
            layout = utils.stitch.buildLayoutGrid(files, opts);

            % Minimum overlap is 16px; abutting tiles have 0 overlap
            pairs = utils.stitch.findNeighborPairs(layout, struct('minOverlapPx', 16));

            testCase.verifyEqual(numel(pairs), 0);
        end

        function findPairs_nominalField_correct(testCase)
            % nominal = layout(j).nomOrigin - layout(i).nomOrigin.
            % Use 200x160 tiles with 20% overlap → X overlap = 32 px > minOverlapPx=16.
            tileFolder = testCase.makeSyntheticTiles(2, [200 160]);
            files = utils.stitch.naturalSortFiles(tileFolder.files);
            opts.rows = 1; opts.cols = 2;
            opts.tileOrder = 'Horizontal'; opts.overlapX = 20; opts.overlapY = 0;
            layout = utils.stitch.buildLayoutGrid(files, opts);

            pairs = utils.stitch.findNeighborPairs(layout);

            testCase.verifyEqual(numel(pairs), 1);
            expectedNominal = layout(pairs(1).j).nomOrigin - layout(pairs(1).i).nomOrigin;
            testCase.verifyEqual(pairs(1).nominal, expectedNominal, 'AbsTol', 1e-9);
        end

        % -----------------------------------------------------------------
        % saveProject / loadProject round-trip
        % -----------------------------------------------------------------

        function saveLoadProject_roundTrip(testCase)
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tileFolder = testCase.makeSyntheticTiles(4, [32 32], tmpDir.Folder);
            files = utils.stitch.naturalSortFiles(tileFolder.files);

            opts.rows = 2; opts.cols = 2;
            opts.tileOrder = 'Horizontal'; opts.overlapX = 10; opts.overlapY = 10;
            originalLayout = utils.stitch.buildLayoutGrid(files, opts);

            nomPairs = utils.stitch.findNeighborPairs(originalLayout);
            % Synthesise fake measured edges
            for edgeIdx = 1:numel(nomPairs)
                nomPairs(edgeIdx).measured = nomPairs(edgeIdx).nominal + [0.5, -0.3, 0];
                nomPairs(edgeIdx).quality  = 0.85;
                nomPairs(edgeIdx).valid    = true;
            end

            originalPositions = vertcat(originalLayout.nomOrigin);
            solverInfo  = struct('rmse', 1.23, 'iterations', 5);
            outputInfo  = struct('outputMode', 'In memory', 'blendMode', 'Feather');

            projectFile = fullfile(tmpDir.Folder, 'test_project.mibstitch.json');
            utils.stitch.saveProject(projectFile, originalLayout, nomPairs, ...
                originalPositions, solverInfo, outputInfo);

            testCase.verifyTrue(isfile(projectFile));

            [loadedLayout, loadedEdges, loadedPositions, loadedSolverInfo, loadedOutputInfo] = ...
                utils.stitch.loadProject(projectFile);

            % Verify tile count
            testCase.verifyEqual(numel(loadedLayout), numel(originalLayout));

            % Verify nomOrigin round-trip
            for tileIdx = 1:numel(originalLayout)
                testCase.verifyEqual(loadedLayout(tileIdx).nomOrigin, ...
                    originalLayout(tileIdx).nomOrigin, 'AbsTol', 1e-9);
            end

            % Verify positions round-trip
            testCase.verifyFalse(isempty(loadedPositions));
            testCase.verifyEqual(loadedPositions, originalPositions, 'AbsTol', 1e-9);

            % Verify edge count
            testCase.verifyEqual(numel(loadedEdges), numel(nomPairs));

            % Verify edge quality
            if numel(loadedEdges) > 0
                testCase.verifyEqual(loadedEdges(1).quality, 0.85, 'AbsTol', 1e-9);
            end

            % Verify solverInfo and outputInfo
            testCase.verifyEqual(loadedSolverInfo.rmse, 1.23, 'AbsTol', 1e-9);
            testCase.verifyEqual(loadedOutputInfo.outputMode, 'In memory');
        end

        function saveProject_extensionAutoAppended(testCase)
            % When filePath has no .mibstitch.json extension it is added automatically
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tileFolder = testCase.makeSyntheticTiles(1, [32 32], tmpDir.Folder);
            layout = utils.stitch.buildLayoutGrid(tileFolder.files, ...
                struct('rows', 1, 'cols', 1, 'tileOrder', 'Horizontal', 'overlapX', 0, 'overlapY', 0));

            projectFile = fullfile(tmpDir.Folder, 'myproject');  % no extension
            utils.stitch.saveProject(projectFile, layout, [], [], [], []);

            expectedFile = fullfile(tmpDir.Folder, 'myproject.mibstitch.json');
            testCase.verifyTrue(isfile(expectedFile));
        end

        function saveLoadProject_settingsBlockRoundTrip(testCase)
            % Schema v3 carries the tool's own parameters alongside the stitch
            % state, so "Load project" can reset the dialog to the saved values
            % or reuse them on a different set of tiles.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tileFolder = testCase.makeSyntheticTiles(2, [32 32], tmpDir.Folder);
            layout = utils.stitch.buildLayoutGrid(tileFolder.files, ...
                struct('rows', 1, 'cols', 2, 'tileOrder', 'Horizontal', 'overlapX', 10, 'overlapY', 10));

            settings = struct( ...
                'LayoutSource',    'Filename pattern', ...
                'InputPath',       fullfile(tmpDir.Folder, 'tiles'), ...
                'SubfolderMode',   true, ...
                'GridRows',        3, ...
                'OverlapX',        22, ...
                'EstimateOverlap', false, ...
                'TransformType',   'Affine', ...
                'BlendMode',       'Max');
            % Nested feature-detector tuning, incl. a vector parameter
            settings.FeatureOptions = struct( ...
                'imgDownsamplingFactorForAnalysis', 2, ...
                'detectMSERFeatures', struct('RegionAreaRange', [30 14000]));

            projectFile = fullfile(tmpDir.Folder, 'with_settings.mibstitch.json');
            utils.stitch.saveProject(projectFile, layout, [], [], [], [], {}, [], settings);

            [~, ~, ~, ~, ~, ~, ~, loadedSettings] = utils.stitch.loadProject(projectFile);

            testCase.verifyEqual(loadedSettings.LayoutSource, 'Filename pattern');
            testCase.verifyEqual(loadedSettings.InputPath, settings.InputPath);
            testCase.verifyTrue(loadedSettings.SubfolderMode);
            testCase.verifyEqual(loadedSettings.GridRows, 3, 'AbsTol', 1e-9);
            testCase.verifyEqual(loadedSettings.OverlapX, 22, 'AbsTol', 1e-9);
            testCase.verifyFalse(loadedSettings.EstimateOverlap);
            testCase.verifyEqual(loadedSettings.TransformType, 'Affine');
            testCase.verifyEqual(loadedSettings.BlendMode, 'Max');
            testCase.verifyEqual(loadedSettings.FeatureOptions.imgDownsamplingFactorForAnalysis, ...
                2, 'AbsTol', 1e-9);
            % jsondecode returns arrays as columns — the controller reshapes them
            % back to rows; here just check the values survived.
            testCase.verifyEqual(sort(loadedSettings.FeatureOptions.detectMSERFeatures.RegionAreaRange(:))', ...
                [30 14000], 'AbsTol', 1e-9);

            % A project saved WITHOUT settings (older schema) still loads, and
            % reports an empty settings struct so the caller skips the dialog.
            plainFile = fullfile(tmpDir.Folder, 'no_settings.mibstitch.json');
            utils.stitch.saveProject(plainFile, layout, [], [], [], []);
            [~, ~, ~, ~, ~, ~, ~, emptySettings] = utils.stitch.loadProject(plainFile);
            testCase.verifyEmpty(fieldnames(emptySettings));
        end

    end % methods (Test)

    % =====================================================================
    methods (Access = private)

        function tileData = makeSyntheticTiles(testCase, numTiles, tileSize, folderPath)
            % Create synthetic PNG tiles in a temp folder (or provided folder).
            % Returns struct with .folder and .files (cell array of full paths).
            if nargin < 4 || isempty(folderPath)
                tmpFixture = testCase.applyFixture( ...
                    matlab.unittest.fixtures.TemporaryFolderFixture);
                folderPath = tmpFixture.Folder;
            end

            tileHeight = tileSize(1);
            tileWidth  = tileSize(2);
            files = cell(numTiles, 1);

            for tileIdx = 1:numTiles
                tileImage = uint8(ones(tileHeight, tileWidth, 'uint8') * 128);
                % Add unique pixel so tiles are distinguishable
                tileImage(1, 1) = uint8(tileIdx);
                filename = fullfile(folderPath, sprintf('tile%02d.png', tileIdx));
                imwrite(tileImage, filename);
                files{tileIdx} = filename;
            end

            tileData.folder = folderPath;
            tileData.files  = files;
        end

    end % methods (Access = private)

end % classdef

% =========================================================================
function layout = makeSimpleTwoLayerLayout(tileSize)
% Create a minimal 2-tile layout in different Z layers, same XY footprint.
tileHeight = tileSize(1);
tileWidth  = tileSize(2);

layout(1).index      = 1;
layout(1).filename   = 'layer1_tile1.tif';
layout(1).sliceFiles = {};
layout(1).zLayer     = 1;
layout(1).gridRC     = [1 1];
layout(1).nomOrigin  = [1 1 1];
layout(1).tileSize   = [tileHeight tileWidth 1 1];
layout(1).dataClass  = 'uint8';

layout(2).index      = 2;
layout(2).filename   = 'layer2_tile1.tif';
layout(2).sliceFiles = {};
layout(2).zLayer     = 2;
layout(2).gridRC     = [1 1];
layout(2).nomOrigin  = [1 1 2];
layout(2).tileSize   = [tileHeight tileWidth 1 1];
layout(2).dataClass  = 'uint8';
end

% =========================================================================
function filenames = createChopFiles(folderPath, zyxMatrix, tileSize)
% Create synthetic tile files with _Z##-X##-Y## naming for numTiles tiles.
% zyxMatrix: Nx3 [Z Y X] per tile.
numTiles = size(zyxMatrix, 1);
filenames = cell(numTiles, 1);
tileImage = uint8(128 * ones(tileSize(1), tileSize(2)));
for tileIdx = 1:numTiles
    zIdx = zyxMatrix(tileIdx, 1);
    yIdx = zyxMatrix(tileIdx, 2);
    xIdx = zyxMatrix(tileIdx, 3);
    filename = fullfile(folderPath, ...
        sprintf('stack_Z%02d-X%02d-Y%02d.png', zIdx, xIdx, yIdx));
    imwrite(tileImage, filename);
    filenames{tileIdx} = filename;
end
end
