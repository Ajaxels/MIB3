function datasetTypeChange_Callback(obj, hWidget, hData)
% DATASETTYPECHANGE_CALLBACK - callback for selection of entry in Datasets.datasetType dropdown to choose the type of the dataset stored.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.datasetTypeChange_Callback(hWidget, hData)
%
% in the selected buffer/container.
% Available options
% - Standard standard MIB dataset, loaded completely into memory
% - Virtual the virtual mode, when the data is loaded from disk on demand
% - BigData to work with pyramidal/chunked data formats [for future development]
%
% Input Arguments:
%   - **hWidget** - handle to the pressed widget
%   - **hData** - handle to supporting data class
%

arguments (Input)
    obj controllers.MibActiveDataset
    hWidget matlab.ui.control.DropDown
    hData matlab.ui.eventdata.ValueChangedData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibActiveDataset.datasetTypeChange_Callback: selection of "obj.handles.panels.activeDataset.handles.datasetType" -> "%s"\n',  hWidget.Value);
end

% Special path: convert an OPEN (Standard/Virtual) dataset to BigData by writing
% it as an OME-Zarr v3 pyramid and reopening it in BigData mode - rather than the
% generic "close current + start blank" switch below. Only when a real image is open.
convId = obj.mibModel.getActiveId();
convDs = obj.mibModel.I{convId};
% A "real" (user-loaded) dataset - as opposed to an empty placeholder slot
% ('none.tif'), a non-existent image, or one of the default asset images
% (assets/images/default.png|.h5) loaded as a dummy when a buffer is initialized
% or its mode switched. Only a real dataset needs a "will be closed" warning.
assetsImagesDir = fullfile(obj.mibModel.mibPath, 'assets', 'images');
isRealImage = convDs.image.exists && ...
    ~strcmp(convDs.image.filename, 'none.tif') && ...
    ~startsWith(lower(convDs.image.filename), lower(assetsImagesDir));
