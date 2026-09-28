classdef StitchLayoutTest < matlab.unittest.TestCase
% STITCHLAYOUTTEST - Unit tests for utils.stitch layout builders and helpers.
%
% Covers:
%   utils.stitch.naturalSortFiles       - alphanumeric sort correctness
%   utils.stitch.buildLayoutGrid        - all four TileOrder modes, auto rows/cols
%   utils.stitch.buildLayoutPositionFile - space/tab/comma delimiters,
%                                          repeated spaces, Z column, relative paths
%   utils.stitch.buildLayoutFilenamePattern - _Z##-X##-Y## token parsing
%   utils.stitch.buildLayoutAtlas       - Fibics Atlas .ve-mif / .ve-tie /
%                                         .ve-updates: stage grid, derived axis
%                                         signs, tie conversion, solved positions
%   utils.stitch.findAtlasSidecars      - which Atlas sidecars are present
%   utils.stitch.findNeighborPairs      - x/y/z directions, minOverlap filtering
%   utils.stitch.saveProject / loadProject - JSON round-trip

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
        % buildLayoutGrid - origin formulas
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
            % set tileSize depth to the slice count - while arranging the folders
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
            % square, rows <= cols): 3 tiles -> 1x3, NOT 2x2 with a hole -
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
            % jsondecode returns arrays as columns - the controller reshapes them
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

        % -----------------------------------------------------------------
        % buildLayoutAtlas / findAtlasSidecars - Fibics Atlas mosaics
        % -----------------------------------------------------------------

        function atlasSidecars_reportOnlyWhatExists(testCase)
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            mosaic = mibtest.helpers.makeAtlasMosaic(tmpDir.Folder, struct('writeTies', false, 'writeUpdates', false));

            sidecars = utils.stitch.findAtlasSidecars(mosaic.veMifPath);
            testCase.verifyEqual(sidecars.mifPath, mosaic.veMifPath);
            testCase.verifyEmpty(sidecars.tiePath);
            testCase.verifyEmpty(sidecars.updatesPath);

            mosaicBoth = mibtest.helpers.makeAtlasMosaic(fullfile(tmpDir.Folder, 'both'));
            sidecarsBoth = utils.stitch.findAtlasSidecars(mosaicBoth.veMifPath);
            testCase.verifyTrue(isfile(sidecarsBoth.tiePath));
            testCase.verifyTrue(isfile(sidecarsBoth.updatesPath));
        end

        function atlasSidecars_resolveAnyOfTheThreeFiles(testCase)
            % The three files sit side by side with near-identical names, so
            % whichever the user picks means the same mosaic - .mifPath must come
            % back pointing at the acquisition record either way.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            mosaic = mibtest.helpers.makeAtlasMosaic(tmpDir.Folder);
            [mosaicFolder, mosaicBase] = fileparts(mosaic.veMifPath);

            for extension = {'.ve-mif', '.ve-tie', '.ve-updates'}
                sidecars = utils.stitch.findAtlasSidecars( ...
                    fullfile(mosaicFolder, [mosaicBase, extension{1}]));
                testCase.verifyEqual(sidecars.mifPath, mosaic.veMifPath, ...
                    sprintf('picking %s must resolve to the .ve-mif', extension{1}));
            end
        end

        function atlasSidecars_nonAtlasPathIsNotAnAtlasMosaic(testCase)
            % .mifPath doubles as the "is this an Atlas input?" test that lets the
            % Position file source tell a mosaic from a plain position text file,
            % so a non-Atlas path must come back empty rather than raising.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            positionFile = fullfile(tmpDir.Folder, 'positions.txt');
            fileId = fopen(positionFile, 'w'); fprintf(fileId, 'tile.tif 0 0\n'); fclose(fileId);

            for candidate = {positionFile, fullfile(tmpDir.Folder, 'tile.tif'), 'no_extension'}
                sidecars = utils.stitch.findAtlasSidecars(candidate{1});
                testCase.verifyEmpty(sidecars.mifPath);
                testCase.verifyEmpty(sidecars.tiePath);
                testCase.verifyEmpty(sidecars.updatesPath);
            end
        end

        function atlasLayout_stageGridToPixelOrigins(testCase)
            % The nominal layout comes from the recorded stage positions: a
            % 22 µm step at 0.5 µm/px is 44 px, and stage Y (which points UP)
            % must be inverted so row 2 lands BELOW row 1.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            mosaic = mibtest.helpers.makeAtlasMosaic(tmpDir.Folder);

            layout = utils.stitch.buildLayoutAtlas(mosaic.veMifPath);

            testCase.verifyEqual(numel(layout), 4);
            % Tiles are ordered row-major regardless of the acquisition order
            % (the mosaic writes them r1c1, r1c2, r2c2, r2c1 - Atlas snakes).
            testCase.verifyEqual(vertcat(layout.gridRC), [1 1; 1 2; 2 1; 2 2]);

            origins = reshape([layout.nomOrigin], 3, []).';
            testCase.verifyEqual(origins(1, 1:2), [1 1], 'AbsTol', 1e-6);
            testCase.verifyEqual(origins(2, 1:2), [1 45], 'AbsTol', 1e-6);   % +1 column
            testCase.verifyEqual(origins(3, 1:2), [45 1], 'AbsTol', 1e-6);   % +1 row, Y inverted
            testCase.verifyEqual(origins(4, 1:2), [45 45], 'AbsTol', 1e-6);
            testCase.verifyEqual([layout.zLayer], [1 1 1 1]);   % one .ve-mif = one section
        end

        function atlasLayout_resolvesTilesLocallyNotByRecordedPath(testCase)
            % The .ve-mif records the ACQUISITION machine's absolute paths, which
            % never exist where the data is analysed - tiles must be found by name
            % in the folder holding the .ve-mif.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            mosaic = mibtest.helpers.makeAtlasMosaic(tmpDir.Folder);   % records E:\acquired\...

            layout = utils.stitch.buildLayoutAtlas(mosaic.veMifPath);

            for tileIdx = 1:numel(layout)
                testCase.verifyTrue(isfile(layout(tileIdx).filename));
                testCase.verifyEqual(fileparts(layout(tileIdx).filename), tmpDir.Folder);
            end
        end

        function atlasLayout_axisSignsDerivedFromMosaic(testCase)
            % No vendor convention is assumed: a mosaic whose stage X runs
            % opposite to the column index must still place column 2 to the RIGHT.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            mosaic = mibtest.helpers.makeAtlasMosaic(tmpDir.Folder, struct('mirrorStageX', true));

            [layout, ~, ~, atlasInfo] = utils.stitch.buildLayoutAtlas(mosaic.veMifPath);

            testCase.verifyEqual(atlasInfo.signX, -1);
            origins = reshape([layout.nomOrigin], 3, []).';
            testCase.verifyEqual(origins(2, 2), 45, 'AbsTol', 1e-6);   % r1c2 still to the right
            testCase.verifyEqual(origins(1, 2), 1, 'AbsTol', 1e-6);
        end

        function atlasTies_measuredOffsetsAndProvenance(testCase)
            % A tie states where the shared strip sits in each tile plus the
            % correction Atlas measured: offset = pos1 - pos2 + shift. The
            % synthetic mosaic shortens every vertical seam by 6 px and every
            % horizontal one by 4 px, so 44 px of nominal step measures 38 / 40.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            mosaic = mibtest.helpers.makeAtlasMosaic(tmpDir.Folder);

            [layout, edges] = utils.stitch.buildLayoutAtlas(mosaic.veMifPath, ...
                struct('importTies', true));

            testCase.verifyEqual(numel(edges), 4);
            % Every edge keeps the i < j orientation the rest of the pipeline emits
            testCase.verifyTrue(all([edges.i] < [edges.j]));

            verticalEdge = edges(find(strcmp({edges.direction}, 'y'), 1));
            testCase.verifyEqual(verticalEdge.measured(1), 38, 'AbsTol', 1e-6);
            testCase.verifyEqual(verticalEdge.measured(3), 0);

            horizontalEdge = edges(find(strcmp({edges.direction}, 'x'), 1));
            testCase.verifyEqual(horizontalEdge.measured(2), 40, 'AbsTol', 1e-6);

            % nominal comes from OUR layout, not from the tie file, so the
            % solver's springs stay consistent with the nominal origins
            testCase.verifyEqual(verticalEdge.nominal, ...
                layout(verticalEdge.j).nomOrigin - layout(verticalEdge.i).nomOrigin, 'AbsTol', 1e-6);
        end

        function atlasTies_confidenceMappedAndThresholded(testCase)
            % Atlas confidence is an unbounded ratio (it runs above 1) while MIB
            % quality is [0 1]; ties below Atlas's own threshold are imported but
            % marked invalid, so they act as springs rather than constraints.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            mosaic = mibtest.helpers.makeAtlasMosaic(tmpDir.Folder, ...
                struct('confidences', [1.12, 0.95, 0.40, 0.91], 'confidenceThreshold', 0.82));

            [~, edges] = utils.stitch.buildLayoutAtlas(mosaic.veMifPath, struct('importTies', true));

            testCase.verifyEqual(max([edges.quality]), 1);            % 1.12 clamped
            testCase.verifyTrue(all([edges.quality] >= 0));
            testCase.verifyEqual(nnz(~[edges.valid]), 1);             % only the 0.40 tie
            testCase.verifyEqual(edges(~[edges.valid]).quality, 0.40, 'AbsTol', 1e-9);
        end

        function atlasTies_userPlacedSeamsKeepUserProvenance(testCase)
            % <User>true</User> means a human placed that seam in Atlas - the same
            % meaning MIB's 'user' source carries, so it must survive a re-measure
            % and get the heavier solver weight.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            mosaic = mibtest.helpers.makeAtlasMosaic(tmpDir.Folder, struct('userTies', [true false false false]));

            [~, edges] = utils.stitch.buildLayoutAtlas(mosaic.veMifPath, struct('importTies', true));

            testCase.verifyEqual(nnz(strcmp({edges.source}, 'user')), 1);
            testCase.verifyEqual(nnz(strcmp({edges.source}, 'auto')), 3);
        end

        function atlasUpdates_solvedPositionsImported(testCase)
            % .ve-updates carries the final placement as a 4x4 transform whose
            % M41/M42 is the tile offset in µm - in the same stage-frame
            % orientation as the .ve-mif.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            mosaic = mibtest.helpers.makeAtlasMosaic(tmpDir.Folder);

            [~, ~, positions] = utils.stitch.buildLayoutAtlas(mosaic.veMifPath, ...
                struct('importTies', true, 'importPositions', true));

            testCase.verifyEqual(size(positions), [4 3]);
            relative = positions - positions(1, :);
            testCase.verifyEqual(relative(2, 1:2), [0 40], 'AbsTol', 1e-6);
            testCase.verifyEqual(relative(3, 1:2), [38 0], 'AbsTol', 1e-6);
            testCase.verifyEqual(relative(4, 1:2), [38 40], 'AbsTol', 1e-6);
        end

        function atlasUpdates_withoutTiesSynthesisesConsistentEdges(testCase)
            % Solved positions with no edge set would send Stitch back into a full
            % measure pass, discarding the import; the derived edges must reproduce
            % the imported placement exactly.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            mosaic = mibtest.helpers.makeAtlasMosaic(tmpDir.Folder, struct('writeTies', false));

            [layout, edges, positions] = utils.stitch.buildLayoutAtlas(mosaic.veMifPath, ...
                struct('importPositions', true));

            testCase.verifyNotEmpty(edges);
            testCase.verifyTrue(all([edges.valid]));
            for edgeIdx = 1:numel(edges)
                expected = positions(edges(edgeIdx).j, :) - positions(edges(edgeIdx).i, :);
                testCase.verifyEqual(edges(edgeIdx).measured, expected, 'AbsTol', 1e-9);
            end

            % Re-solving must land back on the imported placement. Not to machine
            % precision: the nominal-position springs pull every tile a hundredth
            % of a pixel back toward the stage grid, which is the solver working
            % as designed rather than the import disagreeing with itself.
            solved = utils.stitch.solveGlobalLeastSquares(layout, edges, struct('springWeight', 0.1));
            testCase.verifyEqual(solved - solved(1, :), positions - positions(1, :), 'AbsTol', 0.05);
        end

        function atlasImport_missingSidecarRaises(testCase)
            % Asking for an import the folder cannot honour must fail loudly -
            % silently falling back would stitch something other than requested.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            mosaic = mibtest.helpers.makeAtlasMosaic(tmpDir.Folder, struct('writeTies', false, 'writeUpdates', false));

            testCase.verifyError(@() utils.stitch.buildLayoutAtlas(mosaic.veMifPath, ...
                struct('importTies', true)), 'utils:stitch:buildLayoutAtlas:noTieFile');
            testCase.verifyError(@() utils.stitch.buildLayoutAtlas(mosaic.veMifPath, ...
                struct('importPositions', true)), 'utils:stitch:buildLayoutAtlas:noUpdatesFile');
        end

        % -----------------------------------------------------------------
        % buildLayoutMdoc / findMdocSidecar - SerialEM montages
        % -----------------------------------------------------------------

        function mdocSidecar_resolvesFromEitherFile(testCase)
            % The montage is two files and either identifies the pair, so both
            % must come back with the .mdoc (the file that has to be parsed) and
            % the image (the file the pixels come from). The PICKER offers only
            % the .mdoc, but a typed path or a batch protocol can still name the
            % .mrc, so the resolution has to work both ways.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            montage = mibtest.helpers.makeMdocMontage(tmpDir.Folder);

            for candidate = {montage.mdocPath, montage.imagePath}
                sidecar = utils.stitch.findMdocSidecar(candidate{1});
                testCase.verifyEqual(sidecar.mdocPath, montage.mdocPath, ...
                    sprintf('picking %s must resolve to the .mdoc', candidate{1}));
                testCase.verifyEqual(sidecar.imagePath, montage.imagePath);
                testCase.verifyTrue(sidecar.isMontage);
                testCase.verifyEqual(sidecar.numTiles, montage.numTiles);
                % 2x2: two X seams and two Y seams.
                testCase.verifyEqual(sidecar.numEdges, 4);
                testCase.verifyEqual(sidecar.numAligned, montage.numTiles);
            end
        end

        function mdocSidecar_reportsOnlyWhatExists(testCase)
            % A montage SerialEM never stitched carries neither stage, and the
            % counts are what let the caller offer only the honourable modes.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            montage = mibtest.helpers.makeMdocMontage(tmpDir.Folder, ...
                struct('writeEdges', false, 'writeAligned', false));

            sidecar = utils.stitch.findMdocSidecar(montage.mdocPath);
            testCase.verifyTrue(sidecar.isMontage);
            testCase.verifyEqual(sidecar.numEdges, 0);
            testCase.verifyEqual(sidecar.numAligned, 0);
        end

        function mdocSidecar_nonMontagePathIsNotASerialEMMontage(testCase)
            % .mdocPath doubles as the "is this a SerialEM input?" test that lets
            % the Position file source tell a montage from a position text file,
            % so a non-montage path must come back empty rather than raising.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            positionFile = fullfile(tmpDir.Folder, 'positions.txt');
            fileId = fopen(positionFile, 'w'); fprintf(fileId, 'tile.tif 0 0\n'); fclose(fileId);

            for candidate = {positionFile, fullfile(tmpDir.Folder, 'tile.tif'), 'no_extension'}
                sidecar = utils.stitch.findMdocSidecar(candidate{1});
                testCase.verifyEmpty(sidecar.mdocPath);
                testCase.verifyEmpty(sidecar.imagePath);
                testCase.verifyFalse(sidecar.isMrcImage);
                testCase.verifyFalse(sidecar.isMontage);
            end
        end

        function mdocSidecar_bareMrcIsDistinguishableFromANonSerialEMFile(testCase)
            % An MRC with no .mdoc beside it and a plain .txt both leave
            % .mdocPath empty, but they need OPPOSITE handling: the stack earns
            % an explanation ("where is the .mdoc?"), the text file falls through
            % to the position-file parser. .isMrcImage is what tells them apart.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            montage = mibtest.helpers.makeMdocMontage(tmpDir.Folder);
            delete(montage.mdocPath);

            sidecar = utils.stitch.findMdocSidecar(montage.imagePath);
            testCase.verifyEmpty(sidecar.mdocPath, ...
                'without its .mdoc a stack is not a montage');
            testCase.verifyTrue(sidecar.isMrcImage, ...
                'but it is still recognisably an MRC image');
        end

        function mdocLayout_mirrorsTheMontageYAxisAndOrdersByGrid(testCase)
            % PieceCoordinates Y runs UP while MIB rows run DOWN, so grid row 1
            % is the piece with the LARGEST Y. Slices are written in acquisition
            % order (Y fastest within each X), which must NOT leak into the
            % layout's ordering.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            montage = mibtest.helpers.makeMdocMontage(tmpDir.Folder);

            layout = utils.stitch.buildLayoutMdoc(montage.mdocPath);

            testCase.verifyEqual(numel(layout), montage.numTiles);
            testCase.verifyEqual(vertcat(layout.gridRC), [1 1; 1 2; 2 1; 2 2]);
            % The acquisition order really is scrambled relative to grid order -
            % otherwise this test would pass on a reader that ignores the sort.
            testCase.verifyNotEqual([layout.sliceIndex], 1:montage.numTiles);

            % Nominal origins follow the (wrong) recorded step, 1-based.
            origins = reshape([layout.nomOrigin], 3, []).';
            step = montage.nominalStepPx;
            testCase.verifyEqual(origins(:, 1:2), ...
                [1 1; 1 1+step; 1+step 1; 1+step 1+step], 'AbsTol', 1e-9);
        end

        function mdocLayout_carriesSliceIndexIntoTheSharedContainer(testCase)
            % Unlike every other layout source the tiles are not separate files:
            % .filename is the ONE container and .sliceIndex addresses the tile.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            montage = mibtest.helpers.makeMdocMontage(tmpDir.Folder);

            layout = utils.stitch.buildLayoutMdoc(montage.mdocPath);

            testCase.verifyEqual(unique({layout.filename}), {montage.imagePath});
            testCase.verifyEqual(sort([layout.sliceIndex]), 1:montage.numTiles);
            testCase.verifyEmpty([layout.sliceFiles]);
            testCase.verifyEqual(layout(1).tileSize, ...
                [montage.tileSizePx, montage.tileSizePx, 1, 1]);

            % The reader must return the slice the layout points at: read every
            % tile and check each is the crop the true placement implies.
            readerFcn = utils.stitch.makeTileReader(layout);
            for tileIdx = 1:numel(layout)
                tile = readerFcn(tileIdx);
                testCase.verifySize(tile, [montage.tileSizePx, montage.tileSizePx, 1, 1]);
            end
            % Two tiles that overlap must agree pixel-for-pixel in the shared
            % strip at the TRUE placement - the check that a wrong sliceIndex,
            % a missing flip or a transposed permute would all fail.
            leftTile  = squeeze(readerFcn(1));
            rightTile = squeeze(readerFcn(2));
            sharedWidth = montage.tileSizePx - montage.trueStepXpx;
            testCase.verifyEqual(leftTile(:, end - sharedWidth + 1:end), ...
                rightTile(:, 1:sharedWidth), ...
                'overlapping strip must match at the true placement');
        end

        function mdocLayout_carriesTheAcquisitionPixelSize(testCase)
            % The .mdoc states PixelSpacing in Angstroms. Without carrying it the
            % stitched mosaic silently measures in 1 um pixels - wrong by four
            % orders of magnitude here, and wrong SILENTLY, which is worse: every
            % distance and area measured on the result would be plausible garbage.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            montage = mibtest.helpers.makeMdocMontage(tmpDir.Folder);

            layout = utils.stitch.buildLayoutMdoc(montage.mdocPath);
            pixSize = utils.stitch.layoutPixSize(layout);

            testCase.verifyNotEmpty(pixSize);
            testCase.verifyEqual(pixSize.x, 18.38 / 10000, 'AbsTol', 1e-9);
            testCase.verifyEqual(pixSize.y, pixSize.x);
            testCase.verifyEqual(pixSize.units, 'um');
            % A montage is one section and the .mdoc records no thickness, so Z is
            % the in-plane size rather than a fabricated number.
            testCase.verifyEqual(pixSize.z, pixSize.x);

            % And it has to reach the canvas, which is what the dataset reads.
            [~, ~, positions] = utils.stitch.buildLayoutMdoc(montage.mdocPath, ...
                struct('importEdges', true, 'importPositions', true));
            canvas = utils.stitch.planCanvas(layout, positions, struct('pixSize', pixSize));
            testCase.verifyEqual(canvas.pixSize.x, pixSize.x, 'AbsTol', 1e-9);
        end

        function layoutPixSize_saysNothingRatherThanGuessing(testCase)
            % A layout built from a plain folder of images knows no physical scale.
            % It must return empty, NOT a 1 um default: planCanvas already applies
            % that fallback, and inventing it here would make "measured 1 um" and
            % "no idea" indistinguishable to every caller.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            [~, tileFiles] = writeShadedTiles(tmpDir.Folder, 4, 32, 0.2);
            layout = utils.stitch.buildLayoutGrid(tileFiles, ...
                struct('rows', 2, 'cols', 2, 'tileOrder', 'Horizontal', ...
                       'overlapX', 10, 'overlapY', 10));

            testCase.verifyEmpty(utils.stitch.layoutPixSize(layout));

            % A partially-filled field must not veto the tiles that do know.
            layout(1).pixSize = [];
            layout(2).pixSize = struct('x', 0, 'y', 0, 'z', 0);           % unusable
            layout(3).pixSize = struct('x', 0.5, 'y', 0.5, 'z', 1.0);     % usable
            layout(4).pixSize = [];
            resolved = utils.stitch.layoutPixSize(layout);
            testCase.verifyEqual(resolved.x, 0.5);
            testCase.verifyEqual(resolved.z, 1.0);
            testCase.verifyEqual(resolved.units, 'um', ...
                'a pixel size with no stated units must be labelled, not left blank');
        end

        function mdocEdges_convertWithBothSignFlips(testCase)
            % XedgeDxy/YedgeDxy are [dx dy] stated for the LOWER piece, so the
            % offset is their negation; the ROW component then flips a second
            % time through the Y mirror and comes back positive. Getting either
            % flip wrong still yields plausible magnitudes, so the test pins the
            % exact measured step per axis.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            montage = mibtest.helpers.makeMdocMontage(tmpDir.Folder);

            [~, edges] = utils.stitch.buildLayoutMdoc(montage.mdocPath, ...
                struct('importEdges', true));

            testCase.verifyEqual(numel(edges), 4);
            for edgeIdx = 1:numel(edges)
                testCase.verifyLessThan(edges(edgeIdx).i, edges(edgeIdx).j, ...
                    'edges must be emitted with i < j like every other producer');
                measured = edges(edgeIdx).measured;
                if strcmp(edges(edgeIdx).direction, 'x')
                    testCase.verifyEqual(measured(1:2), [0, montage.trueStepXpx], 'AbsTol', 1e-9);
                else
                    testCase.verifyEqual(measured(1:2), [montage.trueStepYpx, 0], 'AbsTol', 1e-9);
                end
                % SerialEM records no per-seam confidence.
                testCase.verifyEqual(edges(edgeIdx).quality, 1);
                testCase.verifyTrue(edges(edgeIdx).valid);
                testCase.verifyEqual(edges(edgeIdx).source, 'auto');
            end
        end

        function mdocAlignedCoords_giveThePixelCorrectPlacement(testCase)
            % The tiles were cut from one texture at the ALIGNED offsets, so the
            % imported placement is the pixel-correct one and its seams score ~1,
            % while the nominal grid (4 px out in X, 6 in Y) scores far worse.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            montage = mibtest.helpers.makeMdocMontage(tmpDir.Folder);

            [layout, edges, positions] = utils.stitch.buildLayoutMdoc(montage.mdocPath, ...
                struct('importEdges', true, 'importPositions', true));

            testCase.verifyEqual(positions(:, 1:2), montage.expectedOriginRC, 'AbsTol', 1e-9);

            scoredAtImport = utils.stitch.scoreSeams(layout, edges, positions, ...
                struct('showWaitbar', false));
            nominalOrigins = reshape([layout.nomOrigin], 3, []).';
            scoredAtNominal = utils.stitch.scoreSeams(layout, edges, nominalOrigins, ...
                struct('showWaitbar', false));

            testCase.verifyGreaterThan(min([scoredAtImport.seamScore]), 0.95);
            testCase.verifyLessThan(max([scoredAtNominal.seamScore]), ...
                min([scoredAtImport.seamScore]));
        end

        function mdocSolveFromImportedEdgesReproducesTheAlignedPlacement(testCase)
            % The two later stages must agree: solving MIB's own global system on
            % SerialEM's edge shifts has to land on SerialEM's own placement.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            montage = mibtest.helpers.makeMdocMontage(tmpDir.Folder);

            [layout, edges, positions] = utils.stitch.buildLayoutMdoc(montage.mdocPath, ...
                struct('importEdges', true, 'importPositions', true));

            solved = utils.stitch.solveGlobalLeastSquares(layout, edges, ...
                struct('nominalWeight', 0.001, 'anchor', 1));
            solvedRC = solved(:, 1:2) - min(solved(:, 1:2), [], 1) + 1;

            testCase.verifyEqual(solvedRC, positions(:, 1:2), 'AbsTol', 0.05);
        end

        function mdocPositionsWithoutEdgesSynthesiseThem(testCase)
            % A placement imported with no measurements would send Stitch back
            % into a full measure pass, throwing the import away.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            montage = mibtest.helpers.makeMdocMontage(tmpDir.Folder, ...
                struct('writeEdges', false));

            [~, edges, positions] = utils.stitch.buildLayoutMdoc(montage.mdocPath, ...
                struct('importPositions', true));

            testCase.verifyNotEmpty(edges);
            testCase.verifyNotEmpty(positions);
            % Self-consistent by construction: each edge is the position delta.
            for edgeIdx = 1:numel(edges)
                testCase.verifyEqual(edges(edgeIdx).measured, ...
                    positions(edges(edgeIdx).j, :) - positions(edges(edgeIdx).i, :), ...
                    'AbsTol', 1e-9);
            end
        end

        function mdocFloatStackRescalesFromTheHeader(testCase)
            % A float montage must be mapped onto uint16 from the FILE header's
            % density range, so every tile of the stack shares one scale.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            montage = mibtest.helpers.makeMdocMontage(tmpDir.Folder, struct('asFloat', true));

            [layout, ~, positions] = utils.stitch.buildLayoutMdoc(montage.mdocPath, ...
                struct('importEdges', true, 'importPositions', true));

            testCase.verifyEqual(layout(1).dataClass, 'uint16');
            testCase.verifyEqual(positions(:, 1:2), montage.expectedOriginRC, 'AbsTol', 1e-9);

            % The stack's own min and max must land on the class limits, and the
            % overlapping strip must still match - a per-slice rescale would put
            % each tile on its own scale and break the second check.
            readerFcn = utils.stitch.makeTileReader(layout);
            allTiles = [];
            for tileIdx = 1:numel(layout)
                tile = readerFcn(tileIdx);
                testCase.verifyClass(tile, 'uint16');
                allTiles = [allTiles; tile(:)]; %#ok<AGROW>
            end
            testCase.verifyEqual(double(min(allTiles)), 0, 'AbsTol', 1);
            testCase.verifyEqual(double(max(allTiles)), 65535, 'AbsTol', 1);

            leftTile  = squeeze(readerFcn(1));
            rightTile = squeeze(readerFcn(2));
            sharedWidth = montage.tileSizePx - montage.trueStepXpx;
            testCase.verifyEqual(leftTile(:, end - sharedWidth + 1:end), ...
                rightTile(:, 1:sharedWidth));
        end

        function mdocRegionReadMatchesTheFullTile(testCase)
            % The ranged getVolume fast path has to mirror the row range into the
            % container's bottom-up axis; an off-by-one or a missing flip shows up
            % only against a full-load-then-crop.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            montage = mibtest.helpers.makeMdocMontage(tmpDir.Folder);
            layout = utils.stitch.buildLayoutMdoc(montage.mdocPath);

            fullReader = utils.stitch.makeTileReader(layout);
            fullTile = fullReader(2);

            pixelRegion = [7 39; 11 52];
            regionReader = utils.stitch.makeTileReader(layout);   % fresh: no cache to crop
            regionTile = regionReader(2, pixelRegion);

            testCase.verifyEqual(regionTile, ...
                fullTile(pixelRegion(1,1):pixelRegion(1,2), pixelRegion(2,1):pixelRegion(2,2), :, :));
        end

        function mdocTiltSeriesIsRejected(testCase)
            % SerialEM writes the same format for tilt series, which have no
            % PieceCoordinates and are not stitchable - one clear error beats a
            % confusing parse of the wrong file kind.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            montage = mibtest.helpers.makeMdocMontage(tmpDir.Folder, ...
                struct('writePieceCoords', false, 'montageKey', false));

            sidecar = utils.stitch.findMdocSidecar(montage.mdocPath);
            testCase.verifyNotEmpty(sidecar.mdocPath);   % still recognised as SerialEM
            testCase.verifyFalse(sidecar.isMontage);     % but not as a mosaic

            testCase.verifyError(@() utils.stitch.buildLayoutMdoc(montage.mdocPath), ...
                'utils:stitch:buildLayoutMdoc:notAMontage');
        end

        % -----------------------------------------------------------------
        % estimateIntensityCorrection - intensity correction
        % -----------------------------------------------------------------

        function intensityCorrection_noneIsNeutralAndReadsNothing(testCase)
            % 'None' must be free: no tile reads, and pixels byte-identical to a
            % reader built with no correction at all.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            montage = mibtest.helpers.makeMdocMontage(tmpDir.Folder, ...
                struct('shadingPercent', 12, 'plainTexture', true));
            layout = utils.stitch.buildLayoutMdoc(montage.mdocPath);

            correction = utils.stitch.estimateIntensityCorrection(layout);
            testCase.verifyEqual(correction.method, 'None');
            testCase.verifyEmpty(correction.field);
            testCase.verifyTrue(all(correction.gain == 1));
            testCase.verifyTrue(all(correction.offset == 0));

            plainReader   = utils.stitch.makeTileReader(layout);
            neutralReader = utils.stitch.makeTileReader(layout, struct('correction', correction));
            testCase.verifyEqual(neutralReader(2), plainReader(2), ...
                'a neutral correction must not touch a single pixel');
        end

        function intensityCorrection_flatFieldRecoversAKnownField(testCase)
            % Every tile carries the SAME illumination field over INDEPENDENT
            % content. That is the assumption the shared-field estimator states,
            % and under it the field has to come back: matching the truth in shape
            % (it is normalised to mean 1, so only the shape is recoverable) and
            % flattening the tiles when divided out.
            %
            % Deliberately NOT built on makeMdocMontage: four heavily-overlapping
            % tiles do not decorrelate, so their content survives the average and
            % lands in the field. Sixteen independent tiles are what the estimator
            % is actually for - see the warning in estimateIntensityCorrection.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tileSize = 96;
            fieldSpan = 0.30;
            [truthField, tileFiles] = writeShadedTiles(tmpDir.Folder, 16, tileSize, fieldSpan);

            layout = utils.stitch.buildLayoutGrid(tileFiles, ...
                struct('rows', 4, 'cols', 4, 'tileOrder', 'Horizontal', ...
                       'overlapX', 10, 'overlapY', 10));
            correction = utils.stitch.estimateIntensityCorrection(layout, ...
                struct('method', 'Flat-field (shared)'));

            testCase.verifyEqual(correction.method, 'Flat-field (shared)');
            testCase.verifySize(correction.field, [tileSize, tileSize]);
            testCase.verifyEqual(double(mean(correction.field, 'all')), 1, 'AbsTol', 0.02);

            % Shape: strongly correlated with the truth, and the same span.
            estimated = double(correction.field(:));
            truth     = double(truthField(:));
            fieldCorrelation = corr(estimated, truth);
            testCase.verifyGreaterThan(fieldCorrelation, 0.9, ...
                'the estimated field does not follow the one that was applied');
            testCase.verifyEqual(max(estimated) - min(estimated), ...
                max(truth) - min(truth), 'RelTol', 0.35);

            % Effect: averaging the tiles is what exposes the illumination (it is
            % the only thing they share), so the average of the CORRECTED tiles
            % has to come out flat. Measured on the average rather than on one
            % tile, because a single 96 px tile's own texture swamps a 30 % field.
            rawReader   = utils.stitch.makeTileReader(layout);
            fixedReader = utils.stitch.makeTileReader(layout, struct('correction', correction));
            rawSpread   = normalizedTileAverageSpread(rawReader, numel(layout));
            fixedSpread = normalizedTileAverageSpread(fixedReader, numel(layout));

            testCase.verifyGreaterThan(rawSpread, 0.8 * fieldSpan, ...
                'the uncorrected tiles should still show the field that was applied');
            testCase.verifyLessThan(fixedSpread, 0.4 * rawSpread, ...
                'dividing out the field must flatten what the tiles have in common');
        end

        function intensityCorrection_fewOverlappingTilesAbsorbTheSpecimen(testCase)
            % The documented failure mode, pinned so it cannot regress into a
            % silent surprise: with few heavily-overlapping tiles the shared-field
            % estimate picks up the SPECIMEN's low-frequency structure, and the
            % field comes out far larger than the illumination actually applied.
            % This is why the method is opt-in and why an overlap-driven estimate
            % is the planned successor - not something to tune the smoothing for.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            montage = mibtest.helpers.makeMdocMontage(tmpDir.Folder, ...
                struct('shadingPercent', 12));   % ramped texture, 4 tiles, 33% overlap
            layout = utils.stitch.buildLayoutMdoc(montage.mdocPath);

            correction = utils.stitch.estimateIntensityCorrection(layout, ...
                struct('method', 'Flat-field (shared)'));

            appliedSpan = double(max(montage.shadingField(:)) - min(montage.shadingField(:)));
            estimatedSpan = double(max(correction.field(:)) - min(correction.field(:)));
            testCase.verifyGreaterThan(estimatedSpan, 2 * appliedSpan, ...
                ['This configuration is expected to OVER-estimate the field. ' ...
                 'If it no longer does, the estimator changed - re-read the ' ...
                 'warning in estimateIntensityCorrection and update it.']);
        end

        function intensityCorrection_matchTileMeansEqualisesTheMeans(testCase)
            % 'Match tile means' targets a DIFFERENT fault: tiles that differ by a
            % flat factor (a drifting detector), not an in-tile gradient.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            appliedGains = [1.00 1.25 0.80 1.10];
            montage = mibtest.helpers.makeMdocMontage(tmpDir.Folder, ...
                struct('tileGains', appliedGains, 'asFloat', true));
            layout = utils.stitch.buildLayoutMdoc(montage.mdocPath);

            correction = utils.stitch.estimateIntensityCorrection(layout, ...
                struct('method', 'Match tile means'));

            testCase.verifyEqual(correction.method, 'Match tile means');
            testCase.verifyEmpty(correction.field, ...
                'mean matching is a per-tile scalar, not a field');

            readerFcn = utils.stitch.makeTileReader(layout, struct('correction', correction));
            correctedMeans = zeros(numel(layout), 1);
            for tileIdx = 1:numel(layout)
                correctedMeans(tileIdx) = mean(single(readerFcn(tileIdx)), 'all');
            end
            spread = (max(correctedMeans) - min(correctedMeans)) / mean(correctedMeans);
            testCase.verifyLessThan(spread, 0.02, ...
                'every tile must end up at the common mean');
        end

        function intensityCorrection_appliesToCropsAndFullTilesAlike(testCase)
            % A cropped read bypasses the cache and corrects its own patch of the
            % field. If the crop were taken from the wrong part of the field the
            % two paths would disagree - which is what this pins down.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            montage = mibtest.helpers.makeMdocMontage(tmpDir.Folder, ...
                struct('shadingPercent', 12, 'plainTexture', true));
            layout = utils.stitch.buildLayoutMdoc(montage.mdocPath);
            correction = utils.stitch.estimateIntensityCorrection(layout, ...
                struct('method', 'Flat-field (shared)'));

            fullReader = utils.stitch.makeTileReader(layout, struct('correction', correction));
            fullTile = fullReader(3);

            pixelRegion = [9 44; 17 60];
            cropReader = utils.stitch.makeTileReader(layout, struct('correction', correction));
            cropTile = cropReader(3, pixelRegion);   % fresh reader: takes the fast path

            testCase.verifyEqual(cropTile, ...
                fullTile(pixelRegion(1,1):pixelRegion(1,2), pixelRegion(2,1):pixelRegion(2,2), :, :), ...
                'the cropped fast path must correct the matching patch of the field');
        end

        function intensityCorrection_overlapSolvedSurvivesASpecimenTrend(testCase)
            % The case the shared-field method cannot handle: the SPECIMEN has a
            % broad brightness trend of its own. Averaging the tiles cannot tell
            % that from illumination, so the shared field absorbs it; fitting to
            % the overlaps can, because both tiles image the same specimen there
            % and it cancels in the difference.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tileSize = 96; stepPx = 72; overlapPercent = 100*(tileSize-stepPx)/tileSize;
            [truthField, tileFiles, truePositions] = writeOverlappingShadedTiles( ...
                tmpDir.Folder, tileSize, stepPx, 3, 0.30, 0.40);

            layout = utils.stitch.buildLayoutGrid(tileFiles, ...
                struct('rows', 3, 'cols', 3, 'tileOrder', 'Horizontal', ...
                       'overlapX', overlapPercent, 'overlapY', overlapPercent));

            solved = utils.stitch.estimateIntensityCorrection(layout, ...
                struct('method', 'Flat-field (overlap-solved)', 'positions', truePositions));
            shared = utils.stitch.estimateIntensityCorrection(layout, ...
                struct('method', 'Flat-field (shared)'));

            testCase.verifyEqual(solved.method, 'Flat-field (overlap-solved)');
            testCase.verifySize(solved.field, [tileSize, tileSize]);

            % Seams observe the field only near tile BORDERS, so the polynomial
            % carries it into the middle unchecked. A degree the seams cannot
            % support bows there - and this shipped once: a degree-4 fit dipped to
            % 0.87 at the tile centre against 1.12 at the edges, which brightened
            % every tile centre and drew a DARK GRID along the seams while the
            % seam residual read better than any other method. The seam metric is
            % blind to it by construction, so it has to be asserted separately.
            fieldValues = double(solved.field);
            borderWidth = round(0.1 * tileSize);
            borderMask = false(tileSize);
            borderMask([1:borderWidth, end-borderWidth+1:end], :) = true;
            borderMask(:, [1:borderWidth, end-borderWidth+1:end]) = true;
            centreIdx = round(tileSize/2) + (-round(tileSize/8):round(tileSize/8));
            centreToBorder = mean(fieldValues(centreIdx, centreIdx), 'all') / ...
                             mean(fieldValues(borderMask));
            testCase.verifyEqual(centreToBorder, 1, 'AbsTol', 0.15, ...
                'the fitted field bows where no seam observes it');

            % The seam-fitted field must track the truth, and beat the averaged one.
            truth = double(truthField(:));
            solvedCorrelation = corr(double(solved.field(:)), truth);
            sharedCorrelation = corr(double(shared.field(:)), truth);
            testCase.verifyGreaterThan(solvedCorrelation, 0.95, ...
                'the seam-fitted field does not follow the one that was applied');
            testCase.verifyGreaterThan(solvedCorrelation, sharedCorrelation, ...
                'fitting to seams must beat averaging when the specimen has its own trend');

            % And what actually matters: the brightness step across each seam.
            solvedMismatch = seamBrightnessMismatch(layout, truePositions, solved);
            sharedMismatch = seamBrightnessMismatch(layout, truePositions, shared);
            noneMismatch   = seamBrightnessMismatch(layout, truePositions, []);
            testCase.verifyLessThan(solvedMismatch, sharedMismatch, ...
                'the seam-fitted field must leave smaller steps than the averaged one');
            testCase.verifyLessThan(solvedMismatch, 0.25 * noneMismatch);
        end

        function intensityCorrection_degreeIsChosenAndReported(testCase)
            % The field's flexibility is chosen by the data, not hard-coded: the
            % report records what each candidate scored and whether it passed the
            % interior check, and the chosen degree must be one that passed.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tileSize = 96; stepPx = 72; overlapPercent = 100*(tileSize-stepPx)/tileSize;
            [~, tileFiles, truePositions] = writeOverlappingShadedTiles( ...
                tmpDir.Folder, tileSize, stepPx, 3, 0.30, 0.40);
            layout = utils.stitch.buildLayoutGrid(tileFiles, ...
                struct('rows', 3, 'cols', 3, 'tileOrder', 'Horizontal', ...
                       'overlapX', overlapPercent, 'overlapY', overlapPercent));

            correction = utils.stitch.estimateIntensityCorrection(layout, ...
                struct('method', 'Flat-field (overlap-solved)', 'positions', truePositions));

            testCase.verifyNotEmpty(correction.degree);
            testCase.verifyNotEmpty(correction.degreeReport);
            testCase.verifyTrue(ismember(correction.degree, [correction.degreeReport.degree]));
            chosenEntry = correction.degreeReport([correction.degreeReport.degree] == correction.degree);
            testCase.verifyTrue(chosenEntry.accepted, ...
                'a degree that failed the interior check must never be chosen');
            % Every entry carries both scores, so a later regression is diagnosable.
            testCase.verifyTrue(all(isfinite([correction.degreeReport.interiorDeviation])));
        end

        function intensityCorrection_forcedBowingDegreeIsRefused(testCase)
            % A degree the seams cannot support must be refused even when asked
            % for explicitly - that failure is invisible to every seam metric, so
            % the interior check is the only thing standing between it and a
            % mosaic with a dark grid along every seam.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tileSize = 96; stepPx = 72; overlapPercent = 100*(tileSize-stepPx)/tileSize;
            [~, tileFiles, truePositions] = writeOverlappingShadedTiles( ...
                tmpDir.Folder, tileSize, stepPx, 3, 0.30, 0.40);
            layout = utils.stitch.buildLayoutGrid(tileFiles, ...
                struct('rows', 3, 'cols', 3, 'tileOrder', 'Horizontal', ...
                       'overlapX', overlapPercent, 'overlapY', overlapPercent));

            % An interior tolerance of 0 rejects every candidate, which is the
            % deterministic way to exercise the refusal path.
            correction = testCase.verifyWarning(@() ...
                utils.stitch.estimateIntensityCorrection(layout, struct( ...
                    'method', 'Flat-field (overlap-solved)', 'positions', truePositions, ...
                    'maxInteriorDeviation', 0)), ...
                'utils:stitch:estimateIntensityCorrection:noUsableDegree');

            testCase.verifyEmpty(correction.field, ...
                'a refused fit must correct nothing rather than ship the artefact');
            testCase.verifyTrue(all(correction.gain == 1));
        end

        function intensityCorrection_mosaicLevellingIsFreeAtTheSeams(testCase)
            % Fitting the seams leaves a whole FAMILY of solutions: field and
            % per-tile gains can trade a plane between them without changing any
            % seam difference at all. Levelling spends that freedom on a flat
            % mosaic, and the proof that it is really free - not a second fit
            % quietly degrading the first - is that the seam steps come out
            % IDENTICAL, not merely similar.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tileSize = 96; stepPx = 72; overlapPercent = 100*(tileSize-stepPx)/tileSize;
            [~, tileFiles, truePositions] = writeOverlappingShadedTiles( ...
                tmpDir.Folder, tileSize, stepPx, 3, 0.30, 0.40);
            layout = utils.stitch.buildLayoutGrid(tileFiles, ...
                struct('rows', 3, 'cols', 3, 'tileOrder', 'Horizontal', ...
                       'overlapX', overlapPercent, 'overlapY', overlapPercent));

            levelled = utils.stitch.estimateIntensityCorrection(layout, struct( ...
                'method', 'Flat-field (overlap-solved)', 'positions', truePositions));
            unlevelled = utils.stitch.estimateIntensityCorrection(layout, struct( ...
                'method', 'Flat-field (overlap-solved)', 'positions', truePositions, ...
                'levelMosaic', false));

            % The invariant, asserted on the correction itself rather than through
            % pixels: the field may change by EXACTLY a plane and by nothing else,
            % and each gain must move by exactly the negative of that plane at its
            % tile's centre. Those two together are what make the seam differences
            % cancel; any other change to the field would be a second fit wearing
            % the gauge's clothes.
            tileSizePx = double(levelled.tileSize);
            [allCols, allRows] = meshgrid(1:tileSizePx(2), 1:tileSizePx(1));
            normX = (allCols(:) - (tileSizePx(2)+1)/2) / (tileSizePx(2)/2);
            normY = (allRows(:) - (tileSizePx(1)+1)/2) / (tileSizePx(1)/2);
            fieldChange = log(double(levelled.field(:))) - log(double(unlevelled.field(:)));
            planeBasis = [ones(numel(normX),1), normX, normY];
            planeFit = planeBasis \ fieldChange;
            testCase.verifyLessThan(max(abs(planeBasis*planeFit - fieldChange)), 1e-6, ...
                'levelling must change the field by a plane and nothing else');

            centres = [(truePositions(:,2) + (tileSizePx(2)-1)/2) / (tileSizePx(2)/2), ...
                       (truePositions(:,1) + (tileSizePx(1)-1)/2) / (tileSizePx(1)/2)];
            gainChange = log(levelled.gain) - log(unlevelled.gain);
            expectedGainChange = -(centres * planeFit(2:3));
            % Both sets are renormalised (field to mean 1, gains to geometric mean
            % 1), so the two differ by a constant that carries no seam meaning.
            testCase.verifyLessThan( ...
                max(abs((gainChange - mean(gainChange)) - ...
                        (expectedGainChange - mean(expectedGainChange)))), 1e-6, ...
                'each gain must absorb exactly the plane added to the field');

            % And the pixels follow. Only approximately here: the reader casts
            % back to the tile's integer class, and these fixture tiles are 8-bit,
            % so rounding moves the measured step by a few percent. On real 16-bit
            % data the two read identical - the exact statement is the one above.
            testCase.verifyEqual( ...
                double(seamBrightnessMismatch(layout, truePositions, levelled)), ...
                double(seamBrightnessMismatch(layout, truePositions, unlevelled)), ...
                'RelTol', 0.1, ...
                'levelling must not change the seam steps beyond pixel rounding');

            % And it must actually do something: the mosaic-wide brightness plane
            % that the un-levelled solve leaves behind is the artefact users
            % report, even at an excellent seam residual.
            testCase.verifyLessThan( ...
                mosaicPlaneStrength(layout, truePositions, levelled), ...
                0.5 * mosaicPlaneStrength(layout, truePositions, unlevelled), ...
                'levelling must flatten the mosaic-wide brightness plane');
            testCase.verifyNotEqual(levelled.mosaicPlane, [0 0]);
            testCase.verifyEqual(unlevelled.mosaicPlane, [0 0]);
        end

        function intensityCorrection_overlapSolvedWorksBeforeAnySolve(testCase)
            % Measure overlaps runs BEFORE any placement is solved, so the method
            % has to work off nominal origins too - samples are block-averaged, so
            % a few pixels of placement error cannot move a low-order field.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tileSize = 96; stepPx = 72; overlapPercent = 100*(tileSize-stepPx)/tileSize;
            [truthField, tileFiles] = writeOverlappingShadedTiles( ...
                tmpDir.Folder, tileSize, stepPx, 3, 0.30, 0.40);
            layout = utils.stitch.buildLayoutGrid(tileFiles, ...
                struct('rows', 3, 'cols', 3, 'tileOrder', 'Horizontal', ...
                       'overlapX', overlapPercent, 'overlapY', overlapPercent));

            % No positions supplied at all: nomOrigin is used.
            correction = utils.stitch.estimateIntensityCorrection(layout, ...
                struct('method', 'Flat-field (overlap-solved)'));

            testCase.verifyEqual(correction.method, 'Flat-field (overlap-solved)');
            testCase.verifyGreaterThan(corr(double(correction.field(:)), double(truthField(:))), 0.95);
        end

        function intensityCorrection_mismatchedFieldIsRefused(testCase)
            % A correction estimated for a different layout must fail loudly
            % rather than silently mis-scale every tile.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            montage = mibtest.helpers.makeMdocMontage(tmpDir.Folder, ...
                struct('shadingPercent', 12, 'plainTexture', true));
            layout = utils.stitch.buildLayoutMdoc(montage.mdocPath);
            correction = utils.stitch.estimateIntensityCorrection(layout, ...
                struct('method', 'Flat-field (shared)'));
            correction.field = correction.field(1:10, 1:10);

            readerFcn = utils.stitch.makeTileReader(layout, struct('correction', correction));
            testCase.verifyError(@() readerFcn(1), ...
                'utils:stitch:makeTileReader:correctionSizeMismatch');
        end

        function reexposure_recoversAndRemovesKnownDamage(testCase)
            % A 2x2 raster cut from ONE texture, each tile darkened where the
            % tiles imaged before it had already scanned - including a ridge past
            % every footprint edge and a corner hit twice. The estimator has to
            % find the order from the pixels, recover the plateau, and give back
            % the undamaged texture.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            truthGain = 1.12; truthOffset = -30;
            [tileFiles, truePositions, truthTiles] = writeReexposedTiles(tmpDir.Folder, ...
                200, 150, truthGain, truthOffset);
            layout = utils.stitch.buildLayoutGrid(tileFiles, ...
                struct('rows', 2, 'cols', 2, 'tileOrder', 'Horizontal', ...
                       'overlapX', 25, 'overlapY', 25));

            correction = utils.stitch.estimateIntensityCorrection(layout, ...
                reexposureOptions(truePositions));

            testCase.verifyEqual(correction.method, 'Re-exposure damage');
            damage = correction.damage;
            testCase.verifyEqual(damage.gain, truthGain, 'AbsTol', 0.03);
            testCase.verifyEqual(damage.offset, truthOffset, 'AbsTol', 4);
            % Every pair, the two diagonals included, points from the tile imaged
            % first to the one imaged after it.
            testCase.verifyEqual(sortrows(damage.pairs), ...
                [1 2 1; 1 3 1; 1 4 1; 2 3 1; 2 4 1; 3 4 1]);
            % The ridge outside the edge was seen, not just the plateau.
            rightSide = damage.profiles(2, :);
            testCase.verifyGreaterThan(interp1(damage.distance, rightSide, 1.5), 1.2);
            testCase.verifyEqual(interp1(damage.distance, rightSide, 28.5), 0, 'AbsTol', 0.1);

            readerFcn = utils.stitch.makeTileReader(layout, struct('correction', correction));
            for tileIdx = 2:4
                raw = double(imread(tileFiles{tileIdx}));
                fixed = double(readerFcn(tileIdx));
                rawError   = mean(abs(raw - truthTiles{tileIdx}), 'all');
                fixedError = mean(abs(fixed - truthTiles{tileIdx}), 'all');
                testCase.verifyLessThan(fixedError, 0.25 * rawError, sprintf( ...
                    'tile %d: the damage was not removed (%.2f -> %.2f grey levels)', ...
                    tileIdx, rawError, fixedError));
            end
            testCase.verifyEqual(readerFcn(1), imread(tileFiles{1}), ...
                'the tile imaged first carries no damage and must not be touched');
        end

        function reexposure_overwriteKeepsTheUndamagedTileOnTop(testCase)
            % Overwrite normally lets the highest index win. With a damage model
            % the FIRST-imaged tile must win instead: the correction evens out the
            % later tile's brightness but cannot restore structure the beam hit,
            % and the earlier tile shows the same area undamaged.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            [tileFiles, truePositions] = writeReexposedTiles(tmpDir.Folder, 200, 150, 1.12, -30);
            layout = utils.stitch.buildLayoutGrid(tileFiles, ...
                struct('rows', 2, 'cols', 2, 'tileOrder', 'Horizontal', ...
                       'overlapX', 25, 'overlapY', 25));
            correction = utils.stitch.estimateIntensityCorrection(layout, ...
                reexposureOptions(truePositions));
            canvas = utils.stitch.planCanvas(layout, [truePositions, ones(4, 1)]);

            mosaic = utils.stitch.fuseInMemory(layout, canvas, ...
                struct('blendMode', 'Overwrite', 'correction', correction));
            tileOne = imread(tileFiles{1});
            % The whole of tile 1 - every overlap included - comes out as tile 1.
            testCase.verifyEqual(mosaic(1:200, 1:200), tileOne);

            % Where tile 4 overlaps only one earlier neighbour, that neighbour
            % wins - as the corrected pixels the whole pipeline reads.
            correctedReader = utils.stitch.makeTileReader(layout, struct('correction', correction));
            tileTwo   = correctedReader(2);
            tileThree = correctedReader(3);
            testCase.verifyEqual(mosaic(201:350, 151:200), tileThree(51:200, 151:200), ...
                'tiles 3 and 4 only: tile 3 was imaged first');
            testCase.verifyEqual(mosaic(151:200, 201:350), tileTwo(151:200, 51:200), ...
                'tiles 2 and 4 only: tile 2 was imaged first');
        end

        function reexposure_cropMatchesTheFullTile(testCase)
            % A cropped read builds the strength map for its own region only; it
            % has to agree with the same pixels taken from a full read.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            [tileFiles, truePositions] = writeReexposedTiles(tmpDir.Folder, 200, 150, 1.12, -30);
            layout = utils.stitch.buildLayoutGrid(tileFiles, ...
                struct('rows', 2, 'cols', 2, 'tileOrder', 'Horizontal', ...
                       'overlapX', 25, 'overlapY', 25));
            correction = utils.stitch.estimateIntensityCorrection(layout, ...
                reexposureOptions(truePositions));

            fullReader = utils.stitch.makeTileReader(layout, struct('correction', correction));
            fullTile = fullReader(4);
            pixelRegion = [20 90; 30 120];   % straddles two footprint edges and the corner
            cropReader = utils.stitch.makeTileReader(layout, struct('correction', correction));
            testCase.verifyEqual(cropReader(4, pixelRegion), ...
                fullTile(pixelRegion(1,1):pixelRegion(1,2), pixelRegion(2,1):pixelRegion(2,2), :, :));
        end

        function reexposure_undamagedTilesAreLeftAlone(testCase)
            % Without any darkening there is nothing to correct: the method must
            % say so and change no pixel, rather than fit noise.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            [tileFiles, truePositions] = writeReexposedTiles(tmpDir.Folder, 200, 150, 1, 0);
            layout = utils.stitch.buildLayoutGrid(tileFiles, ...
                struct('rows', 2, 'cols', 2, 'tileOrder', 'Horizontal', ...
                       'overlapX', 25, 'overlapY', 25));

            correction = testCase.verifyWarning(@() utils.stitch.estimateIntensityCorrection( ...
                layout, reexposureOptions(truePositions)), ...
                'utils:stitch:estimateIntensityCorrection:noReexposureDamage');
            testCase.verifyEmpty(correction.damage.footprints);
            plainReader = utils.stitch.makeTileReader(layout);
            neutralReader = utils.stitch.makeTileReader(layout, struct('correction', correction));
            testCase.verifyEqual(neutralReader(4), plainReader(4));
        end

        function reexposure_needsPositions(testCase)
            % Nominal positions can be off by many pixels, and the edges this
            % corrects are sharp - so it refuses rather than guess.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tileFiles = writeReexposedTiles(tmpDir.Folder, 200, 150, 1.12, -30);
            layout = utils.stitch.buildLayoutGrid(tileFiles, ...
                struct('rows', 2, 'cols', 2, 'tileOrder', 'Horizontal', ...
                       'overlapX', 25, 'overlapY', 25));
            correction = testCase.verifyWarning(@() utils.stitch.estimateIntensityCorrection( ...
                layout, struct('method', 'Re-exposure damage')), ...
                'utils:stitch:estimateIntensityCorrection:needsPositions');
            testCase.verifyEqual(correction.method, 'None');
        end

        function reexposure_smallMoveKeepsTheModel(testCase)
            % A re-solve moves tiles by a pixel or two; the fitted model stays
            % and only the footprints follow - no pixel is read for it.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            [tileFiles, truePositions] = writeReexposedTiles(tmpDir.Folder, 200, 150, 1.12, -30);
            layout = utils.stitch.buildLayoutGrid(tileFiles, ...
                struct('rows', 2, 'cols', 2, 'tileOrder', 'Horizontal', ...
                       'overlapX', 25, 'overlapY', 25));
            first = utils.stitch.estimateIntensityCorrection(layout, reexposureOptions(truePositions));

            moved = truePositions;
            moved(4, :) = moved(4, :) + [2 -1];
            options = reexposureOptions(moved);
            options.previous = first;
            % Point the layout at files that do not exist: a pixel read would fail.
            missingLayout = layout;
            for tileIdx = 1:numel(missingLayout)
                missingLayout(tileIdx).filename = fullfile(tmpDir.Folder, 'gone', sprintf('%d.png', tileIdx));
            end
            second = utils.stitch.estimateIntensityCorrection(missingLayout, options);

            testCase.verifyEqual(second.damage.profiles, first.damage.profiles);
            testCase.verifyEqual(second.damage.gain, first.damage.gain);
            testCase.verifyEqual(second.damage.positions, moved);
            firstRow  = first.damage.footprints(first.damage.footprints(:, 1) == 4, :);
            secondRow = second.damage.footprints(second.damage.footprints(:, 1) == 4, :);
            testCase.verifyEqual(sortrows(secondRow), sortrows(firstRow - [0 2 2 -1 -1]), ...
                'moving tile 4 must shift every earlier footprint the opposite way in its frame');
        end

        function mdocMissingContainerIsReported(testCase)
            % A montage is two files; without the image there is nothing to read.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            montage = mibtest.helpers.makeMdocMontage(tmpDir.Folder);
            delete(montage.imagePath);

            testCase.verifyError(@() utils.stitch.buildLayoutMdoc(montage.mdocPath), ...
                'utils:stitch:buildLayoutMdoc:imageNotFound');
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
function [truthField, tileFiles] = writeShadedTiles(folderPath, numTiles, tileSize, fieldSpan)
% WRITESHADEDTILES - Independent-content tiles sharing ONE illumination field.
%
% The configuration the shared-field estimator assumes: every tile shows different
% specimen (so content averages out) under the same illumination (so the field
% does not). `fieldSpan` is the field's peak-to-peak fraction.
[fieldXX, fieldYY] = meshgrid(linspace(-1, 1, tileSize), linspace(-1, 1, tileSize));
% Diagonal AND curved, so a transpose or a flip cannot pass unnoticed.
truthField = 1 + fieldSpan * (0.35 * fieldXX + 0.25 * fieldYY - 0.20 * (fieldXX.^2 - fieldYY.^2));
truthField = truthField / mean(truthField(:));

