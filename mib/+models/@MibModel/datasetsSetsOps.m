function status = datasetsSetsOps(obj, BatchOptIn)
% DATASETSSETSOPS - Operations with sets of the model.
%
% Syntax:
%   .. code-block:: matlab
%
%      status = obj.datasetsSetsOps()
%      status = obj.datasetsSetsOps(BatchOptIn)
%
% Compatible with the batch processing mode.
%
% Input Arguments:
%   - **BatchOptIn** — *(optional)* structure with parameters; when NaN,
%     returns default options via "SyncBatch" event
%   - ``.Mode`` — cell string, operation to perform:
%   - ``'Select set'`` — select the set in the Datasets panel dropdown
%   - ``'Add set'`` — add a new set (10 new datasets) into the model
%   - ``'Rename set'`` — rename the current set
%   - ``'Remove set'`` — remove the current set
%   - ``.SetName`` — char, set name to select, rename, or remove; when empty a dialog appears
%
% Output Arguments:
%   - **status** — logical, ``true`` when the operation completed successfully
%
% Usage:
%   **Example 1** — select a set by name
%
%   .. code-block:: matlab
%
%      BatchOpt.Mode    = {'Select set'};
%      BatchOpt.SetName = 'Set 2';
%      obj.mibModel.datasetsSetsOps(BatchOpt);
%
%   **Example 2** — add a new set
%
%   .. code-block:: matlab
%
%      BatchOpt.Mode    = {'Add set'};
%      BatchOpt.SetName = 'Experiment B';
%      obj.mibModel.datasetsSetsOps(BatchOpt);
%

status = false;

% --------------- Batch operation logic ---------------
% specify default BatchOptIn
BatchOpt = struct();
BatchOpt.Mode = {'Select set'};     % default operation
BatchOpt.Mode{2} = {'Select set', 'Add set', 'Rename set', 'Remove set'};  % only the single option is available for the batch mode so far
BatchOpt.DatasetType = {'Standard'}; % default dataset type: Standard
BatchOpt.DatasetType{2} = {'Standard', 'Virtual', 'BigData'}; % available dataset types

if isempty(obj.Sets.selectedSet) % initialization of MIB
    BatchOpt.SetName = 'Set 1';  
else    
    BatchOpt.SetName = obj.Sets.names{obj.Sets.selectedSet}; % current set name
end
% tooltips that will accompany the BatchOpt
BatchOpt.mibBatchTooltip.Mode = sprintf('Select required operation with the sets');
BatchOpt.mibBatchTooltip.DatasetType = sprintf('Dataset type');
BatchOpt.mibBatchTooltip.SetName = sprintf('Specify the (new) set name');

% add section name and action name for the batch tool
BatchOpt.mibBatchSectionName = 'Panels -> Datasets';
BatchOpt.mibBatchActionName = 'Set operations';

if nargin == 2  % batch mode
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)     % when varargin{4} == NaN return possible settings
            % trigger SyncBatch event to send BatchOptInOut to mibBatchController
            eventdata = ToggleEventData(BatchOpt);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        else
            errordlg(sprintf('A structure as the 2nd parameter is required!'));
        end
        return;
    else
        % add/update BatchOpt with the provided fields in BatchOptIn
        % combine fields from input and default structures
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end
end

noSets = numel(obj.Sets.names); % current number of sets