if strcmp(hWidget.Value, 'BigData') && ~strcmp(convDs.datasetType, 'BigData') && isRealImage
    questOpt = struct('Icon', 'puffin_question', 'WindowWidth', 540, 'WindowHeight', 240);
    if ~isempty(obj.mibModel.mibPath); questOpt.mibPath = obj.mibModel.mibPath; end
    sel = utils.dlgs.inputQuestDlg(obj.view.gui, ...
        sprintf(['A dataset is currently open. Switch to BigData by:\n\n' ...
        ' \x2022 "New (default)": discard the open dataset and start an empty BigData dataset\n' ...
        ' \x2022 "Convert current": write the open image as an OME-Zarr v3 pyramid on disk and reopen it in BigData mode\n\n' ...
        'BigData is browse-only until you create a model.']), 'Switch to BigData', ...
        'New (default)', 'Convert current', 'Cancel', 'New (default)', questOpt);
    switch sel
        case {'Cancel', ''}
            hWidget.Value = hData.PreviousValue;
            return;
        case 'New (default)'
            % discard the open dataset and start an empty BigData placeholder
            defH5 = {fullfile(obj.mibModel.mibPath, 'assets', 'images', 'default.h5')};
            updatedMode = obj.mibModel.I{convId}.switchDatasetMode(3, ...
                obj.mibModel.preferences.System.EnableSelection, defH5);
            if isempty(updatedMode) || updatedMode ~= 3
                hWidget.Value = hData.PreviousValue;
                return;
            end
            obj.mibModel.Sets.datasetTypes{obj.mibModel.Sets.selectedSet, ...
                obj.mibModel.Sets.selectedDataset(obj.mibModel.Sets.selectedSet)} = 'BigData';
            notify(obj.mibModel, 'NewDataset');
            obj.mibController.cDirContents.updateFileList_Callback();
            return;
        case 'Convert current'
            % fall through to the conversion below
        otherwise
            % dialog closed / unexpected - abort the switch
            hWidget.Value = hData.PreviousValue;
            return;
    end

    [imgPath, imgStem] = fileparts(convDs.image.filename);
    if isempty(imgPath); imgPath = obj.mibModel.currentDirectory; end
    if isempty(imgStem); imgStem = 'dataset'; end
    [zFile, zDir] = uiputfile({'*.zarr3', 'OME-Zarr v3 (*.zarr3)'}, ...
        'Save BigData (zarr3) as', fullfile(imgPath, [imgStem '.zarr3']));
    if isequal(zFile, 0); hWidget.Value = hData.PreviousValue; return; end
    outPath = fullfile(zDir, zFile);
    % datasetInfo drives the smart chunk/shard/strategy defaults (WSI vs. isotropic vs.
    % anisotropic 3-D) - without it optionsDialog silently falls back to the isotropic
    % preset regardless of the dataset's actual voxel size, same as the Export dialogs.
    datasetInfo = struct('Y', convDs.image.height, 'X', convDs.image.width, ...
        'Z', convDs.image.depth, 'pixSize', convDs.image.pixSize);
    zOpt = io.savers.Zarr3Saver.optionsDialog(obj.view.gui, obj.mibModel.mibPath, false, datasetInfo);
    if isempty(zOpt); hWidget.Value = hData.PreviousValue; return; end   % cancelled settings

    wb = uiprogressdlg(obj.view.gui, 'Title', 'Convert to BigData', ...
        'Message', 'Writing OME-Zarr v3 pyramid, please wait...', 'Indeterminate', 'on');
    try
        io.savers.Zarr3Saver.exportDataset(obj.mibModel, convId, outPath, zOpt);   % write (reads old dataset)
        % reopen the written store as BigData into this buffer
        lo = struct('datasetMode', 'BigData', 'ParentFigure', obj.mibModel.getProgressBarParent(), ...
            'showWaitbar', false, 'mibPath', obj.mibModel.mibPath);
        loader = io.loaders.Zarr3VirtualSetupLoader(lo);
        [imginfo, files] = loader.loadMetadata({outPath}, lo);
        [img, imginfo] = loader.loadImages(files, imginfo, lo);
        obj.mibModel.I{convId}.initialize(img, imginfo, 'BigData', [], false);
        delete(wb);
    catch ME
        if isvalid(wb); delete(wb); end
        utils.dlgs.showErrorDialog(obj.view.gui, ME.message, 'Convert to BigData failed');
        hWidget.Value = hData.PreviousValue;
        return;
    end

    % update the panel type cache and refresh
    obj.mibModel.Sets.datasetTypes{obj.mibModel.Sets.selectedSet, ...
        obj.mibModel.Sets.selectedDataset(obj.mibModel.Sets.selectedSet)} = 'BigData';
    notify(obj.mibModel, 'NewDataset');
    obj.mibController.cDirContents.updateFileList_Callback();
    return;
end