tileFiles = cell(numTiles, 1);
for tileIdx = 1:numTiles
    rng(1000 + tileIdx, 'twister');   % independent content per tile
    content = imfilter(randn(tileSize), fspecial('gaussian', [9 9], 2.0), 'replicate');
    content = 128 + 26 * content / std(content(:));
    tileFiles{tileIdx} = fullfile(folderPath, sprintf('shaded_%02d.png', tileIdx));
    imwrite(uint8(min(255, max(0, content .* truthField))), tileFiles{tileIdx});
end
end

% =========================================================================
function [truthField, tileFiles, truePositions] = writeOverlappingShadedTiles( ...
    folderPath, tileSize, stepPx, gridSize, fieldSpan, specimenRamp)
% WRITEOVERLAPPINGSHADEDTILES - Overlapping tiles cut from ONE canvas that itself
% has a broad brightness trend, each then shaded by the SAME illumination field.
%
% This is the configuration that separates the two flat-field methods: the
% canvas-wide ramp is specimen, not illumination, but a method that only averages
% the tiles has no way to know that. `specimenRamp` is its peak-to-peak fraction,
% `fieldSpan` the illumination field's.
canvasSize = tileSize + (gridSize - 1) * stepPx;
rng(4242, 'twister');
content = imfilter(randn(canvasSize), fspecial('gaussian', [9 9], 2.0), 'replicate');
content = content / std(content(:));
[rampXX, rampYY] = meshgrid(linspace(0, 1, canvasSize), linspace(0, 1, canvasSize));
% A trend belonging to the SAMPLE, spanning the whole mosaic.
canvas = 128 * (1 + specimenRamp * (0.6 * rampXX + 0.4 * rampYY - 0.5)) + 22 * content;

