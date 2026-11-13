function [storePaths, zarrFormat, cancelled, resumeStores] = selectModelStoreDestination(obj, zarrList, storeKind, allowResume)
% SELECTMODELSTOREDESTINATION - confirm where the BigData model or score stores are written.
%
% Syntax:
%   .. code-block:: matlab
%
%       [storePaths, zarrFormat, cancelled] = obj.selectModelStoreDestination(zarrList)
%       [storePaths, zarrFormat, cancelled] = obj.selectModelStoreDestination(zarrList, storeKind)
%       [storePaths, zarrFormat, cancelled, resumeStores] = obj.selectModelStoreDestination(zarrList, storeKind, true)
%
% Used by ``startPredictionBlockedImage`` and ``startPredictionInstances`` when
% "Model files" is "Zarr3 (BigData model)", and by ``startPredictionBlockedImage``
% when "Score files" is "Zarr3 (BigData)".
%
% Input Arguments:
%   - **zarrList** - [cell] full paths of the images (zarr stores from ``checkZarrStores``,
%     or the files of any other type); only the folder of the first one and the names are used
%   - **storeKind** - *(optional)* ``'model'`` (default) or ``'score'``. A score
%     store is written as ``Score_<image name>.zarr3`` and has no pyramid
%     levels to keep, so the check of ``obj.ZarrModelOpt.Levels`` is skipped. Its
%     format and destination are in ``obj.ScoreExportOpt`` (``updateScoreExportSettings``).
%     Its ``'ResultsScores'`` destination is ``PredictionImages/ResultsScores``.
%     When the model files also go to a zarr store and both are ``'Next to images'``,
%     the score stores are put in
%     the folder of the model stores without asking again (only the overwriting
%     is confirmed), and ``obj.sessionSettings.lastModelStoreFolder`` is left
%     for the models
%   - **allowResume** - *(optional)* [logical] offer "Resume" for stores of an
%     interrupted prediction, default false
%
% Each store is written as ``Labels_<image name>.zarr3`` (``.zarr2`` when
% ``obj.ZarrModelOpt.ZarrFormat`` is ``'v2'``), the name MIB proposes for a new
% BigData model. ``obj.ZarrModelOpt.Location`` selects the folder:
%
%   - ``'Next to images'`` (default) - the folder with the images, so the result
%     can be loaded on the image without copying; confirmed in a dialog that
%     also offers choosing another folder;
%   - ``'ResultsModels'`` (``'ResultsScores'`` for scores) - ``PredictionImages/ResultsModels``, confirmed the
%     same way;
%   - ``'Ask'`` - the folder is asked straight away (``uigetdir``, starting in
%     the folder with the images).
%
% The overwriting of stores that already exist is then confirmed once, because
% ``core.MibBigDataLabels.createStore`` removes an existing folder silently.
% With ``allowResume`` (zarr images, ``predictZarrStore``), when some of them
% hold an interrupted prediction (``MibDeep.PredictionRecordFile`` in the store),
% the dialog also offers "Resume": those stores are then continued
% (``resumeStores``) and the other existing ones overwritten. Whether a store
% matches the current settings is checked later, by ``predictZarrStore``.
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
%   - **resumeStores** - [logical] for each image, true when its store holds an
%     interrupted prediction and the user chose "Resume"

    if nargin < 3 || isempty(storeKind); storeKind = 'model'; end
    if nargin < 4; allowResume = false; end
    resumeStores = false(size(zarrList));
    isScore = strcmp(storeKind, 'score');
    if isScore
        namePrefix = 'Score_';
        storeTitle = 'score stores';
        resultsFolder = 'ResultsScores';
        storeOpt = obj.ScoreExportOpt;
    else
        namePrefix = 'Labels_';
        storeTitle = 'model stores';
        resultsFolder = 'ResultsModels';
        storeOpt = obj.ZarrModelOpt;
    end
    cancelled = true;
    storePaths = {};
    if strcmp(storeOpt.ZarrFormat, 'v2')
        zarrFormat = 2;
    else
        zarrFormat = 3;
    end
    storeExtension = sprintf('.zarr%d', zarrFormat);

    % a store with fewer levels than the image must still hold the predicted level;
    % for images that are not zarr the index is not a level and the prediction is level 1
    if strcmp(obj.BatchOpt.ImageFilenameExtension{1}, 'ZARR')
        predictedLevel = obj.BatchOpt.BioformatsIndex{1};
    else
        predictedLevel = 1;
    end
    if ~isScore && obj.ZarrModelOpt.Levels > 0 && obj.ZarrModelOpt.Levels < predictedLevel
        mgsOpt.MsgBoxOnly = true;
        utils.dlgs.inputUniversalDlg(obj.view.gui, ...
            sprintf(['The model stores are set to %d pyramid level(s), but level %d is predicted\n\n' ...
            'Increase "Pyramid levels" in the settings of Model files (0 = as image)'], ...
            obj.ZarrModelOpt.Levels, predictedLevel), {}, {}, 'Wrong number of levels', mgsOpt);
        return;
    end

    if strcmp(storeOpt.Location, resultsFolder)
        outputFolder = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', resultsFolder);
    else
        outputFolder = fileparts(zarrList{1});
    end
    % the models were placed just before: score stores follow them when both go next to the images
    followModels = isScore && strcmp(obj.BatchOpt.P_ModelFiles{1}, 'Zarr3 (BigData model)') && ...
        strcmp(obj.ScoreExportOpt.Location, 'Next to images') && strcmp(obj.ZarrModelOpt.Location, 'Next to images');
    if followModels
        if isfield(obj.sessionSettings, 'lastModelStoreFolder') && isfolder(obj.sessionSettings.lastModelStoreFolder)
            outputFolder = obj.sessionSettings.lastModelStoreFolder;   % the folder the user chose for the models
        end
        selection = 'Write here';
    elseif strcmp(storeOpt.Location, 'Ask')
        selection = 'Choose folder...';
    else
        selection = uiconfirm(obj.view.gui, ...
            sprintf('%s will be written to\n\n%s\n\nas %s<image name>%s', [upper(storeTitle(1)) storeTitle(2:end)], outputFolder, namePrefix, storeExtension), ...
            ['Destination of ' storeTitle], ...
            'Options', {'Write here', 'Choose folder...', 'Cancel'}, ...
            'DefaultOption', 1, 'CancelOption', 3);
    end
    switch selection
        case 'Cancel'
            return;
        case 'Choose folder...'
            chosenFolder = uigetdir(outputFolder, sprintf('Select folder for %s (%s<image name>%s)', storeTitle, namePrefix, storeExtension));
            figure(obj.view.gui);
            if isequal(chosenFolder, 0); return; end
            outputFolder = chosenFolder;
    end

    storePaths = cell(size(zarrList));
    for fileId = 1:numel(zarrList)
        [~, imageName] = fileparts(zarrList{fileId});
        imageName = regexprep(imageName, '\.ome$', '', 'ignorecase');
        storePaths{fileId} = fullfile(outputFolder, [namePrefix imageName storeExtension]);
    end

    existingStores = storePaths(cellfun(@isfolder, storePaths));
    if ~isempty(existingStores)
        [~, existingNames, existingExt] = cellfun(@fileparts, existingStores, 'UniformOutput', false);
        existingNames = strcat(existingNames, existingExt);
        if numel(existingNames) > 10
            existingNames = [existingNames(1:10), {sprintf('... and %d more', numel(existingNames)-10)}];
        end
        interrupted = allowResume & cellfun(@(storePath) ...
            isfile(fullfile(storePath, controllers.MibDeep.PredictionRecordFile)), storePaths);
        if any(interrupted)
            selection = uiconfirm(obj.view.gui, ...
                sprintf(['These %s already exist in\n%s\n\n%s\n\n%d of them hold an interrupted prediction: ' ...
                'Resume continues it (with the same settings) and overwrites the others'], ...
                storeTitle, outputFolder, strjoin(existingNames, newline), nnz(interrupted)), ...
                [upper(storeTitle(1)) storeTitle(2:end) ' exist'], 'Options', {'Resume', 'Overwrite', 'Cancel'}, ...
                'DefaultOption', 1, 'CancelOption', 3, 'Icon', 'warning');
            resumeStores = interrupted & strcmp(selection, 'Resume');
        else
            selection = uiconfirm(obj.view.gui, ...
                sprintf('These %s already exist in\n%s\n\n%s\n\nOverwrite them?', storeTitle, outputFolder, strjoin(existingNames, newline)), ...
                [upper(storeTitle(1)) storeTitle(2:end) ' exist'], 'Options', {'Overwrite', 'Cancel'}, ...
                'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
        end
        if strcmp(selection, 'Cancel'); storePaths = {}; resumeStores = false(size(zarrList)); return; end
    end
    if ~isScore
        obj.sessionSettings.lastModelStoreFolder = outputFolder;   % where previewModels looks for the stores
    end
    cancelled = false;
end