% Special path: BigData → Standard conversion with choice of how to handle the data
if strcmp(hWidget.Value, 'Standard') && strcmp(convDs.datasetType, 'BigData') && isRealImage
    questOpt = struct('Icon', 'puffin_question', 'WindowWidth', 560, 'WindowHeight', 250);
    if ~isempty(obj.mibModel.mibPath); questOpt.mibPath = obj.mibModel.mibPath; end
    sel = utils.dlgs.inputQuestDlg(obj.view.gui, ...
        sprintf(['A BigData dataset is currently open. Switch to Standard by:\n\n' ...
        ' \x2022 "New (default)": discard and start an empty Standard dataset\n' ...
        ' \x2022 "Load into memory": read a selected pyramid level into memory\n\n' ...
        'The BigData file on disk is not modified.']), 'Switch to Standard', ...
        'New (default)', 'Load into memory', 'Cancel', 'New (default)', questOpt);
    switch sel
        case {'Cancel', ''}
            hWidget.Value = hData.PreviousValue;
            return;
        case 'New (default)'
            % fall through to the generic switch below (loads default.png placeholder)
        case 'Load into memory'
            zarrPath = convDs.image.filename;
            lo = struct('datasetMode', 'Standard', 'ParentFigure', obj.view.gui, ...
                'showWaitbar', true, 'mibPath', obj.mibModel.mibPath);
            % The store was opened by whichever loader its format needed, so the
            % buffer may hold either version and the conversion has to probe rather
            % than assume. Hardcoding the v3 loader here sent every zarr v2 store
            % (the OME-Zarr / OpenOrganelle default) looking for a zarr.json that
            % does not exist. resolveLoader cannot be used: it refuses zarr in
            % Standard mode, which is exactly what this path is doing on purpose.
            if strcmp(io.ExtensionRegistryLoad.detectZarrFormatExtension(zarrPath), 'zarr2')
                loader = io.loaders.Zarr2VirtualSetupLoader(lo);
            else
                loader = io.loaders.Zarr3VirtualSetupLoader(lo);
            end
            % A BigData label overlay is a view onto a second pyramid rather than
            % pixels in this buffer, and the initialize() below replaces obj.labels
            % with an empty placeholder. Take the handle now so the model can be
            % read into memory beside the image; the store stays open on it.
            overlayLabels = [];
            if convDs.modelExist && isa(convDs.labels, 'core.MibBigDataLabelsIndex')
                overlayLabels = convDs.labels;
            end

            try
                [imginfo, files] = loader.loadMetadata({zarrPath}, lo);
                [img, imginfo]   = loader.loadImages(files, imginfo, lo);
            catch ME
                utils.dlgs.showErrorDialog(obj.view.gui, ME.message, 'Load into memory failed');
                hWidget.Value = hData.PreviousValue;
                return;
            end
            if isempty(img)
                hWidget.Value = hData.PreviousValue;
                return;
            end
            obj.mibModel.I{convId}.initialize(img, imginfo, 'Standard', [], true);

            % ---- bring the label overlay across as an ordinary model ---------
            % The model type follows the overlay's own (65535 / 4294967295) and is
            % never the packed 63-material one: an instance segmentation's ids run
            % into the thousands and packing would fold every one of them onto a
            % material below 64, with the mask and selection bits set as a bonus.
            if ~isempty(overlayLabels)
                % The loader picks the level in its own dialog and does not report
                % which, but the level is identifiable from the dimensions it
                % returned - and the labels have to be read at that same level.
                loadedDims = double([imginfo{"Height"}, imginfo{"Width"}, imginfo{"Depth"}]);
                levelIndex = find(all(files.levelImageSizes == loadedDims, 2), 1);
                if isempty(levelIndex); levelIndex = 1; end
                levelIndex = min(levelIndex, size(overlayLabels.imageScaleFactors, 1));
                magFactor  = overlayLabels.imageScaleFactors(levelIndex, 1);
                scaleZ     = overlayLabels.imageScaleFactors(levelIndex, 3);

                % renderPerObject decides how the overlay is DRAWN; a conversion
                % wants the ids themselves, so it is lifted for the read.
                previousRenderPerObject = overlayLabels.renderPerObject;
                overlayLabels.renderPerObject = true;

                wbModel = uiprogressdlg(obj.view.gui, 'Title', 'Convert to Standard', ...
                    'Message', sprintf('Reading the model into memory\n%d x %d x %d, please wait...', ...
                        loadedDims(2), loadedDims(1), loadedDims(3)), 'Cancelable', 'on');
                labelVolume = zeros(loadedDims, overlayLabels.dataClass);
                modelFailure = '';
                try
                    for z = 1:loadedDims(3)
                        if wbModel.CancelRequested
                            modelFailure = 'cancelled';
                            break;
                        end
                        wbModel.Value = z / loadedDims(3);
                        % getData takes full-resolution coordinates, so one output
                        % plane is the span of full-res slices that level plane covers -
                        % the same span the image's own plane z covers, which is what
                        % lines the two up index for index.
                        slice = overlayLabels.getData('labels', 3, [], ...
                            struct('magFactor', magFactor, 'z', [(z-1)*scaleZ + 1, z*scaleZ]));
                        % The gather sizes a level as ceil(fullDim/scale) while a store
                        % may have written floor, so the read can be one row, column or
                        % plane larger than the image it has to match. The overhang is
                        % at the far edge, so the model takes the leading block; sizes
                        % that disagree anywhere else would be a registration fault.
                        labelVolume(:, :, z) = slice(1:loadedDims(1), 1:loadedDims(2));
                    end
                catch ME
                    modelFailure = ME.message;
                end
                overlayLabels.renderPerObject = previousRenderPerObject;
                delete(wbModel);

                if isempty(modelFailure)
                    ds = obj.mibModel.I{convId};
                    ds.createModel(overlayLabels.maxMaterials);
                    obj.mibModel.setData3D(labelVolume, 'labels', 1, 3, [], ...
                        struct('id', convId, 'blockModeSwitch', 0));
                    ds.labels.materialsCount = double(max(labelVolume(:)));
                else
                    % No partial model: a half-read one looks like a segmentation
                    % that lost its objects rather than one that was interrupted.
                    if strcmp(modelFailure, 'cancelled')
                        modelNote = 'reading the model was cancelled';
                    else
                        modelNote = sprintf('the model could not be read:\n%s', modelFailure);
                    end
                    utils.dlgs.showErrorDialog(obj.view.gui, sprintf( ...
                        ['The image was loaded into memory, but %s.\n\n' ...
                         'The dataset is now Standard and holds the image only.'], modelNote), ...
                        'Model not converted');
                end
            end

            obj.mibModel.Sets.datasetTypes{obj.mibModel.Sets.selectedSet, ...
                obj.mibModel.Sets.selectedDataset(obj.mibModel.Sets.selectedSet)} = 'Standard';
            notify(obj.mibModel, 'NewDataset');
            obj.mibController.cDirContents.updateFileList_Callback();
            return;
        otherwise
            hWidget.Value = hData.PreviousValue;
            return;
    end