[fieldXX, fieldYY] = meshgrid(linspace(-1, 1, tileSize), linspace(-1, 1, tileSize));
truthField = 1 + fieldSpan * (0.35 * fieldXX + 0.25 * fieldYY - 0.20 * (fieldXX.^2 - fieldYY.^2));
truthField = truthField / mean(truthField(:));

numTiles = gridSize * gridSize;
tileFiles = cell(numTiles, 1);
truePositions = zeros(numTiles, 2);
tileIdx = 0;
for rowIdx = 1:gridSize
    for colIdx = 1:gridSize
        tileIdx = tileIdx + 1;
        topRow  = (rowIdx - 1) * stepPx + 1;
        leftCol = (colIdx - 1) * stepPx + 1;
        truePositions(tileIdx, :) = [topRow, leftCol];
        patch = canvas(topRow:topRow + tileSize - 1, leftCol:leftCol + tileSize - 1);
        tileFiles{tileIdx} = fullfile(folderPath, sprintf('overlap_%02d.png', tileIdx));
        imwrite(uint8(min(255, max(0, patch .* truthField))), tileFiles{tileIdx});
    end
end
end

% =========================================================================
function options = reexposureOptions(positions)
% REEXPOSUREOPTIONS - Re-exposure estimator settings scaled to 200 px test tiles.
% The defaults (150 px reach, 25 px guard) are sized for real 4k - 24k tiles.
options = struct('method', 'Re-exposure damage', 'positions', positions, ...
    'damageReach', 30, 'damageFarWidth', 10, 'edgeGuard', 4);
