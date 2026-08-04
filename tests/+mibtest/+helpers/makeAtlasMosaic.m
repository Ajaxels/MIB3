function mosaic = makeAtlasMosaic(folderPath, options)
% MAKEATLASMOSAIC - Write a synthetic Fibics Atlas 2x2 mosaic into a folder.
%
% Syntax:
%   .. code-block:: matlab
%
%      mosaic = mibtest.helpers.makeAtlasMosaic(folderPath)
%      mosaic = mibtest.helpers.makeAtlasMosaic(folderPath, options)
%
% Produces the four tile images plus the three XML files an Atlas acquisition
% leaves beside them, reproducing the format's traps rather than an idealised
% version of it:
%
%   - tile paths recorded as the ACQUISITION machine's absolute paths, so a
%     reader that trusts them finds nothing;
%   - a second, unrelated ``<PixelSize>`` nested in the autofocus block;
%   - a second ``<ParentTransform>`` nested in ``<DefaultAlignment>``;
%   - tiles listed in Atlas's snake acquisition order (r1c1, r1c2, r2c2, r2c1),
%     not in row-major order;
%   - stage Y running UP, so row 2 sits at a SMALLER stage Y than row 1.
%
% Geometry: 64 px tiles at 0.5 µm/px (32 µm FOV) on a 22 µm step (44 px, leaving
% 20 px of overlap). Every seam carries a measured correction — 4 px in X, 6 px
% in Y, deliberately different so an axis swap cannot pass unnoticed — so the
% ties measure 40 px / 38 px where the nominal grid says 44 px.
%
% The tiles are CUT FROM ONE TEXTURED IMAGE at those measured offsets, which is
% what makes the mosaic testable end to end: the ``.ve-tie`` / ``.ve-updates``
% placement is the pixel-correct one (seams score ~1), while the nominal stage
% grid is wrong by 4-6 px — the same shape of error that makes Atlas's rough
% placement unusable on real data.
%
% Input Arguments:
%   - **folderPath** — [char] folder to write into; created when absent.
%   - **options** *(optional)* — struct with fields:
%
%     - ``.writeTies`` — [logical] write the ``.ve-tie`` file (default: ``true``)
%     - ``.writeUpdates`` — [logical] write the ``.ve-updates`` file (default: ``true``)
%     - ``.mirrorStageX`` — [logical] make stage X run opposite to the column
%       index, for testing the derived axis signs (default: ``false``)
%     - ``.confidences`` — [1x4 double] per-tie ``<Confidence>`` values
%       (default: ``[0.96 0.98 0.95 0.86]``)
%     - ``.confidenceThreshold`` — [double] the file's own
%       ``<ConfidenceThreshold>`` (default: ``0.82``)
%     - ``.userTies`` — [1x4 logical] per-tie ``<User>`` flag (default: all false)
%     - ``.textureSeed`` — [double] seed for the source texture (default: ``77``)
%
% Output Arguments:
%   - **mosaic** — struct with ``.folder``, ``.veMifPath``, ``.tileNames``,
%     ``.pixelSizeUm``, ``.stepPx``, ``.measuredStepXpx``, ``.measuredStepYpx``.
%
% **Example** — a mosaic Atlas never stitched:
%
%   .. code-block:: matlab
%
%      mosaic = mibtest.helpers.makeAtlasMosaic(tempFolder, ...
%          struct('writeTies', false, 'writeUpdates', false));
%      layout = utils.stitch.buildLayoutAtlas(mosaic.veMifPath);
%
% See also utils.stitch.buildLayoutAtlas, utils.stitch.findAtlasSidecars

arguments
    folderPath (1,:) char
    options    struct = struct()
end

if ~isfield(options, 'writeTies');           options.writeTies = true; end
if ~isfield(options, 'writeUpdates');        options.writeUpdates = true; end
if ~isfield(options, 'mirrorStageX');        options.mirrorStageX = false; end
if ~isfield(options, 'confidences');         options.confidences = [0.96 0.98 0.95 0.86]; end
if ~isfield(options, 'confidenceThreshold'); options.confidenceThreshold = 0.82; end
if ~isfield(options, 'userTies');            options.userTies = false(1, 4); end
if ~isfield(options, 'textureSeed');         options.textureSeed = 77; end

if ~isfolder(folderPath); mkdir(folderPath); end

