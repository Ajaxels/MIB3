function updateScoreExportSettings(obj)
% UPDATESCOREEXPORTSETTINGS - update export settings for score files.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.updateScoreExportSettings()
%
% Shows a dialog with the settings of the score files and stores them in
% ``obj.ScoreExportOpt``. ``.IncludeExterior`` ("Export exterior material") is
% always offered. When ``BatchOpt.P_ScoreFiles`` is "Zarr3 (BigData)" the dialog
% also has the settings of the score stores
% (``Score_<image name>.zarr3``, written by ``startPredictionBlockedImage``):
%
%   - ``.ZarrFormat`` - ``'v3'`` (default) or ``'v2'``, the zarr format of the store
%   - ``.Location`` - destination of the stores: ``'Next to images'`` (default)
%     or ``'ResultsScores'`` are offered for confirmation when prediction
%     starts; ``'Ask'`` asks for a folder then (see ``selectModelStoreDestination``).
%     When the model files are also written as zarr stores, the score stores
%     go to the folder of the models
%   - ``.Levels`` - number of pyramid levels, ``0`` (default) = the levels of the
%     zarr image from the predicted level down; for images that are not zarr
%     (no pyramid to follow) ``0`` = automatic, halving XY until the smaller
%     side is below 256 pixels
%   - ``.ChunkSize`` - chunk ``[y x z]``; ``[0 0 0]`` (default) = the chunks of the
%     zarr image, ``[256 256 16]`` for other images. The channels (classes) are
%     always in one chunk
%   - ``.ShardSize`` - chunks per shard ``[y x z]``, ``[0 0 0]`` (default) = no
%     sharding. Zarr v3 only, the combination with v2 is refused here
%   - ``.Compressors`` and ``.CompressionLevel`` - ``'zstd'`` (default), ``'gzip'``
%     or ``'none'``, level 7 by default (zstd 1-22, gzip 1-9)
%   - ``.DownsampleMethod`` - how the coarser levels are made: ``'bilinear'``
%     (default), ``'nearest'`` or ``'bicubic'``. The scores are continuous
%     (uint8, 0-255), so the label-oriented 'mode' and 'median' are not offered
%
% The pyramid starts at the predicted level, which becomes level 1 of the store.

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDeep.updateScoreExportSettings: triggered\n');
end

    zarrScores = strcmp(obj.BatchOpt.P_ScoreFiles{1}, 'Zarr3 (BigData)');
    prompts = {sprintf('Export exterior material')};
    defAns = {obj.ScoreExportOpt.IncludeExterior};
    dlgTitle = 'Export scores settings';

    options.WindowStyle = 'normal';
    options.LabelPosition = 'left';
    options.Header = sprintf('Additional settings for export of score files\nOnly for Blocked-image engine');
    options.HeaderLines = 2;

    if zarrScores
        formatList = {'v3', 'v2'};
        locationList = {'Next to images', 'ResultsScores', 'Ask'};
        compressorList = {'zstd', 'gzip', 'none'};
        methodList = {'bilinear (fast, smooth)', 'nearest (fast)', 'bicubic (slower, sharp)'};
        scoreOpt = obj.ScoreExportOpt;
        prompts = [prompts; {'Zarr format:'; ...
            'Destination:'; ...
            'Pyramid levels (0 = as image, automatic for non-zarr):'; ...
            'Chunk size [Y, X, Z] (0 = as image):'; ...
            'Shard X-factors [Y, X, Z] (0 = off):'; ...
            'Compression:'; ...
            'Compression level:'; ...
            'Downsampling method:'}];
        defAns = [defAns; ...
            {[formatList, {max([1, find(ismember(formatList, scoreOpt.ZarrFormat), 1)])}]; ...
            [locationList, {max([1, find(ismember(locationList, scoreOpt.Location), 1)])}]; ...
            struct('Spinner', true, 'Value', scoreOpt.Levels, 'Limits', [0 12], 'Step', 1, 'Round', true); ...
            sprintf('%d, %d, %d', scoreOpt.ChunkSize); ...
            sprintf('%d, %d, %d', scoreOpt.ShardSize); ...
            [compressorList, {max([1, find(ismember(compressorList, scoreOpt.Compressors), 1)])}]; ...
            struct('Spinner', true, 'Value', max(1, scoreOpt.CompressionLevel), 'Limits', [1 22], 'Step', 1, 'Round', true); ...
            [methodList, {max([1, find(startsWith(methodList, scoreOpt.DownsampleMethod), 1)])}]}];
        headerLines = {'Additional settings for export of score files'; ...
            'Only for Blocked-image engine'; ...
            ''; ...
            'Zarr3 (BigData): Score_<image name>.zarr3, an image with a channel per class'; ...
            'Destination "Ask": the folder is asked when Predict is pressed'; ...
            'Pyramid levels: 0 follows the zarr image from the predicted level down;'; ...
            'images that are not zarr get levels until the smaller side is below 256 px'; ...
            'Chunk size: 0 uses the chunks of the zarr image, [256 256 16] otherwise'; ...
            'Shard X-factors: chunks bundled per shard file (zarr v3 only)'; ...
            'Downsampling method, for the coarser levels of the scores'};
        options.Header = strjoin(headerLines, newline);
        options.HeaderLines = numel(headerLines);
        options.WindowWidth = 560;
        options.mibPath = obj.mibModel.mibPath;
    end

    answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, dlgTitle, options);
    if isempty(answer); return; end

    if zarrScores
        chunkSize = str2num(answer{5}); %#ok<ST2NM>
        if numel(chunkSize) ~= 3 || any(chunkSize < 0) || any(chunkSize ~= round(chunkSize)) || ...
                (any(chunkSize == 0) && any(chunkSize > 0))
            mgsOpt.MsgBoxOnly = true;
            utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                sprintf('Chunk size should be three positive integers [Y, X, Z],\nor 0, 0, 0 to use the default chunks'), ...
                {}, {}, 'Wrong chunk size', mgsOpt);
            return;
        end
        shardSize = str2num(answer{6}); %#ok<ST2NM>
        if numel(shardSize) ~= 3 || any(shardSize < 0) || any(shardSize ~= round(shardSize))
            mgsOpt.MsgBoxOnly = true;
            utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                sprintf('Shard X-factors should be three non-negative integers [Y, X, Z],\nor 0, 0, 0 for no sharding'), ...
                {}, {}, 'Wrong shard size', mgsOpt);
            return;
        end
        if all(shardSize > 0) && strcmp(answer{2}, 'v2')
            mgsOpt.MsgBoxOnly = true;
            utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                sprintf('Sharding is available only for zarr v3\n\nSelect v3, or set Shard X-factors to 0, 0, 0'), ...
                {}, {}, 'Sharding requires zarr v3', mgsOpt);
            return;
        end
        obj.ScoreExportOpt.ZarrFormat = answer{2};
        obj.ScoreExportOpt.Location = answer{3};
        obj.ScoreExportOpt.Levels = answer{4};
        obj.ScoreExportOpt.ChunkSize = chunkSize(:)';
        obj.ScoreExportOpt.ShardSize = shardSize(:)';
        obj.ScoreExportOpt.Compressors = answer{7};
        obj.ScoreExportOpt.CompressionLevel = answer{8};
        obj.ScoreExportOpt.DownsampleMethod = strtok(answer{9}, ' ');
    end
    obj.ScoreExportOpt.IncludeExterior = logical(answer{1});

    % % Precistion is not implemented yet
end