end

% =========================================================================
function [tileFiles, truePositions, truthTiles] = writeReexposedTiles(folderPath, ...
    tileSize, stepPx, damageGain, damageOffset)
% WRITEREEXPOSEDTILES - A 2x2 raster whose later tiles are darkened where the
% earlier ones already scanned.
%
% Tiles are cut from ONE texture, so the undamaged truth of every pixel is known.
% Acquisition order is the raster order 1, 2, 3, 4; tile t is damaged by every
% earlier tile whose footprint touches it, diagonals included, so tile 4's corner
% under tiles 1, 2 and 3 carries three exposures. Each footprint contributes a
% separable strength - 1 inside, a ridge of 1.5 decaying over ~6 px outside -
% and the damage is ``truth + S * ((gain - 1) * truth + offset)``. With gain 1
% and offset 0 the tiles are clean.
canvasSize = tileSize + stepPx;
rng(5150, 'twister');
content = imfilter(randn(canvasSize), fspecial('gaussian', [15 15], 3), 'replicate');
[rampXX, rampYY] = meshgrid(linspace(-1, 1, canvasSize));
canvas = 125 + 25 * content / std(content(:)) + 8 * (rampXX - 0.5 * rampYY);
% Kept well inside uint8 even after the damage, so the truth is representable.
canvas = min(220, max(30, canvas));