pixelSizeUm   = 0.5;
fovUm         = 32;      % 64 px tiles
tileSizePx    = 64;
stepUm        = 22;      % 44 px, leaving 20 px of overlap
correctionXum = -2;      % -4 px on every horizontal seam
correctionYum = -3;      % -6 px on every vertical seam
stageOriginX  = -49462.9;
stageOriginY  = -45614.4;
stageXSign    = 1;
if options.mirrorStageX; stageXSign = -1; end

% True (measured) steps in pixels — what the ties and the solved placement state.
measuredStepXpx = (stepUm + correctionXum) / pixelSizeUm;
measuredStepYpx = (stepUm + correctionYum) / pixelSizeUm;

% ---- Tiles cut from one texture at the TRUE offsets, written in Atlas's
%      snake acquisition order (r1c1, r1c2, r2c2, r2c1) ----
gridRowCol = [1 1; 1 2; 2 2; 2 1];
numTiles   = size(gridRowCol, 1);
sourceImage = mibtest.helpers.stitchTextureImage( ...
    tileSizePx + measuredStepYpx, tileSizePx + measuredStepXpx, options.textureSeed);
tileNames = cell(numTiles, 1);
for tileIdx = 1:numTiles
    tileNames{tileIdx} = sprintf('Tile_r%d-c%d_SYN', gridRowCol(tileIdx, 1), gridRowCol(tileIdx, 2));
    topRow  = (gridRowCol(tileIdx, 1) - 1) * measuredStepYpx + 1;
    leftCol = (gridRowCol(tileIdx, 2) - 1) * measuredStepXpx + 1;
    imwrite(sourceImage(topRow:topRow + tileSizePx - 1, leftCol:leftCol + tileSizePx - 1), ...
        fullfile(folderPath, [tileNames{tileIdx}, '.png']));
