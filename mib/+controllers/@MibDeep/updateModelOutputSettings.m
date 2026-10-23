function updateModelOutputSettings(obj)
% UPDATEMODELOUTPUTSETTINGS - update settings for the "Zarr3 (BigData model)" output of prediction.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.updateModelOutputSettings()
%
% Shows a dialog with the settings of the BigData model stores written by
% prediction of zarr images (see ``writeModelStore``) and stores them in
% ``obj.ZarrModelOpt``:
%
%   - ``.ZarrFormat`` - ``'v3'`` (default) or ``'v2'``, the zarr format of the
%     model store, written as ``Labels_<image name>.zarr3`` or ``.zarr2``;
%     both are editable in MIB
%   - ``.Location`` - destination of the stores: ``'Next to images'``
%     (default) or ``'ResultsModels'`` are offered for confirmation when
%     prediction starts; ``'Ask'`` asks for a folder when prediction starts
%     (see ``selectModelStoreDestination``)
%   - ``.Levels`` - number of pyramid levels, ``0`` (default) = as many as the
%     image. Fewer levels drop the coarsest ones; the store must keep the
%     predicted level, which ``selectModelStoreDestination`` checks before the
%     run. More levels than the image are not possible: the level shapes are
%     the image's
%   - ``.ChunkSize`` - chunk ``[y x z]``; ``[0 0 0]`` (default) = the chunks of
%     the image level by level. A chunk larger than a level is clamped to it
%   - ``.ShardSize`` - chunks per shard ``[y x z]``, as in the standard zarr
%     export dialog; ``[0 0 0]`` (default) = no sharding. Zarr v3 only (v2 has
%     no sharding codec, the combination is refused here). Sharding cuts the
%     number of files of a large store, but every later edit of the model
%     rewrites whole shards (a partial-shard write re-reads and rewrites the
%     shard, measured 3.4x slower, development/bigdata/plan_imageconverter_zarr.md)
%   - ``.Compressors`` - ``'zstd'`` (default), ``'gzip'`` or ``'none'``
%   - ``.CompressionLevel`` - ``7`` (default); zstd 1-22, gzip 1-9 (a higher
%     gzip level is written as 9). Labels compress well: on label volumes zstd 7
%     was 15-25% smaller than the codec default 3 for 5-15% more write time,
%     and higher levels gained a few percent for up to twice the write time
%     (measurements in development/deepmib/plan_zarr_implementation.md). There
%     is no "codec default" choice; 0 saved by an earlier version becomes 7
%
%   - ``.DownsampleMethod`` - how the coarser levels are made from the
%     predicted level: ``'nearest'`` (default, fast) or ``'mode'`` (majority
%     vote per block, slow, keeps thin structures and small objects better);
%     same items as the standard zarr export dialog for models. It applies to
%     the prediction only: later edits of the model in MIB propagate to the
%     coarser levels with nearest-neighbour, as every BigData edit does
%
% The one setting of the standard zarr export dialog
% (``io.savers.Zarr3Saver.optionsDialog``) that is not offered is the
% downsampling strategy: the level shapes must be those of the image so the
% model lines up with it at every zoom.

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDeep.updateModelOutputSettings: triggered\n');
end

    formatList = {'v3', 'v2'};
    locationList = {'Next to images', 'ResultsModels', 'Ask'};
    compressorList = {'zstd', 'gzip', 'none'};
    methodList = {'nearest (fast)', 'mode (precise, very slow)'};
    chunkText = sprintf('%d, %d, %d', obj.ZarrModelOpt.ChunkSize);
    shardText = sprintf('%d, %d, %d', obj.ZarrModelOpt.ShardSize);

    prompts = {'Zarr format:'; ...
        'Destination:'; ...
        'Pyramid levels (0 = as image):'; ...
        'Chunk size [Y, X, Z] (0 = as image):'; ...
        'Shard X-factors [Y, X, Z] (0 = off):'; ...
        'Compression:'; ...
        'Compression level:'; ...
        'Downsampling method:'};
    defAns = {[formatList, {max([1, find(ismember(formatList, obj.ZarrModelOpt.ZarrFormat), 1)])}]; ...
        [locationList, {max([1, find(ismember(locationList, obj.ZarrModelOpt.Location), 1)])}]; ...
        struct('Spinner', true, 'Value', obj.ZarrModelOpt.Levels, 'Limits', [0 12], 'Step', 1, 'Round', true); ...
        chunkText; ...
        shardText; ...
        [compressorList, {max([1, find(ismember(compressorList, obj.ZarrModelOpt.Compressors), 1)])}]; ...
        struct('Spinner', true, 'Value', max(1, obj.ZarrModelOpt.CompressionLevel), 'Limits', [1 22], 'Step', 1, 'Round', true); ...
        [methodList, {max([1, find(startsWith(methodList, obj.ZarrModelOpt.DownsampleMethod), 1)])}]};
    dlgTitle = 'BigData model output settings';

    headerLines = {'Model stores generated from ZARR images ("Model files" = "Zarr3 (BigData model)")'; ...
        ''; ...
        'Destination "Ask": the folder is asked when Predict is pressed'; ...
        'Pyramid levels: fewer than the image drops the coarsest levels;'; ...
        'the predicted level must be kept'; ...
        'Shard X-factors: chunks bundled per shard file (zarr v3 only); fewer'; ...
        'files for large stores, but slower editing of the model afterwards'; ...
        'Compression level: zstd 1-22, gzip 1-9 (higher is written as 9);'; ...
        'labels compress well, 7 is a good balance of size and speed'; ...
        'Downsampling method, for the coarser levels: "nearest" (fast) picks the'; ...
        'nearest pixel; "mode" (slow) takes the dominant label of each block and'; ...
        'keeps thin structures and small objects better'; ...
        ''; ...
        'Level shapes follow the image, so the model matches it at every zoom.'};
    options.WindowStyle = 'normal';
    options.LabelPosition = 'left';
    options.WindowWidth = 560;
    options.Header = strjoin(headerLines, newline);
    options.HeaderLines = numel(headerLines);
    options.mibPath = obj.mibModel.mibPath;

    answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, dlgTitle, options);
    if isempty(answer); return; end

    chunkSize = str2num(answer{4}); %#ok<ST2NM>
    if numel(chunkSize) ~= 3 || any(chunkSize < 0) || any(chunkSize ~= round(chunkSize)) || ...
            (any(chunkSize == 0) && any(chunkSize > 0))
        mgsOpt.MsgBoxOnly = true;
        utils.dlgs.inputUniversalDlg(obj.view.gui, ...
            sprintf('Chunk size should be three positive integers [Y, X, Z],\nor 0, 0, 0 to use the chunks of the image'), ...
            {}, {}, 'Wrong chunk size', mgsOpt);
        return;
    end
    shardSize = str2num(answer{5}); %#ok<ST2NM>
    if numel(shardSize) ~= 3 || any(shardSize < 0) || any(shardSize ~= round(shardSize))
        mgsOpt.MsgBoxOnly = true;
        utils.dlgs.inputUniversalDlg(obj.view.gui, ...
            sprintf('Shard X-factors should be three non-negative integers [Y, X, Z],\nor 0, 0, 0 for no sharding'), ...
            {}, {}, 'Wrong shard size', mgsOpt);
        return;
    end
    if all(shardSize > 0) && strcmp(answer{1}, 'v2')
        mgsOpt.MsgBoxOnly = true;
        utils.dlgs.inputUniversalDlg(obj.view.gui, ...
            sprintf('Sharding is available only for zarr v3\n\nSelect v3, or set Shard X-factors to 0, 0, 0'), ...
            {}, {}, 'Sharding requires zarr v3', mgsOpt);
        return;
    end

    obj.ZarrModelOpt.ZarrFormat = answer{1};
    obj.ZarrModelOpt.Location = answer{2};
    obj.ZarrModelOpt.Levels = answer{3};
    obj.ZarrModelOpt.ChunkSize = chunkSize(:)';
    obj.ZarrModelOpt.ShardSize = shardSize(:)';
    obj.ZarrModelOpt.Compressors = answer{6};
    obj.ZarrModelOpt.CompressionLevel = answer{7};
    obj.ZarrModelOpt.DownsampleMethod = strtok(answer{8}, ' ');   % 'nearest' or 'mode'
end