truePositions = [1 1; 1 1 + stepPx; 1 + stepPx 1; 1 + stepPx 1 + stepPx];
profile = @(d) (d < 0) + (d >= 0) .* 1.5 .* exp(-d / 6);
tileFiles  = cell(4, 1);
truthTiles = cell(4, 1);
coords = (1:tileSize)';
for tileIdx = 1:4
    truth = canvas(truePositions(tileIdx, 1) + (0:tileSize - 1), ...
                   truePositions(tileIdx, 2) + (0:tileSize - 1));
    strength = zeros(tileSize);
    for earlierIdx = 1:tileIdx - 1
        rowMin = truePositions(earlierIdx, 1) - truePositions(tileIdx, 1) + 1;
        colMin = truePositions(earlierIdx, 2) - truePositions(tileIdx, 2) + 1;
        rowDistance = max((rowMin - 0.5) - coords, coords - (rowMin + tileSize - 1 + 0.5));
        colDistance = max((colMin - 0.5) - coords, coords - (colMin + tileSize - 1 + 0.5));
        strength = strength + profile(rowDistance) * profile(colDistance)';
    end
    observed = truth + strength .* ((damageGain - 1) * truth + damageOffset);
    truthTiles{tileIdx} = truth;
    tileFiles{tileIdx} = fullfile(folderPath, sprintf('reexposed_%02d.png', tileIdx));
    imwrite(uint8(min(255, max(0, observed))), tileFiles{tileIdx});
