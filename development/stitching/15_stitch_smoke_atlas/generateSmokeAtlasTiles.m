function generateSmokeAtlasTiles()
% GENERATESMOKEATLASTILES - A Fibics Atlas mosaic folder: tiles + .ve-mif/.ve-tie/.ve-updates.
%
% Creates a 3x3 mosaic in the shape Atlas leaves on disk, so the
% "Position file" layout source can be exercised on Atlas data without proprietary
% data. All three XML files are written, reproducing the format's real traps:
%
%   - tile paths recorded as the ACQUISITION machine's absolute paths (``E:\...``),
%     so a reader that trusts them finds nothing;
%   - a second, unrelated ``<PixelSize>`` nested in the autofocus block, and a
%     second ``<ParentTransform>`` nested in ``<DefaultAlignment>``;
%   - tiles listed in Atlas's SNAKE acquisition order, not row-major;
%   - stage Y running UP, so row 2 sits at a SMALLER stage Y than row 1.
%
% **The nominal stage grid is deliberately wrong.** As on real Atlas data, the
% recorded Y step is longer than the truth (here by 8 px) while X is accurate to
% about a pixel - the failure this layout source exists to cope with. The
% ``.ve-tie`` and ``.ve-updates`` files describe the CORRECT placement, so:
%
%   Nominal grid only              -> visible seam steps until MIB re-measures
%   Atlas seam measurements        -> MIB solves to the truth without registering
%   Atlas seams + solved positions -> already correct; Stitch fuses as it stands
%
% Outputs (in <repoRoot>\temp\stitching_test\15_stitch_smoke_atlas):
%   Tile_r#-c#_SMOKE.tif          - the 9 tiles
%   MosaicInfo_SMOKE.ve-mif       - acquisition record (nominal stage grid)
%   MosaicInfo_SMOKE.ve-tie       - pairwise seam measurements (correct)
%   MosaicInfo_SMOKE.ve-updates   - final solved placement (correct)
%   trueOrigins.mat               - trueOrigins 9x2 [y x] true cut origins
%
% Load in MIB (smoke_tests.md test 15):
%   Stitch ribbon -> Layout source = "Position file"
%   -> Browse (pick MosaicInfo_SMOKE.ve-mif) -> answer the import dialog.

repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
outputFolder = fullfile(repoRoot, 'temp', 'stitching_test', '15_stitch_smoke_atlas');
if ~isfolder(outputFolder); mkdir(outputFolder); end

numRows = 3;
numCols = 3;
tileSize = 240;
trueStepX = 180;            % 25% overlap - what the pixels actually show
trueStepY = 180;
nominalErrorYpx = 8;        % the .ve-mif Y step is this much too long
nominalErrorXpx = 1;
pixelSizeUm = 0.5;
fovUm = tileSize * pixelSizeUm;
stageOriginXum = -49462.9;  % arbitrary absolute stage position, as Atlas records
stageOriginYum = -45614.4;

canvasH = tileSize + (numRows - 1) * trueStepY;
canvasW = tileSize + (numCols - 1) * trueStepX;

% ---- Ground truth: texture + lines + circles, so a bad seam is visible ----
rng(15, 'twister');
pixelNoise    = randn(canvasH, canvasW);
fineTexture   = imfilter(randn(canvasH, canvasW), fspecial('gaussian', [7 7], 1.2), 'replicate');
coarseTexture = imfilter(randn(canvasH, canvasW), fspecial('gaussian', [21 21], 4.0), 'replicate');
pixelNoise    = pixelNoise / std(pixelNoise(:));
fineTexture   = fineTexture / std(fineTexture(:));
coarseTexture = coarseTexture / std(coarseTexture(:));
background = 0.25 * pixelNoise + 0.35 * fineTexture + 0.40 * coarseTexture;
background = (background - min(background(:))) / (max(background(:)) - min(background(:)));
[xx, yy] = meshgrid(1:canvasW, 1:canvasH);
img = 0.60 * background + 0.12 * (xx / canvasW) + 0.08 * (yy / canvasH) + 0.10;

lineHalfWidth = 1.3;
lineOpacity = 0.45;
for lineIdx = 1:20
    theta = rand() * pi;
    rho   = rand() * hypot(canvasH, canvasW) * 0.9;
    lineMask = abs(xx * cos(theta) + yy * sin(theta) - rho) < lineHalfWidth;
    if mod(lineIdx, 2) == 0
        img(lineMask) = img(lineMask) * (1 - lineOpacity) + lineOpacity;
    else
        img(lineMask) = img(lineMask) * (1 - lineOpacity);
    end
end
circleSpec = [180 200 120; 460 430 150; 300 540 90; 520 150 80];   % [cy cx radius]
for circleIdx = 1:size(circleSpec, 1)
    circleMask = abs(hypot(xx - circleSpec(circleIdx, 2), ...
                           yy - circleSpec(circleIdx, 1)) - circleSpec(circleIdx, 3)) < lineHalfWidth;
    img(circleMask) = img(circleMask) * (1 - lineOpacity) + lineOpacity;
