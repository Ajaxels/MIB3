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
        developerMode
        % logical switch to turn on the developer mode, in this mode, the
        % tooltip starts with the handle of the widget
        id
        % index of the selected dataset
        mibPath 
        % path to MIB installation directory also available in MibController
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
        ShowErrorDialog % show error dialog, notified from widgets that have no access to MibView, requires core.ToggleEventData
        DatasetsPanelUpdate % update widgets of the Datasets panel
    end

    methods
        % declaration of functions in the external files, keep empty line in between for the doc generator
        
        status = datasetsSetsOps(obj, BatchOptIn) % operations with sets of the  model. Compatible with the batch mode.

        function obj = MibModel(cpuParallelLimitMax)
            % function obj = MibModel(cpuParallelLimitMax)
            % Construct an instance of this class
            %
            % Parameters:
            % cpuParallelLimit: integer, maximal number of possible workers for parallel processing

            arguments
                % https://se.mathworks.com/help/releases/R2025a/matlab/input-and-output-arguments.html
                cpuParallelLimitMax (1,1) double {mustBePositive, mustBeInteger} = 1
            end
            
            obj.cpuParallelLimitMax = cpuParallelLimitMax;
            obj.initalize();
        end

        function initalize(obj)
            %obj.maxId = 10;  % define maximal number of datasets (equal to number of mibBufferToggle buttons in the Directory contents panel)
            obj.currentDirectory = '\';   % define working directory
            obj.id = 1;         % index of the current dataset
            obj.mibPath = [];   % path to MIB installation directory
            % define default Set
            obj.Sets.selectedSet = [];
            obj.Sets.names = {}; 
            obj.Sets.selectedDataset = [];
            obj.Sets.datasetsInSet = 10; % number of dataset in each set, defined by number of buffer buttons in the Datasets panel
            
            % initialize MIB with 10 dummy datasets
            BatchOpt = struct('Mode', {'Add set'}, 'SetName', 'Set 1');
            obj.datasetsSetsOps(BatchOpt);

            %obj.newDatasetSwitch = 0;
            %obj.showAllMaterials = 1;   % display all materials of the model
            %obj.disableSegmentation = 0;    % disable segmentation switch
            %obj.storedSelection = [];   % initialize stored selection
            %obj.connImaris = [];    % empty connection to Imaris
            obj.sessionSettings = struct();     % current session settings
            %obj.mibPrevId = 1;     % index of the previous dataset
            
            
            %obj.U = mibImageUndo();    % create instanse for keeping undo information
            obj.pythonEnv = [];     % Python environment for MIB
            obj.developerMode = true;
        end

    end
end