end
end

% =========================================================================
function worstMismatch = seamBrightnessMismatch(layout, positions, correction)
% SEAMBRIGHTNESSMISMATCH - Largest |brightness step| across any seam, in percent.
% The quantity a user sees at a tile boundary, and the one every correction
% method is ultimately judged on.
readerOptions = struct();
if ~isempty(correction); readerOptions.correction = correction; end
readerFcn = utils.stitch.makeTileReader(layout, readerOptions);
tileHeight = layout(1).tileSize(1);
tileWidth  = layout(1).tileSize(2);

worstMismatch = 0;
for tileI = 1:numel(layout) - 1
    for tileJ = tileI + 1:numel(layout)
        overlapRows = tileHeight - abs(positions(tileI,1) - positions(tileJ,1));
        overlapCols = tileWidth  - abs(positions(tileI,2) - positions(tileJ,2));
        if overlapRows < 8 || overlapCols < 8; continue; end
        rowStart = max(positions(tileI,1), positions(tileJ,1));
        rowEnd   = min(positions(tileI,1), positions(tileJ,1)) + tileHeight - 1;
        colStart = max(positions(tileI,2), positions(tileJ,2));
        colEnd   = min(positions(tileI,2), positions(tileJ,2)) + tileWidth - 1;
        cropI = single(readerFcn(tileI, [rowStart-positions(tileI,1)+1, rowEnd-positions(tileI,1)+1; ...
                                         colStart-positions(tileI,2)+1, colEnd-positions(tileI,2)+1]));
        cropJ = single(readerFcn(tileJ, [rowStart-positions(tileJ,1)+1, rowEnd-positions(tileJ,1)+1; ...
                                         colStart-positions(tileJ,2)+1, colEnd-positions(tileJ,2)+1]));
        worstMismatch = max(worstMismatch, ...
            abs(100 * (mean(cropI(:)) / mean(cropJ(:)) - 1)));
    end