end
groundTruth = uint8(255 * max(min(img, 1), 0));

% ---- Cut the tiles at the TRUE offsets, in Atlas's snake acquisition order ----
gridRowCol = zeros(numRows * numCols, 2);
tileIdx = 0;
for row = 1:numRows
    columnOrder = 1:numCols;
    if mod(row, 2) == 0; columnOrder = fliplr(columnOrder); end   % snake
    for col = columnOrder
        tileIdx = tileIdx + 1;
        gridRowCol(tileIdx, :) = [row, col];
    end
end
numTiles = size(gridRowCol, 1);

tileNames   = cell(numTiles, 1);
trueOrigins = zeros(numTiles, 2);
for tileIdx = 1:numTiles
    row = gridRowCol(tileIdx, 1);
    col = gridRowCol(tileIdx, 2);
    originY = 1 + (row - 1) * trueStepY;
    originX = 1 + (col - 1) * trueStepX;
    trueOrigins(tileIdx, :) = [originY, originX];
    tileNames{tileIdx} = sprintf('Tile_r%d-c%d_SMOKE', row, col);
    imwrite(groundTruth(originY:originY + tileSize - 1, originX:originX + tileSize - 1), ...
        fullfile(outputFolder, [tileNames{tileIdx}, '.tif']));
end
recordedPath = @(name) ['E:\acquired\session\SMOKE\', name, '.tif'];

% ---- Nominal (wrong) stage grid, in micrometres with Y running UP ----
nominalStepXum = (trueStepX + nominalErrorXpx) * pixelSizeUm;
nominalStepYum = (trueStepY + nominalErrorYpx) * pixelSizeUm;
stageXum = stageOriginXum + (gridRowCol(:, 2) - 1) * nominalStepXum;
stageYum = stageOriginYum - (gridRowCol(:, 1) - 1) * nominalStepYum;

xmlLines = {'<?xml version="1.0" encoding="iso-8859-1"?>'};
xmlLines{end+1} = '<MosaicInfo ID="15"><Application>Atlas Engine v5.5.6</Application>';
xmlLines{end+1} = '<ReferenceInfo><Name>SMOKE</Name></ReferenceInfo>';
xmlLines{end+1} = sprintf('<PixelSize unit="nm">%g</PixelSize>', pixelSizeUm * 1000);
xmlLines{end+1} = sprintf(['<TileInfo><FOV unit="um">%g</FOV><TileWidth>%d</TileWidth>' ...
    '<TileHeight>%d</TileHeight><TileOverlapXum>%g</TileOverlapXum>' ...
    '<TileOverlapYum>%g</TileOverlapYum><NumTilesX>%d</NumTilesX><NumTilesY>%d</NumTilesY>' ...
    '<AutoTune><AutoStigAndFocus><FOV>1536</FOV><PixelSize>1.5</PixelSize>' ...
    '</AutoStigAndFocus></AutoTune></TileInfo>'], ...
    fovUm, tileSize, tileSize, fovUm - nominalStepXum, fovUm - nominalStepYum, numCols, numRows);
xmlLines{end+1} = '<Tiles>';
for tileIdx = 1:numTiles
    xmlLines{end+1} = sprintf(['<Tile row="%d" col="%d"><TargetStageX>%.6f</TargetStageX>' ...
        '<TargetStageY>%.6f</TargetStageY><StageX>%.6f</StageX><StageY>%.6f</StageY>' ...
        '<Detector>BSD1</Detector><Filename>%s</Filename></Tile>'], ...
        gridRowCol(tileIdx, 1), gridRowCol(tileIdx, 2), ...
        stageXum(tileIdx), stageYum(tileIdx), stageXum(tileIdx), stageYum(tileIdx), ...
        recordedPath(tileNames{tileIdx})); %#ok<AGROW>
end
xmlLines{end+1} = '</Tiles><Status>completed</Status></MosaicInfo>';
writeTextFile(fullfile(outputFolder, 'MosaicInfo_SMOKE.ve-mif'), xmlLines);

% ---- .ve-tie: the CORRECT seam measurements ----
% offset(i->j) = Image1Position - Image2Position + Shift, in the stage frame.
% The position terms alone reproduce the NOMINAL step, so Shift carries the
% correction back to the truth.
correctionXum = -nominalErrorXpx * pixelSizeUm;
correctionYum = -nominalErrorYpx * pixelSizeUm;
tileOfGridCell = zeros(numRows, numCols);
for tileIdx = 1:numTiles
    tileOfGridCell(gridRowCol(tileIdx, 1), gridRowCol(tileIdx, 2)) = tileIdx;
end

xmlLines = {'<?xml version="1.0" encoding="utf-8"?>', '<F-ATLAS-Image-Ties><Ties>'};
for row = 1:numRows
    for col = 1:numCols
        if col < numCols      % horizontal seam
            xmlLines{end+1} = atlasTieXml( ...
                tileOfGridCell(row, col), tileOfGridCell(row, col + 1), ...
                [ nominalStepXum / 2, 0], [-nominalStepXum / 2, 0], [correctionXum, 0], ...
                0.94, tileNames, recordedPath); %#ok<AGROW>
        end
        if row < numRows      % vertical seam (stage Y up: the strip is BELOW tile 1)
            xmlLines{end+1} = atlasTieXml( ...
                tileOfGridCell(row, col), tileOfGridCell(row + 1, col), ...
                [0, -nominalStepYum / 2], [0, nominalStepYum / 2], [0, -correctionYum], ...
                0.97, tileNames, recordedPath); %#ok<AGROW>
        end
    end
end
xmlLines{end+1} = ['</Ties><ConfidenceThreshold>0.820000</ConfidenceThreshold>' ...
    '<PerTileRotation>false</PerTileRotation><PerTileScale>false</PerTileScale>' ...
    '</F-ATLAS-Image-Ties>'];
writeTextFile(fullfile(outputFolder, 'MosaicInfo_SMOKE.ve-tie'), xmlLines);

% ---- .ve-updates: the CORRECT solved placement ----
xmlLines = {'<?xml version="1.0" encoding="utf-8"?>', '<ATLAS-Stitch-Info>'};
xmlLines{end+1} = sprintf('<OriginalRoot>%s</OriginalRoot>', 'E:\acquired\session\SMOKE\');
for tileIdx = 1:numTiles
    solvedXum =  (gridRowCol(tileIdx, 2) - 1) * trueStepX * pixelSizeUm;
    solvedYum = -(gridRowCol(tileIdx, 1) - 1) * trueStepY * pixelSizeUm;
    xmlLines{end+1} = sprintf([ ...
        '<Tile><Name>%s</Name>' ...
        '<ParentTransform><M11>%g</M11><M12>0</M12><M21>0</M21><M22>%g</M22>' ...
        '<M41>%.6f</M41><M42>%.6f</M42>' ...
        '<CenterLocalX>0.5</CenterLocalX><CenterLocalY>0.5</CenterLocalY></ParentTransform>' ...
        '<IsVisible>true</IsVisible>' ...
        '<DefaultAlignment><ParentTransform><M11>1</M11><M22>1</M22>' ...
        '<M41>-0.5</M41><M42>-0.5</M42></ParentTransform></DefaultAlignment>' ...
        '<FileName>%s</FileName><Width>%d</Width><Height>%d</Height></Tile>'], ...
        tileNames{tileIdx}, fovUm, fovUm, solvedXum, solvedYum, ...
        recordedPath(tileNames{tileIdx}), tileSize, tileSize); %#ok<AGROW>
end
xmlLines{end+1} = '</ATLAS-Stitch-Info>';
writeTextFile(fullfile(outputFolder, 'MosaicInfo_SMOKE.ve-updates'), xmlLines);

save(fullfile(outputFolder, 'trueOrigins.mat'), 'trueOrigins', 'gridRowCol');
fprintf(['Generated a %dx%d Fibics Atlas mosaic (%dx%d px tiles, true step %d px) in %s\n' ...
         'The .ve-mif stage grid is deliberately %d px too long in Y (%d px in X);\n' ...
         'the .ve-tie / .ve-updates describe the correct placement.\n'], ...
    numRows, numCols, tileSize, tileSize, trueStepX, outputFolder, ...
    nominalErrorYpx, nominalErrorXpx);
end

% =========================================================================
function tieXml = atlasTieXml(tileI, tileJ, position1, position2, shiftUm, confidence, tileNames, recordedPath)
% ATLASTIEXML - One <Tie> element. Indices are 0-based into the <Tiles> listing.
tieXml = sprintf([ ...
    '<Tie><Size><X>0</X><Y>0</Y></Size>' ...
    '<Image1Position><X>%.6f</X><Y>%.6f</Y></Image1Position>' ...
    '<Image2Position><X>%.6f</X><Y>%.6f</Y></Image2Position>' ...
    '<Shift><X>%.6f</X><Y>%.6f</Y></Shift>' ...
    '<Image1Index>%d</Image1Index><Image2Index>%d</Image2Index>' ...
    '<Overlap>true</Overlap><Confidence>%.6f</Confidence><User>false</User>' ...
    '<Image1FileName>%s</Image1FileName><Image2FileName>%s</Image2FileName></Tie>'], ...
    position1, position2, shiftUm, tileI - 1, tileJ - 1, confidence, ...
    recordedPath(tileNames{tileI}), recordedPath(tileNames{tileJ}));
end

% =========================================================================
function writeTextFile(filePath, lines)
% WRITETEXTFILE - Write a cell array of lines as a plain text file.
fileId = fopen(filePath, 'w');
fprintf(fileId, '%s\n', lines{:});
fclose(fileId);
end
