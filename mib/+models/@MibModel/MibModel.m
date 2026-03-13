classdef MibModel < handle
    % classdef MibModel < handle
    % the main model class of MIB

    properties
        I
        % variable for keeping instances of MibDataset
        Iraw
        % raw image source for Ishown
        Ishown
        % currently rendered images for visualization
        currentDirectory
        % current working directory for MIB
        cpuParallelLimitMax
        % max number of parallel workers available
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
        Undo
        % variable for Undo history
        useBioFormats = false;
        % use bio-formats reader

    end

    events
        AddMeasurement       % add a new measurement
        DatasetsPanelUpdate  % update widgets of the Datasets panel
        FrameChanged         % change of the current frame of 5D dataset (time)
        NewDataset           % MibModel loaded a new image, update MibController widgets
        ShowErrorDialog      % show error dialog, notified from widgets that have no access to MibView, requires core.ToggleEventData
        ShowImage            % render image in the Image View panel
        SliceChanged         % change of slices of the current dataset (depth)
        StopProtocol         % stop batch protocol from execution
        SyncBatch            % synchronize structure for batch actions
        UpdateDatasetAxes    % request to update obj.I (MibDataset).axesX and obj.I (MibDataset).axesY during fit screen, resize, or new dataset drawing
        UpdateFileList       % update the list of files
        UpdateGuiWidgets     % update all widgets of the main GUI
        UpdateRecentDirsList % update the list of recent directories under Open Image button
        UpdateToolbar        % request to update buttons in MIB toolbar (requires Options.fastpan = true; eventdata = core.ToggleEventData(Options); notify(obj, 'UpdateToolbar', eventdata);)
    end

    methods
        % declaration of functions in the external files, keep empty line in between for the doc generator

        clearLayer(obj, layer, sel_switch, BatchOptIn)        % clear the specified layer

        [xOut, yOut, zOut, tOut] = convertMouseToDataCoordinates(obj, x, y, mode, permuteSw)        % convert coordinates under the mouse cursor to the coordinates of the dataset

        status = datasetsSetsOps(obj, BatchOptIn) % operations with sets of the  model; compatible with the batch mode.

        fnOut = save(obj, layerType, filename, BatchOptIn)        % Unified BatchOpt-compatible save: writes 'image', 'mask', or 'labels' layer. Handles directory/filename policies, [F] template expansion, SyncBatch event, and StopProtocol notification. See models.MibModel.save for full documentation and usage examples.

        [axesX, axesY] = getAxesLimits(obj, id)        % get axes limits for the currently shown or id dataset
        
        [imgRGB, imgRAW] = getRGBimage(obj, options, datasetId, sImgIn)  % generate RGB image from all layers that have to be shown on the screen.

        magFactor = getMagFactor(obj, id)        % get magnification factor for the currently shown or specified dataset
        
        loadImages(obj, parameter, BatchOptIn)        % load images and arrange them into a stack

        initialize(obj)        % initialize the MibModel class

        initializePreferences(obj)            % initialize and update MIB preferences from a file

        fnOut = saveImage(obj, layerType, filename, BatchOptIn)        % Save image, mask, or labels layer; top-level BatchOpt-compatible wrapper.

        setAxesLimits(obj, axesX, axesY, id)        % set axes limits for the currently shown or id dataset
        
        setMagFactor(obj, magFactor, id)        % set magnification for the currently shown or id dataset

        function obj = MibModel(cpuParallelLimitMax, mibPath, mibVersion)
            % function obj = MibModel(cpuParallelLimitMax, mibPath, mibVersion)
            % Construct an instance of this class
            %
            % Parameters:
            % cpuParallelLimit: integer, maximal number of possible workers for parallel processing
            % mibPath: char with the location of MIB3
            % mibVersion: char with the MIB version as
            %       ATTENTION! it is important to have the version number between "ver." and "/" 
            %       Release syntax example: "ver. 2025.11 / 04.11.2025"
            %       Beta syntax example: "ver. 2025.11 (beta 4) / 04.11.2025"
            
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