switch BatchOpt.Mode{1}
    case 'Select set'
        %fprintf('models.mibModel.datasetsSetsOps: Select set -> %s\n', BatchOpt.SetName);
        newSelectedSet = find(ismember(obj.Sets.names, BatchOpt.SetName));
        if obj.Sets.selectedSet == newSelectedSet; return; end

        obj.Sets.selectedSet = newSelectedSet;
        
        % update all widgets of the Datasets panel
        notify(obj, 'DatasetsPanelUpdate');
        
        %notify(obj, 'UpdateGuiWidgets');
    case 'Add set'
        %fprintf('models.mibModel.datasetsSetsOps: Add set: %s \n', BatchOpt.SetName);

        if ismember(BatchOpt.SetName, obj.Sets.names)
            ErrorDlgOpt.winTitle = 'Error in MibModel.datasetsSetsOps';
            ErrorDlgOpt.optionalPrefix = sprintf('!!! Error !!!\n\nThe sets should have unique names!');
            eventdata = core.ToggleEventData(ErrorDlgOpt);
            notify(obj, 'ShowErrorDialog', eventdata);
            return;
        end

        initializationSwitch = false;
        if isempty(obj.Sets.names)
            % when true MIB is initialized, skip "notify(obj, 'UpdateDatasetAxes', eventdata);"
            % will be initialized in "doPostInitializationTasks"
            initializationSwitch = true;
        end

        % update obj.Sets
        obj.Sets.names = [obj.Sets.names; BatchOpt.SetName];
        obj.Sets.selectedSet = numel(obj.Sets.names);
        obj.Sets.selectedDataset = [obj.Sets.selectedDataset; 1]; % add 1 as the index of the selected dataset for the added set
        obj.Sets.datasetTypes = [obj.Sets.datasetTypes; repmat(BatchOpt.DatasetType(1), [1 obj.Sets.datasetsInSet])];

        % get index of the next dataset
        nextDatasetIndex = (numel(obj.Sets.names)-1) * obj.Sets.datasetsInSet + 1;
        % read the default image once; MibDataset copies the array, and
        % dictionary is a value type, so both can be shared between iterations
        fn = fullfile(obj.mibPath, 'assets', 'images', 'default.png');
        I = imread(fn);
        meta = dictionary();
        for i=nextDatasetIndex:nextDatasetIndex+obj.Sets.datasetsInSet-1  % initialize mibDataset

            % update MibDataset using the default values
            if ~isempty(obj.preferences) % standard call when obj.preferences is initialized
                % check whether the selection is enabled or not
                if obj.preferences.System.EnableSelection
                    obj.I{i} = core.MibDataset(I, meta, BatchOpt.DatasetType{1}, 'labels63');
                else
                    obj.I{i} = core.MibDataset(I, meta, BatchOpt.DatasetType{1}, 'imageOnly');
                    obj.I{i}.enableSelection = false;
                end

                % update obj.I{i} properties
                obj.I{i}.labels.materialColors = obj.preferences.Colors.ModelMaterialColors; % update default model colors
                % update default LUT colors
                if obj.I{i}.image.colors < size(obj.preferences.Colors.LUTColors, 1)
                    obj.I{i}.image.lutColors = obj.preferences.Colors.LUTColors;
                end

                % update all widgets of the Datasets panel
                if ~initializationSwitch
                    Options.mode = 'resize';
                    Options.index = i;
                    eventdata = core.ToggleEventData(Options);
                    notify(obj, 'UpdateDatasetAxes', eventdata);
                end

                %obj.updateAxesLimits('resize', i); % Updates the obj.mibImage.axesX and obj.mibImage.axesY during fit screen, resize, or new dataset drawing
            else        % first call when MibModel initialized in MIB, for all other calls obj.preferences will be restored
                obj.I{i} = core.MibDataset(I, meta, BatchOpt.DatasetType{1}, 'labels63');
            end
        end
                
        % update all widgets of the Datasets panel
        if ~initializationSwitch
            notify(obj, 'DatasetsPanelUpdate');   % listener callback controllers.MibActiveDataset.update_fromModel
        end
    case 'Rename set'
        %fprintf('models.mibModel.datasetsSetsOps: Rename set %s -> %s\n', obj.Sets.names{obj.Sets.selectedSet}, BatchOpt.SetName);
        
        obj.Sets.names{obj.Sets.selectedSet} = BatchOpt.SetName;
        % update all widgets of the Datasets panel
        notify(obj, 'DatasetsPanelUpdate');
    case 'Sort sets'
        % the datasets are indexed globally and set-major (datasetsInSet
        % containers per set), so sorting the set names alone would leave the
        % names pointing at another set's data; refuse to touch anything when
        % that invariant is already broken rather than shuffling blindly
        if numel(obj.I) ~= noSets * obj.Sets.datasetsInSet
            ErrorDlgOpt.winTitle = 'Error in MibModel.datasetsSetsOps';
            ErrorDlgOpt.optionalPrefix = sprintf(['!!! Error !!!\n\nThe number of containers (%d) does not match ' ...
                '%d sets x %d containers; the sets can not be sorted!'], numel(obj.I), noSets, obj.Sets.datasetsInSet);
            eventdata = core.ToggleEventData(ErrorDlgOpt);
            notify(obj, 'ShowErrorDialog', eventdata);
            return;
        end

        [~, ids] = sort(obj.Sets.names);

        % move the containers together with their set; obj.I holds handles, so
        % this permutes pointers only and never copies image data
        globalIds = reshape(1:numel(obj.I), obj.Sets.datasetsInSet, []);  % one column per set
        newOrderOfGlobalIds = reshape(globalIds(:, ids), 1, []);   % old global id now sitting at each new position
        obj.I = obj.I(newOrderOfGlobalIds);

        % remap everything else that caches a global container index
        newIdOfOldId = zeros(1, numel(obj.I));
        newIdOfOldId(newOrderOfGlobalIds) = 1:numel(obj.I);
        obj.id = newIdOfOldId(obj.id);
        if ~isempty(obj.linkedPairs)
            obj.linkedPairs = sort(newIdOfOldId(obj.linkedPairs), 2);  % keep the smaller global id first
        end
        % undo items store the global container index they were taken from
        % (see MibModel.undo -> storeOptions.id); after the reindexing they
        % would restore pixels into a different dataset
        obj.Backup.clearContents();

        obj.Sets.names = obj.Sets.names(ids);
        obj.Sets.datasetTypes = obj.Sets.datasetTypes(ids,:);
        obj.Sets.selectedDataset = obj.Sets.selectedDataset(ids);
        % update the selected set
        obj.Sets.selectedSet = find(ids==obj.Sets.selectedSet);

        % update all widgets of the Datasets panel; the image documents are
        % indexed by the set index as well and are permuted by the listener
        notify(obj, 'DatasetsPanelUpdate', core.ToggleEventData(struct('mode', 'sortSets', 'order', ids)));
    case 'Remove set'
        %fprintf('models.mibModel.datasetsSetsOps: Remove set\n');
        
        if noSets == 1 %#ok<ISCL>
            ErrorDlgOpt.winTitle = 'Error in MibModel.datasetsSetsOps';
            ErrorDlgOpt.optionalPrefix = sprintf('!!! Ops !!!\n\nThe last set can not be removed!');
            ErrorDlgOpt.WindowHeight = 125;
            eventdata = core.ToggleEventData(ErrorDlgOpt);
            notify(obj, 'ShowErrorDialog', eventdata);
            return;
        end
        % get the global index of the first dataset
        firstDatasetIndex = (obj.Sets.selectedSet-1)*obj.Sets.datasetsInSet + 1;

        datasetIndices = firstDatasetIndex:firstDatasetIndex+obj.Sets.datasetsInSet-1;
        obj.I(datasetIndices) = [];

        % removing a set shifts every higher global container index down, while
        % undo items store the global index they were taken from (see
        % MibModel.undo -> storeOptions.id) and would restore pixels into a
        % different dataset afterwards
        obj.Backup.clearContents();

        % update obj.Sets structure
        obj.Sets.names(obj.Sets.selectedSet) = [];
        obj.Sets.datasetTypes(obj.Sets.selectedSet, :) = [];
        obj.Sets.selectedDataset(obj.Sets.selectedSet) = [];
        obj.Sets.selectedSet = max([obj.Sets.selectedSet - 1, 1]);
        % update all widgets of the Datasets panel
        notify(obj, 'DatasetsPanelUpdate');
end

status = true;
end