end

% confirm the operation - only when a real dataset is loaded. Switching the type
% of an empty placeholder / dummy buffer closes nothing, so no warning is needed.
if isRealImage
    selection = uiconfirm(obj.view.gui, ...
        sprintf('You are going to switch to the %s mode\nThe current dataset will be closed!', hWidget.Value), ...
        'Switch dataset mode', 'Icon', 'warning', 'DefaultOption', 2);
    if strcmp(selection, 'Cancel')
        hWidget.Value = hData.PreviousValue;
        return;
    end
end

initWithImage = [];
switch hWidget.Value % Get the selected dataset type from the dropdown
    case 'Standard'
        % Set the standard mode when dataset is loaded into memory
        fn = fullfile(obj.mibModel.mibPath, 'assets', 'images', 'default.png');
        initWithImage = imread(fn);
        newMode = 1;
    case 'Virtual'
        % Set the virtual mode
        newMode = 2;
        initWithImage = {fullfile(obj.mibModel.mibPath, 'assets', 'images', 'default.h5')};
    case 'BigData'
        % BigData mode: on-demand reader for pyramidal/chunked datasets.
        % Start from a blank placeholder; the user then opens an OME-Zarr v3
        % pyramid via File -> Open to populate it.
        newMode = 3;
        initWithImage = {fullfile(obj.mibModel.mibPath, 'assets', 'images', 'default.h5')};
end

updatedMode = obj.mibModel.I{obj.mibModel.id}.switchDatasetMode(newMode, obj.mibModel.preferences.System.EnableSelection, initWithImage);
if updatedMode~=newMode; return; end

% update obj.mibModel.Sets.datasetTypes
obj.mibModel.Sets.datasetTypes{obj.mibModel.Sets.selectedSet, obj.mibModel.Sets.selectedDataset(obj.mibModel.Sets.selectedSet)} = hWidget.Value;

% new dataset and update widgets
notify(obj.mibModel, 'NewDataset');

% update the list of files
obj.mibController.cDirContents.updateFileList_Callback();
