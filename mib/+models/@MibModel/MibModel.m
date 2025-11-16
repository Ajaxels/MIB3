classdef MibModel < handle
    % classdef MibModel < handle
    % the main model class of MIB

    properties
        I
        % variable for keeping instances of MibDataset
        currentDirectory
        % current working directory for MIB
        cpuParallelLimitMax
        % max number of parallel workers available
        id
        % index of the selected dataset
        matlabVersion
        % version of Matlab
        mibPath 
        % path to MIB installation directory also available in MibController
        myPath
        % current working directory
        preferences
        % a structure with program preferences
        pythonEnv
        % python environment started from MIB
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
    end

    events
        ShowErrorDialog     % show error dialog, notified from widgets that have no access to MibView, requires core.ToggleEventData
        DatasetsPanelUpdate % update widgets of the Datasets panel
        UpdateDatasetAxes   % request to update obj.I (MibDataset).axesX and obj.I (MibDataset).axesY during fit screen, resize, or new dataset drawing
    end

    methods
        % declaration of functions in the external files, keep empty line in between for the doc generator
        
        status = datasetsSetsOps(obj, BatchOptIn) % operations with sets of the  model. Compatible with the batch mode.

        function obj = MibModel(cpuParallelLimitMax, mibPath)
            % function obj = MibModel(cpuParallelLimitMax, mibPath)
            % Construct an instance of this class
            %
            % Parameters:
            % cpuParallelLimit: integer, maximal number of possible workers for parallel processing
            % mibPath: char with the location of MIB3

            arguments
                % https://se.mathworks.com/help/releases/R2025a/matlab/input-and-output-arguments.html
                cpuParallelLimitMax (1,1) double {mustBePositive, mustBeInteger} = 1
                mibPath (1,:) char = ''
            end
            
            obj.cpuParallelLimitMax = cpuParallelLimitMax;
            obj.mibPath = mibPath;
            obj.initialize();
        end

        function initialize(obj)
            obj.currentDirectory = '\';   % define working directory
            obj.id = 1;         % index of the current dataset
            
            % define default Set
            obj.Sets.selectedSet = [];  % selected set in obj.view.handles.panels.datasets.handles.sets
            obj.Sets.names = {};        % cell array with names of the sets
            obj.Sets.datasetTypes = {};        % cell matrix with datasetTypes in sets, obj.Sets.datasetTypes{setId, datasetId}, where datasetId = 1...10
            obj.Sets.selectedDataset = []; % array of the selected datasets in the sets
            obj.Sets.datasetsInSet = 10; % number of dataset in each set, defined by number of buffer buttons in the Datasets panel
            
            % initialize MIB with 10 dummy datasets
            BatchOpt = struct('Mode', {'Add set'}, 'DatasetType', {'Std'}, 'SetName', 'Set 1');
            obj.datasetsSetsOps(BatchOpt);

            %obj.newDatasetSwitch = 0;
            %obj.showAllMaterials = 1;   % display all materials of the model
            %obj.disableSegmentation = 0;    % disable segmentation switch
            %obj.storedSelection = [];   % initialize stored selection
            %obj.connImaris = [];    % empty connection to Imaris
            obj.sessionSettings = struct();     % current session settings
            %obj.mibPrevId = 1;     % index of the previous dataset
            
            
            %obj.U = mibImageUndo();    % create instance for keeping undo information
            obj.pythonEnv = [];     % Python environment for MIB
        end

    end
end