end
recordedPath = @(name) ['E:\acquired\session\SYN\', name, '.png'];

stageXum = zeros(numTiles, 1);
stageYum = zeros(numTiles, 1);
for tileIdx = 1:numTiles
    stageXum(tileIdx) = stageOriginX + stageXSign * (gridRowCol(tileIdx, 2) - 1) * stepUm;
    stageYum(tileIdx) = stageOriginY - (gridRowCol(tileIdx, 1) - 1) * stepUm;
end

% ---- .ve-mif — the acquisition record ----
xmlLines = {'<?xml version="1.0" encoding="iso-8859-1"?>'};
xmlLines{end+1} = '<MosaicInfo ID="1"><Application>Atlas Engine v5.5.6</Application>';
xmlLines{end+1} = '<ReferenceInfo><Name>SYN</Name></ReferenceInfo>';
xmlLines{end+1} = sprintf('<PixelSize unit="nm">%g</PixelSize>', pixelSizeUm * 1000);
xmlLines{end+1} = sprintf(['<TileInfo><FOV unit="um">%g</FOV><TileWidth>64</TileWidth>' ...
    '<TileHeight>64</TileHeight><TileOverlapXum>10</TileOverlapXum>' ...
    '<TileOverlapYum>10</TileOverlapYum><NumTilesX>2</NumTilesX><NumTilesY>2</NumTilesY>' ...
    '<AutoTune><AutoStigAndFocus><FOV>1536</FOV><PixelSize>1.5</PixelSize>' ...
    '</AutoStigAndFocus></AutoTune></TileInfo>'], fovUm);
xmlLines{end+1} = '<Tiles>';
for tileIdx = 1:numTiles
    xmlLines{end+1} = sprintf(['<Tile row="%d" col="%d"><TargetStageX>%.6f</TargetStageX>' ...
        '<TargetStageY>%.6f</TargetStageY><StageX>%.6f</StageX><StageY>%.6f</StageY>' ...
        '<Filename>%s</Filename></Tile>'], ...
        gridRowCol(tileIdx, 1), gridRowCol(tileIdx, 2), ...
        stageXum(tileIdx), stageYum(tileIdx), stageXum(tileIdx), stageYum(tileIdx), ...
        recordedPath(tileNames{tileIdx})); %#ok<AGROW>
end
xmlLines{end+1} = '</Tiles><Status>completed</Status></MosaicInfo>';
veMifPath = fullfile(folderPath, 'MosaicInfo_SYN.ve-mif');
writeTextFile(veMifPath, xmlLines);

% ---- .ve-tie — the four seams of a 2x2, indexed into the <Tiles> listing ----
tiePairs        = [0 1; 1 2; 0 3; 3 2];   % r1c1-r1c2, r1c2-r2c2, r1c1-r2c1, r2c1-r2c2
tieIsHorizontal = [true; false; false; true];
if options.writeTies
    halfStepUm = stepUm / 2;
    xmlLines = {'<?xml version="1.0" encoding="utf-8"?>', '<F-ATLAS-Image-Ties><Ties>'};
    for tieIdx = 1:size(tiePairs, 1)
        if tieIsHorizontal(tieIdx)
            position1 = [ halfStepUm, 0];      % strip on the RIGHT of the left tile
            position2 = [-halfStepUm, 0];
            shiftUm   = [correctionXum, 0];
        else
            position1 = [0, -halfStepUm];      % strip at the BOTTOM of the upper tile
            position2 = [0,  halfStepUm];
            shiftUm   = [0, -correctionYum];   % stage Y up: a downward move is negative
        end
        xmlLines{end+1} = sprintf([ ...
            '<Tie><Image1Position><X>%.6f</X><Y>%.6f</Y></Image1Position>' ...
            '<Image2Position><X>%.6f</X><Y>%.6f</Y></Image2Position>' ...
            '<Shift><X>%.6f</X><Y>%.6f</Y></Shift>' ...
            '<Image1Index>%d</Image1Index><Image2Index>%d</Image2Index>' ...
            '<Overlap>true</Overlap><Confidence>%.6f</Confidence><User>%s</User>' ...
            '<Image1FileName>%s</Image1FileName><Image2FileName>%s</Image2FileName></Tie>'], ...
            position1, position2, shiftUm, ...
            tiePairs(tieIdx, 1), tiePairs(tieIdx, 2), options.confidences(tieIdx), ...
            string(options.userTies(tieIdx)), ...
            recordedPath(tileNames{tiePairs(tieIdx, 1) + 1}), ...
            recordedPath(tileNames{tiePairs(tieIdx, 2) + 1})); %#ok<AGROW>
    end
    xmlLines{end+1} = sprintf(['</Ties><ConfidenceThreshold>%.6f</ConfidenceThreshold>' ...
        '<PerTileRotation>false</PerTileRotation></F-ATLAS-Image-Ties>'], options.confidenceThreshold);
    writeTextFile(fullfile(folderPath, 'MosaicInfo_SYN.ve-tie'), xmlLines);
end

% ---- .ve-updates — the placement those ties imply ----
solvedStepXum = stepUm + correctionXum;
solvedStepYum = stepUm + correctionYum;
if options.writeUpdates
    xmlLines = {'<?xml version="1.0" encoding="utf-8"?>', '<ATLAS-Stitch-Info>'};
    for tileIdx = 1:numTiles
        solvedX = stageXSign * (gridRowCol(tileIdx, 2) - 1) * solvedStepXum;
        solvedY = -(gridRowCol(tileIdx, 1) - 1) * solvedStepYum;
        xmlLines{end+1} = sprintf([ ...
            '<Tile><Name>%s</Name>' ...
            '<ParentTransform><M11>%g</M11><M22>%g</M22><M41>%.6f</M41><M42>%.6f</M42>' ...
            '<CenterLocalX>0.5</CenterLocalX></ParentTransform>' ...
            '<DefaultAlignment><ParentTransform><M11>1</M11><M22>1</M22>' ...
            '<M41>-0.5</M41><M42>-0.5</M42></ParentTransform></DefaultAlignment>' ...
            '<FileName>%s</FileName><Width>64</Width><Height>64</Height></Tile>'], ...
            tileNames{tileIdx}, fovUm, fovUm, solvedX, solvedY, ...
            recordedPath(tileNames{tileIdx})); %#ok<AGROW>
    end
    xmlLines{end+1} = '</ATLAS-Stitch-Info>';
    writeTextFile(fullfile(folderPath, 'MosaicInfo_SYN.ve-updates'), xmlLines);
end

mosaic.folder          = folderPath;
mosaic.veMifPath       = veMifPath;
mosaic.tileNames       = tileNames;
mosaic.pixelSizeUm     = pixelSizeUm;
mosaic.stepPx          = stepUm / pixelSizeUm;
mosaic.measuredStepXpx = measuredStepXpx;
mosaic.measuredStepYpx = measuredStepYpx;

end

% =========================================================================
function writeTextFile(filePath, lines)
% WRITETEXTFILE - Write a cell array of lines as a plain text file.
fileId = fopen(filePath, 'w');
fprintf(fileId, '%s\n', lines{:});
fclose(fileId);
end
