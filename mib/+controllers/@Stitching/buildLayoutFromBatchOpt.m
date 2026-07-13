function buildLayoutFromBatchOpt(obj)
% BUILDLAYOUTFROMBATCHOPT - Build the tile layout from current BatchOpt settings (headless).
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.buildLayoutFromBatchOpt()
%
% Builds ``obj.layout`` from ``BatchOpt.LayoutSource`` and ``BatchOpt.InputPath``
% without opening any dialogs, so it works both in batch mode and from the GUI
% after the input path was chosen. Errors when the path is missing or contains
% no tiles. Downstream state (``edges``, ``positions``, ``canvas``) is reset.
%

layoutSource = obj.BatchOpt.LayoutSource{1};
inputPath = obj.BatchOpt.InputPath;

if isempty(inputPath)
    error('Stitching:noInputPath', 'InputPath is empty — select a tile folder or position file first');
end

if strcmp(layoutSource, 'Position file')
    if ~isfile(inputPath)
        error('Stitching:badInputPath', 'Position file not found: %s', inputPath);
    end
    posOptions.subfolderMode = obj.BatchOpt.SubfolderMode;
    obj.layout = utils.stitch.buildLayoutPositionFile(inputPath, posOptions);
else
    % Grid or Filename pattern — collect image files from the folder
    if ~isfolder(inputPath)
        error('Stitching:badInputPath', 'Tile folder not found: %s', inputPath);
    end
    imageExtensions = {'*.tif', '*.tiff', '*.png', '*.jpg', '*.jpeg', '*.bmp'};
    tileFiles = {};
    for extIdx = 1:numel(imageExtensions)
        foundFiles = dir(fullfile(inputPath, imageExtensions{extIdx}));
        if ~isempty(foundFiles)
            tileFiles = [tileFiles, fullfile(inputPath, {foundFiles.name})]; %#ok<AGROW>
        end
    end
    if isempty(tileFiles)
        error('Stitching:noTiles', 'No image files found in %s', inputPath);
    end

    if strcmp(layoutSource, 'Grid')
        gridOpts.rows       = obj.BatchOpt.GridRows{1};
        gridOpts.cols       = obj.BatchOpt.GridCols{1};
        gridOpts.tileOrder  = obj.BatchOpt.TileOrder{1};
        gridOpts.overlapX   = obj.BatchOpt.OverlapX{1};
        gridOpts.overlapY   = obj.BatchOpt.OverlapY{1};
        obj.layout = utils.stitch.buildLayoutGrid(tileFiles, gridOpts);
    else
        % Filename pattern
        obj.layout = utils.stitch.buildLayoutFilenamePattern(tileFiles);
    end
end

% Reset downstream state
obj.edges     = [];
obj.positions = [];
obj.canvas    = [];

end
