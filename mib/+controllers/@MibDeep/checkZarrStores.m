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
% the directory itself when there is no such subfolder. MIB model stores (the
% ``mibModelStore`` attribute, e.g. the output of an earlier prediction written
% next to the images) are skipped.
%
% The metadata of every store is read here, so that a problem stops the run
% before any file is deleted and before the network is loaded:
%
%   - the requested level (``BatchOpt.BioformatsIndex``) must exist in every
%     store. This is a hard check because the zarr loaders ignore an
%     out-of-range ``ZarrLevel`` and open their level dialog instead, which
%     would appear inside the datastore read;
%   - the pixel class must be an integer one: the Standard-mode loader converts
%     float data through a dialog that needs a parent figure;
%   - the memory needed for the largest level, estimated as 4 copies of it
%     (image, blocked image, labels, scores; for 2D Instance: image, its RGB
%     copy and uint32 labels are of the same order), is compared with the
%     largest possible array (Windows only); the user may continue or cancel.
%
% Output Arguments:
%   - **zarrList** - [cell] full paths of the stores
%   - **zarrStores** - [struct array] per store: ``.groupPath`` - the image
%     group resolved inside the store (equals the store path unless the store
%     is a container); ``.pyramid`` - ``levelImageSizes``, ``levelScaleFactors``,
%     ``chunkSizes``, ``axisOrder`` for ``core.MibBigDataLabels.createStore``
%   - **cancelled** - [logical] true when the run must stop

    cancelled = true;
    zarrStores = struct('groupPath', {}, 'pyramid', {});
    zarrLevel = obj.BatchOpt.BioformatsIndex{1};

    zarrDir = fullfile(obj.BatchOpt.OriginalPredictionImagesDir, 'Images');
    if ~isfolder(zarrDir); zarrDir = obj.BatchOpt.OriginalPredictionImagesDir; end
    listing = dir(zarrDir);
    listing = listing([listing.isdir] & ~cellfun(@isempty, regexpi({listing.name}, '\.zarr[23]?$', 'once')));
    zarrList = fullfile({listing.folder}, {listing.name});
    zarrList = zarrList(~cellfun(@core.MibBigDataLabels.isMibModelStore, zarrList));
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
    maxLevelBytes = 0;
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
        bytesPerPixel = numel(typecast(cast(0, files.imgClass), 'uint8'));
        maxLevelBytes = max(maxLevelBytes, prod(files.levelImageSizes(zarrLevel, :)) * files.color * bytesPerPixel);

        zarrStores(fileId).groupPath = files.filename;
        zarrStores(fileId).pyramid = struct('levelImageSizes', files.levelImageSizes, ...
            'levelScaleFactors', files.levelScaleFactors, ...
            'chunkSizes', {files.chunkSizes}, ...
            'axisOrder', files.axisOrder);
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

    % memory check: the selected level of the largest store is loaded whole
    try
        memoryInfo = memory();
        availableBytes = memoryInfo.MaxPossibleArrayBytes;
    catch
        availableBytes = Inf;   % memory() is available only on Windows
    end
    if maxLevelBytes * 4 > availableBytes
        selection = uiconfirm(obj.view.gui, ...
            sprintf(['Level %d of the largest store takes %.1f GB, and predicting it needs about %.1f GB of memory, ' ...
            'while %.1f GB is available.\n\nSelect a coarser level (a larger number) or continue at your own risk'], ...
            zarrLevel, maxLevelBytes/1e9, maxLevelBytes*4/1e9, availableBytes/1e9), ...
            'Not enough memory', 'Options', {'Continue', 'Cancel'}, ...
            'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
        if strcmp(selection, 'Cancel'); return; end
    end
    cancelled = false;
end
