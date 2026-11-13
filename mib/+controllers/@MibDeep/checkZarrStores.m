function [zarrList, zarrStores, cancelled] = checkZarrStores(obj)
% CHECKZARRSTORES - list the zarr stores for prediction and check them before the run.
%
% Syntax:
%   .. code-block:: matlab
%
%       [zarrList, zarrStores, cancelled] = obj.checkZarrStores()
%
% Used by ``startPredictionBlockedImage`` and ``startPredictionInstances`` when
% the extension of images for prediction is 'ZARR'.
%
% Stores are folders named ``*.zarr``, ``*.zarr2`` or ``*.zarr3`` (``*.ome.zarr``
% included) under the "Images" subfolder of the prediction directory, or under
% the directory itself when there is no such subfolder. The prediction directory
% may also be a zarr store itself (its name ends with ``.zarr``, ``.zarr2`` or
% ``.zarr3``): that one store is predicted. MIB model stores (the
% ``mibModelStore`` attribute) and score stores (``mibPredictionScores``), i.e. the
% output of an earlier prediction written next to the images, are skipped
% (``MibDeep.isPredictionStore``).
%
% The metadata of every store is read here, so that a problem stops the run
% before any file is deleted and before the network is loaded:
%
%   - the requested level (``BatchOpt.BioformatsIndex``) must exist in every
%     store, so that the run does not stop on a later store;
%   - the pixel class must be an integer one, as for every other DeepMIB input.
%
% No pixels are read here. The stores are larger than memory as a rule, so the
% prediction reads them slab by slab (``predictZarrStore``, and the per-slice
% loop of ``startPredictionInstances``); the memory of a slab is checked there.
%
% Output Arguments:
%   - **zarrList** - [cell] full paths of the stores
%   - **zarrStores** - [struct array] per store: ``.groupPath`` - the image
%     group resolved inside the store (equals the store path unless the store
%     is a container); ``.pixSize`` - voxel size of level 1 (``files.pixSize``),
%     used by the score stores; ``.pyramid`` -``levelImageSizes``, ``levelScaleFactors``,
%     ``chunkSizes``, ``axisOrder`` for ``core.MibBigDataLabels.createStore``;
%     ``.levelNames`` - array path of each level inside the group (``''`` = the
%     group itself); ``.levelRegionOrigins`` - ``[y x z]`` first voxel of each
%     level when the store was opened with a region, ones otherwise;
%     ``.colors`` - number of channels; ``.imgClass`` - pixel class. The last
%     four are what ``deepmib.readZarrSlab`` needs
%   - **cancelled** - [logical] true when the run must stop

    cancelled = true;
    zarrStores = struct('groupPath', {}, 'pyramid', {}, 'pixSize', {}, ...
        'levelNames', {}, 'levelRegionOrigins', {}, 'colors', {}, 'imgClass', {});
    zarrLevel = obj.BatchOpt.BioformatsIndex{1};

    predictionDir = regexprep(obj.BatchOpt.OriginalPredictionImagesDir, '[\\/]+$', '');
    if isfolder(predictionDir) && ~isempty(regexpi(predictionDir, '\.zarr[23]?$', 'once'))
        % the selected directory is a zarr store itself
        zarrDir = fileparts(predictionDir);
        zarrList = {predictionDir};
    else
        zarrDir = fullfile(obj.BatchOpt.OriginalPredictionImagesDir, 'Images');
        if ~isfolder(zarrDir); zarrDir = obj.BatchOpt.OriginalPredictionImagesDir; end
        listing = dir(zarrDir);
        listing = listing([listing.isdir] & ~cellfun(@isempty, regexpi({listing.name}, '\.zarr[23]?$', 'once')));
        zarrList = fullfile({listing.folder}, {listing.name});
    end
    zarrList = zarrList(~cellfun(@controllers.MibDeep.isPredictionStore, zarrList));
    if isempty(zarrList)
        mgsOpt.MsgBoxOnly = true;
        utils.dlgs.inputUniversalDlg(obj.view.gui, ...
            sprintf('No zarr stores (*.zarr, *.zarr2, *.zarr3) were found in\n%s', zarrDir), ...
            {}, {}, 'Missing files', mgsOpt);
        return;
    end

    integerClasses = {'uint8', 'uint16', 'uint32', 'int8', 'int16', 'int32'};
    extReg = io.ExtensionRegistryLoad();
    problems = {};
    for fileId = 1:numel(zarrList)
        [~, storeName, storeExt] = fileparts(zarrList{fileId});
        storeName = [storeName storeExt];
        try
            loaderInfo = extReg.resolveLoader(zarrList{fileId}, 'Standard', 'Default');
            if ischar(loaderInfo); error('%s', loaderInfo); end
            loader = io.LoaderFactory.create(loaderInfo, struct('ParentFigure', obj.view.gui, 'silentMode', true));
            [~, files] = loader.loadMetadata(zarrList(fileId), struct('silentMode', true));
        catch err
            utils.dlgs.showErrorDialog(obj.view.gui, err, sprintf('Can not read %s', storeName));
            return;
        end
        if ~isstruct(files) || ~isfield(files, 'nLevels') || isempty(files.nLevels)
            return;     % the image group picker of a container was dismissed
        end

        if zarrLevel > files.nLevels
            problems{end+1} = sprintf('%s: has %d level(s)', storeName, files.nLevels); %#ok<AGROW>
            continue;
        end
        if ~ismember(files.imgClass, integerClasses)
            problems{end+1} = sprintf('%s: %s pixels, only integer images are supported', storeName, files.imgClass); %#ok<AGROW>
            continue;
        end
        zarrStores(fileId).groupPath = files.filename;
        zarrStores(fileId).pixSize = files.pixSize;
        zarrStores(fileId).pyramid = struct('levelImageSizes', files.levelImageSizes, ...
            'levelScaleFactors', files.levelScaleFactors, ...
            'chunkSizes', {files.chunkSizes}, ...
            'axisOrder', files.axisOrder);
        zarrStores(fileId).levelNames = files.levelNames;
        if isfield(files, 'levelRegionOrigins') && ~isempty(files.levelRegionOrigins)
            zarrStores(fileId).levelRegionOrigins = files.levelRegionOrigins;
        else
            zarrStores(fileId).levelRegionOrigins = ones(files.nLevels, 3);
        end
        zarrStores(fileId).colors = files.color;
        zarrStores(fileId).imgClass = files.imgClass;
    end

    if ~isempty(problems)
        mgsOpt.MsgBoxOnly = true;
        mgsOpt.WindowWidth = 560;
        mgsOpt.WindowHeight = 280;
        utils.dlgs.inputUniversalDlg(obj.view.gui, ...
            sprintf('Level %d can not be predicted for these stores:', zarrLevel), ...
            {}, {strjoin(problems, newline)}, 'Wrong level', mgsOpt);
        return;
    end
    cancelled = false;
end
