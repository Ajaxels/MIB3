function [storePaths, zarrFormat, cancelled] = selectModelStoreDestination(obj, zarrList)
% SELECTMODELSTOREDESTINATION - confirm where the BigData model stores are written.
%
% Syntax:
%   .. code-block:: matlab
%
%       [storePaths, zarrFormat, cancelled] = obj.selectModelStoreDestination(zarrList)
%
% Used by ``startPredictionBlockedImage`` and ``startPredictionInstances`` when
% "Model files" is "Zarr3 (BigData model)".
%
% Input Arguments:
%   - **zarrList** - [cell] full paths of the zarr images, from ``checkZarrStores``
%
% Each store is written as ``Labels_<image name>.zarr3`` (``.zarr2`` when
% ``obj.ZarrModelOpt.ZarrFormat`` is ``'v2'``), the name MIB proposes for a new
% BigData model. ``obj.ZarrModelOpt.Location`` selects the folder:
%
%   - ``'Next to images'`` (default) - the folder with the images, so the result
%     can be loaded on the image without copying; confirmed in a dialog that
%     also offers choosing another folder;
%   - ``'ResultsModels'`` - ``PredictionImages/ResultsModels``, confirmed the
%     same way;
%   - ``'Ask'`` - the folder is asked straight away (``uigetdir``, starting in
%     the folder with the images).
%
% The overwriting of stores that already exist is then confirmed once, because
% ``core.MibBigDataLabels.createStore`` removes an existing folder silently.
% The chosen folder is kept in ``obj.sessionSettings.lastModelStoreFolder``,
% where ``previewModels`` looks for the stores first.
%
% Before that, a store limited to fewer pyramid levels than the image
% (``obj.ZarrModelOpt.Levels``) must still hold the predicted level
% (``BatchOpt.BioformatsIndex``); otherwise the run is refused with a message.
%
% Output Arguments:
%   - **storePaths** - [cell] full path of the model store for each image
%   - **zarrFormat** - [numeric] 2 or 3
%   - **cancelled** - [logical] true when the user cancelled

    cancelled = true;
    storePaths = {};
    if strcmp(obj.ZarrModelOpt.ZarrFormat, 'v2')
        zarrFormat = 2;
    else
        zarrFormat = 3;
    end
    storeExtension = sprintf('.zarr%d', zarrFormat);

    % a store with fewer levels than the image must still hold the predicted level
    predictedLevel = obj.BatchOpt.BioformatsIndex{1};
    if obj.ZarrModelOpt.Levels > 0 && obj.ZarrModelOpt.Levels < predictedLevel
        mgsOpt.MsgBoxOnly = true;
        utils.dlgs.inputUniversalDlg(obj.view.gui, ...
            sprintf(['The model stores are set to %d pyramid level(s), but level %d is predicted\n\n' ...
            'Increase "Pyramid levels" in the settings of Model files (0 = as image)'], ...
            obj.ZarrModelOpt.Levels, predictedLevel), {}, {}, 'Wrong number of levels', mgsOpt);
        return;
    end

    if strcmp(obj.ZarrModelOpt.Location, 'ResultsModels')
        outputFolder = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels');
    else
        outputFolder = fileparts(zarrList{1});
    end
    if strcmp(obj.ZarrModelOpt.Location, 'Ask')
        selection = 'Choose folder...';
    else
        selection = uiconfirm(obj.view.gui, ...
            sprintf('Model stores will be written to\n\n%s\n\nas Labels_<image name>%s', outputFolder, storeExtension), ...
            'Destination of model stores', ...
            'Options', {'Write here', 'Choose folder...', 'Cancel'}, ...
            'DefaultOption', 1, 'CancelOption', 3);
    end
    switch selection
        case 'Cancel'
            return;
        case 'Choose folder...'
            chosenFolder = uigetdir(outputFolder, sprintf('Select folder for model stores (Labels_<image name>%s)', storeExtension));
            figure(obj.view.gui);
            if isequal(chosenFolder, 0); return; end
            outputFolder = chosenFolder;
    end

    storePaths = cell(size(zarrList));
    for fileId = 1:numel(zarrList)
        [~, imageName] = fileparts(zarrList{fileId});
        imageName = regexprep(imageName, '\.ome$', '', 'ignorecase');
        storePaths{fileId} = fullfile(outputFolder, ['Labels_' imageName storeExtension]);
    end

    existingStores = storePaths(cellfun(@isfolder, storePaths));
    if ~isempty(existingStores)
        [~, existingNames, existingExt] = cellfun(@fileparts, existingStores, 'UniformOutput', false);
        existingNames = strcat(existingNames, existingExt);
        if numel(existingNames) > 10
            existingNames = [existingNames(1:10), {sprintf('... and %d more', numel(existingNames)-10)}];
        end
        selection = uiconfirm(obj.view.gui, ...
            sprintf('These model stores already exist in\n%s\n\n%s\n\nOverwrite them?', outputFolder, strjoin(existingNames, newline)), ...
            'Model stores exist', 'Options', {'Overwrite', 'Cancel'}, ...
            'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
        if strcmp(selection, 'Cancel'); storePaths = {}; return; end
    end
    obj.sessionSettings.lastModelStoreFolder = outputFolder;   % where previewModels looks for the stores
    cancelled = false;
end
