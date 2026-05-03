classdef MibModel < handle
    % MIBMODEL - the main model class of MIB.
    %

    properties
        I
        % variable for keeping instances of MibDataset
        Iraw
        % raw image source for Ishown
        Ishown
        % currently rendered images for visualization
        applySegmentationIn3D = false
        % apply some segmentation tools in 3D, updated by press of obj.cSelection.handles.applySegmentationIn3D
        autoFillSelection = true;
        % autofill the selection layer during segmentation, updated by press of obj.cSelection.handles.autoFillSelection
        currentDirectory
        % current working directory for MIB
        cpuParallelLimitMax
        % max number of parallel workers available
        differenceSelection = false
        % apply erode and dilate operations to get only a difference with the original selection, updated by press of obj.cSelection.handles.differenceSelection
        extensionRegistryLoad
        % class containing registry of filename extensions that can be loaded
        hideImage = false;
        % define whether or not display the image layer
        id
        % index of the selected dataset
        matlabVersion
        % version of Matlab
        mibGUI
        % handle to the main MIB window, to be used in child controllers to
        % align them relative to the main window (utils.moveWindowOutside)
        % place
        mibPath 
        % path to MIB installation directory also available in MibController
        mibVersion
        % char with the current version of MIB
        onFlyImageStretch =  false;
        % enable/disable live stretching of image intensities
        preferences
        % a structure with program preferences
        previouslySelectedDataset = 1
        % index of the previously selected dataset, to be toggled using Ctrl+E shortcut
        pythonEnv
        % python environment started from MIB
        selectedFileFilter = {'all known', 'all known'};
        % file filter selected in the Directory contents panel, cell, where
        % selectedFileFilter{1} - extension for the standard reader
        % selectedFileFilter{2} - extension for the bio-formats reader
        selectedFiles
        % cell array with the selected files in the Directory Contents panel
        Sets
        % structure with the set settings
        % .selectedSet -> index of the selected set
        % .names -> cell array with names of sets
        % .selectedDataset -> array of the datasets selected in each set
        % .datasetsInSet -> number of datasets in one set
        sessionSettings
        % a structure with settings for some tools used during the current session of MIB e.g.:
        % .automaticAlignmentOptions -> a structure used in mibAlignmentController
        % .guiImages - CData for images to be shown on some buttons
        showAnnotations = false;
        % enable/disable live stretching of image intensities
        showLines3D = false;
         % enable/disable show of 3D lines
        showMask = false;
        % define whether or not display the mask layer (used in obj.mibDataset.getRGBimage)
        showModel = false;
        % define whether or not display the model layer (used in obj.mibDataset.getRGBimage)
        Backup
        % variable for Undo history, instance of core.MibBackup
        useBioFormats = false;
        % use bio-formats reader
        linkedPairs = zeros(0,2)
        % n×2 double array of global dataset ID pairs that are linked for view synchronisation;
        % each row [idA, idB] means dataset idA and idB always show the same position.
        % Managed by controllers.MibActiveDataset.buffers_ContextMenu (link/unlink/close actions).
        % Queried by MibController.showImage for live propagation.
        connImaris = []
        % handle to an active IceImarisConnector connection; [] when not connected
    end

    properties (SetObservable)
        disableSegmentation = false;
        % when 1, segmentation tool callbacks return early (pan still works);
        % used during interactive ROI drawing — mirrors MIB2 mibModel.disableSegmentation
    end

    events
        AddMeasurement       % add a new measurement
        DatasetsPanelUpdate  % update widgets of the Datasets panel
        FrameChanged         % change of the current frame of 5D dataset (time)
        NewDataset           % MibModel loaded a new image, update MibController widgets
        ShowErrorDialog      % show error dialog, notified from widgets that have no access to MibView, requires core.ToggleEventData
        ShowImage            % render image in the Image View panel
        % ShowMask           % enable mask visualization -> use instead
        %                       obj.mibModel.showMask = true; 
        %                       eventdata = core.ToggleEventData({'selectionPanel'});
        %                       notify(obj.mibModel, 'UpdateGuiWidgets', eventdata);
        %                       notify(obj.mibModel, 'ShowImage');
        SliceChanged         % change of slices of the current dataset (depth)
        StopProtocol         % stop batch protocol from execution
        SyncBatch            % synchronize structure for batch actions
        Undo                 % notify controllers about an undo operation, carries core.ToggleEventData with the backup type string (e.g. 'lines3d')
        UpdateAnnotations    % update annotations, for example when they are removed or modified
        UpdateDatasetAxes    % request to update obj.I (MibDataset).axesX and obj.I (MibDataset).axesY during fit screen, resize, or new dataset drawing
        UpdateDialog         % request to update specific dialog, for example when Batch Processing is used, requires core.ToggleEventData, see BoundingBox.m
        UpdateFileList       % update the list of files
        UpdateGuiWidgets     % update all widgets of the main GUI
        UpdateImgInfo        % update image information, for example bounding box
        UpdateRecentDirsList % update the list of recent directories under Open Image button
        UpdateStatusBar      % update status bar
        UpdateToolbar        % request to update buttons in MIB toolbar (requires Options.fastpan = true; eventdata = core.ToggleEventData(Options); notify(obj, 'UpdateToolbar', eventdata);)
        UpdatedLines3D       % notify controllers about updated Lines3D data, carries core.ToggleEventData with the action string (e.g. 'Add node')
        UpdateUserScore      % update user stats
        AxesLimitsChanged    % notify listeners that the image axes limits were changed (zoom/pan), used by Snapshot controller
    end

    methods
        % declaration of functions in the external files, keep empty line in between for the doc generator

        addMaterial(obj, BatchOptIn)        % add a material to the current model; wrapper around core.MibDataset.addMaterial

        backup(obj, type, switch3d, getDataOptions)        % store the dataset for Undo

        clearLayer(obj, layer, sel_switch, BatchOptIn)        % clear the specified layer

        clearSelection(obj, sel_switch, BatchOptIn)           % clear the Selection layer (2D/3D/4D scope)

        deleteAnnotations(obj, BatchOptIn)        % Delete all annotations from the active dataset

        dilateImage(obj, BatchOptIn)       % dilate (expand) the selection, mask, or labels layer (2D or 3D strel, sequential or parallel)

        erodeImage(obj, BatchOptIn)        % erode the selection, mask, or labels layer (2D or 3D strel, sequential or parallel)

        fillSelectionOrMask(obj, targetLayer, BatchOptIn)   % fill holes in the selection or mask layer (2D/3D/4D scope, sequential or parallel)

        [xOut, yOut] = convertDataToMouseCoordinates(obj, x, y, mode)        % convert dataset coordinates to image axes (screen) coordinates

        [xOut, yOut, zOut, tOut] = convertMouseToDataCoordinates(obj, x, y, mode, permuteSw)        % convert coordinates under the mouse cursor to the coordinates of the dataset

        createModel(obj, ModelType, ModelMaterialNames, BatchOptIn)        % create a new model; wrapper around core.MibDataset.createModel

        status = datasetsSetsOps(obj, BatchOptIn)        % operations with sets of the model; compatible with the batch mode.

        exportDataset(obj, layerType, BatchOptIn)        % export image, mask, or labels layer to MATLAB workspace

        exportDatasetToImaris(obj, layerType, BatchOptIn)        % export image, mask, or model layer to Imaris via IceImarisConnector

        exportDatasetToMib(obj, layerType, BatchOptIn)           % copy mask or model layer to another MIB container

        dataset = getData2D(obj, type, slice_no, orient, col_channel, options)        % get a 2D slice from the current dataset; wrapper around core.MibDataset.getData2D

        dataset = getData3D(obj, type, time, orient, col_channel, options)        % get a 3D dataset from the current dataset; wrapper around core.MibDataset.getData3D

        dataset = getData4D(obj, type, orient, col_channel, options)        % get the complete 4D dataset; wrapper around core.MibDataset.getData4D

        id = getActiveId(obj)        % compute the correct dataset index from Sets.selectedSet (immune to mouse-motion corruption of obj.id)

        imageDeepCopy(obj, fromId, toId, options)        % deep-copy a MibDataset from one container slot to another, correctly handling handle sub-properties (image, labels, mask, selection, annotations, lines3D, measure, hROI)

        partnerId = getLinkedDataset(obj, id)        % return the global dataset ID of the linked partner, or [] if id is not part of any linked pair

        propertyValue = getImageProperty(obj, propertyName, id)        % get a property of the currently shown or specified MibDataset

        [axesX, axesY] = getAxesLimits(obj, id)        % get axes limits for the currently shown or id dataset

        magFactor = getMagFactor(obj, id)        % get magnification factor for the currently shown or specified dataset

        [imgRGB, imgRAW] = getRGBimage(obj, options, datasetId, sImgIn)        % generate RGB image from all layers that have to be shown on the screen.

        importDataset(obj, layerType, BatchOptIn)        % Import the image, mask, or model layer from the MATLAB main workspace.

        importDatasetFromMib(obj, layerType, BatchOptIn)        % Import the mask or model layer from another MIB container.

        initialize(obj)        % initialize the MibModel class

        interpolateImage(obj, imgType, intType, BatchOptIn)        % interpolate 'mask', 'selection', or 'labels' layer between slices using shape or line algorithm

        initializePreferences(obj)        % initialize and update MIB preferences from a file

        loadImages(obj, parameter, BatchOptIn)        % load images and arrange them into a stack

        loadModel(obj, model, BatchOptIn)        % load a segmentation model from file or import from workspace array; delegates to core.MibDataset.loadModel

        status = materialsActions(obj, action, BatchOptIn)        % collection of actions related to materials of the model (rename, add, insert, swap, reorder, remove)

        moveLayers(obj, SourceLayer, DestinationLayer, DatasetType, ActionType, BatchOptIn)        % move datasets between the layers (selection, mask, model)

        removeMaterial(obj, BatchOptIn)        % remove one or more materials from the current model; wrapper around core.MibDataset.removeMaterial

        renameMaterial(obj, BatchOptIn)        % rename one or all materials of the current model; wrapper around core.MibLabels.renameMaterial

        fnOut = save(obj, layerType, filename, BatchOptIn)        % Unified BatchOpt-compatible save: writes 'image', 'mask', or 'labels' layer. Handles directory/filename policies, [F] template expansion, SyncBatch event, and StopProtocol notification. See models.MibModel.save for full documentation and usage examples.

        fnOut = saveImage(obj, layerType, filename, BatchOptIn)        % Save image, mask, or labels layer; top-level BatchOpt-compatible wrapper.

        fnOut = saveLabels(obj, filename, BatchOptIn)        % Save the segmentation model (labels layer); thin wrapper around saveImage('labels', ...).

        setAxesLimits(obj, axesX, axesY, id)        % set axes limits for the currently shown or id dataset

        setDefaultColorPalette(obj, paletteName, colorsNo)        % set default color palette for materials of the model

        result = setData2D(obj, dataset, type, slice_no, orient, col_channel, options)        % set a 2D slice in the current dataset; wrapper around core.MibDataset.setData2D

        result = setData3D(obj, dataset, type, time, orient, col_channel, options)        % set a 3D dataset in the current dataset; wrapper around core.MibDataset.setData3D

        result = setData4D(obj, dataset, type, orient, col_channel, options)        % set the complete 4D dataset; wrapper around core.MibDataset.setData4D

        setMagFactor(obj, magFactor, id)        % set magnification for the currently shown or id dataset

        undo(obj, newIndex)        % undo/redo the recent changes (Ctrl+Z)

        function obj = MibModel(cpuParallelLimitMax, mibPath, mibVersion)
            % MIBMODEL - Construct an instance of this class.
            %
            % Syntax:
            %   function obj = MibModel(cpuParallelLimitMax, mibPath, mibVersion)
            %
            % Input Arguments:
            %   - **cpuParallelLimit** — integer, maximal number of possible workers for parallel processing
            %   - **mibPath** — char with the location of MIB3
            %   - **mibVersion** — char with the MIB version as
            %     ATTENTION! it is important to have the version number between "ver." and "/"
            %     Release syntax example: "ver. 2025.11 / 04.11.2025"
            %     Beta syntax example: "ver. 2025.11 (beta 4) / 04.11.2025"
            %
            
            arguments
                % https://se.mathworks.com/help/releases/R2025a/matlab/input-and-output-arguments.html
                cpuParallelLimitMax (1,1) double {mustBePositive, mustBeInteger} = 1
                mibPath (1,:) char = ''
                mibVersion (1,:) char = 'ver. 2025.12 / 05.12.2025 (alpha)'
            end
            
            obj.cpuParallelLimitMax = cpuParallelLimitMax;
            obj.mibPath = mibPath;
            obj.mibVersion = mibVersion;
            obj.initialize();
        end
    end
end