end
end

% =========================================================================
function strength = mosaicPlaneStrength(layout, positions, correction)
% MOSAICPLANESTRENGTH - How strongly the CORRECTED mosaic shades across itself.
%
% Fitted on the corrected tile means against tile position, which is the same
% quantity the eye reads as "one side of the montage is darker". Deliberately
% not a seam measurement: a mosaic can shade from end to end while every
% individual seam matches perfectly, and that combination is exactly the artefact
% this exists to catch.
readerOptions = struct();
if ~isempty(correction); readerOptions.correction = correction; end
readerFcn = utils.stitch.makeTileReader(layout, readerOptions);
tileHeight = layout(1).tileSize(1);
tileWidth  = layout(1).tileSize(2);

numTiles = numel(layout);
logMeans = zeros(numTiles, 1);
for tileIdx = 1:numTiles
    logMeans(tileIdx) = log(double(mean(single(readerFcn(tileIdx)), 'all')));
end
centres = [(positions(:,2) + (tileWidth-1)/2) / (tileWidth/2), ...
           (positions(:,1) + (tileHeight-1)/2) / (tileHeight/2)];
coefficients = [ones(numTiles,1), centres] \ logMeans;
strength = norm(coefficients(2:3));
end

% =========================================================================
function spread = normalizedTileAverageSpread(readerFcn, numTiles)
% NORMALIZEDTILEAVERAGESPREAD - Peak-to-peak of what the tiles have IN COMMON.
%
% Each tile is normalised by its own mean and the tiles are averaged, so
% independent specimen content cancels and only the shared illumination survives.
% This is the quantity a flat-field correction exists to flatten - and, unlike a
% single tile, it is not swamped by that tile's own texture.
accumulated = [];
for tileIdx = 1:numTiles
    tilePixels = single(readerFcn(tileIdx));
    tilePixels = mean(reshape(tilePixels, size(tilePixels, 1), size(tilePixels, 2), []), 3);
    tilePixels = tilePixels / mean(tilePixels(:));
    if isempty(accumulated); accumulated = tilePixels; else; accumulated = accumulated + tilePixels; end
end
accumulated = accumulated / numTiles;
accumulated = imgaussfilt(accumulated, 4, 'Padding', 'replicate');
spread = double(max(accumulated(:)) - min(accumulated(:))) / double(mean(accumulated(:)));
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
