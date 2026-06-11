function initialize(obj)
% INITIALIZE - Initialize the MibModel class.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.initialize()
%
% Initializes the MibModel class by setting up default directories,
% datasets, and session parameters. Creates the initial dataset set
% with dummy datasets and initializes core components like the undo
% system and extension registry.
%
% Input Arguments:
%   none
%
% Usage:
%   **Example 1** — initialize the model after construction
%
%   .. code-block:: matlab
%
%      obj = models.MibModel();
%      obj.initialize();
%

arguments (Input)
    obj models.MibModel
end

%% initialize preferences
obj.initializePreferences();

% define default sessionSettings
obj.sessionSettings = utils.defaults.generateSessionSettings();


%% define MibModel properties
obj.id = 1;         % index of the current dataset
obj.extensionRegistryLoad = io.ExtensionRegistryLoad; % registry of filename extensions
% update mibModel parameters
obj.currentDirectory = obj.preferences.System.Dirs.LastPath;  % define current working directory

% get the current version of Matlab; parse version() output ('26.1.0.123456')
% instead of ver('matlab') which takes ~900 ms scanning all toolboxes;
% str2double of the 'major.minor' substring keeps the same numeric semantics
% (conversion is not correct as version named as 9.8, 9.9, 9.10, 26.10 .....)
obj.matlabVersion = str2double(regexp(version, '^\d+\.\d+', 'match', 'once'));

%obj.newDatasetSwitch = 0;
%obj.showAllMaterials = 1;   % display all materials of the model
%obj.disableSegmentation = 0;    % disable segmentation switch
obj.storedSelection = [];   % initialize stored selection buffer
obj.connImaris = [];    % empty connection to Imaris

obj.Backup = core.MibBackup();    % create instance for keeping undo information
% seed undo settings from the saved preferences; otherwise the constructor
% defaults (enableSwitch=1, max3d_steps=1) override the user's Undo prefs for
% the whole session unless the Preferences dialog is opened. In particular a
% saved Undo.Max3dUndoHistory==0 would still keep max3d_steps=1, so every 3D
% operation (e.g. Resample) would do a full-volume backup instead of bailing.
obj.Backup.enableSwitch = logical(obj.preferences.Undo.Enable);
obj.Backup.setNumberOfHistorySteps(obj.preferences.Undo.MaxUndoHistory, obj.preferences.Undo.Max3dUndoHistory);
obj.pythonEnv = [];     % Python environment for MIB

%% define default Set
obj.Sets.selectedSet = [];  % selected set in obj.view.handles.panels.activeDataset.handles.sets
obj.Sets.names = {};        % cell array with names of the sets
obj.Sets.datasetTypes = {};        % cell matrix with datasetTypes in sets, obj.Sets.datasetTypes{setId, datasetId}, where datasetId = 1...10
obj.Sets.selectedDataset = []; % array of the selected datasets in the sets
obj.Sets.datasetsInSet = 10; % number of dataset in each set, defined by number of buffer buttons in the Datasets panel

% reset linked-view pairs (global-ID pairs of linked datasets)
obj.linkedPairs = zeros(0, 2);

% initialize MIB with 10 dummy datasets
BatchOpt = struct('Mode', {'Add set'}, 'DatasetType', {'Standard'}, 'SetName', 'Set 1');
obj.datasetsSetsOps(BatchOpt);


end