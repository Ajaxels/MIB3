function status = datasetsSetsOps(obj, BatchOptIn)
% status = datasetsSetsOps(obj, BatchOptIn)
% operations with sets of the  model. Compatible with the batch mode.
%
% Parameters:
% BatchOptIn: structure with parameters.
% .Mode - a cell with the following modes
% -> 'Select set' - select the set in obj.view.handles.panels.datasets.handles.sets dropdown
% -> 'Add set' - add a new set (10 new datasets) into the model
% -> 'Rename set' - rename the set
% -> 'Remove set' - remove the set
% .SetName - set name to select, rename, remove; when empty a dialog asking for the set name appears
%
% Return values:
% status: logical, resulting status of the function true/false

status = false;

% --------------- Batch operation logic ---------------
% specify default BatchOptIn
BatchOpt = struct();
BatchOpt.Mode = {'Select set'};     % default operation
BatchOpt.Mode{2} = {'Select set', 'Add set', 'Rename set', 'Remove set'};  % only the single option is available for the batch mode so far
if isempty(obj.Sets.selectedSet) % initialization of MIB
    BatchOpt.SetName = 'Set 1';  
else    
    BatchOpt.SetName = obj.Sets.names{obj.Sets.selectedSet}; % current set name
end
% tooltips that will accompany the BatchOpt
BatchOpt.mibBatchTooltip.Mode = sprintf('Select required operation with the sets');
BatchOpt.mibBatchTooltip.SetName = sprintf('Specify the (new) set name');

% add section name and action name for the batch tool
BatchOpt.mibBatchSectionName = 'Panels -> Datasets';
BatchOpt.mibBatchActionName = 'Set operations';

if nargin == 2  % batch mode
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)     % when varargin{4} == NaN return possible settings
            % trigger syncBatch event to send BatchOptInOut to mibBatchController
            eventdata = ToggleEventData(BatchOpt);
            notify(obj.mibModel, 'syncBatch', eventdata);
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
        obj.Sets.selectedSet = find(ismember(obj.Sets.names, BatchOpt.SetName));
        
        % update all widgets of the Datasets panel
        notify(obj, 'DatasetsPanelUpdate');

        fprintf('obj.mibModel.datasetsSetsOps: Select set -> %s\n', BatchOpt.SetName);
    case 'Add set'
        if ismember(BatchOpt.SetName, obj.Sets.names)
            ErrorDlgOpt.winTitle = 'Error in MibModel.datasetsSetsOps';
            ErrorDlgOpt.optionalPrefix = sprintf('!!! Error !!!\n\nThe sets should have unique names!');
            eventdata = core.ToggleEventData(ErrorDlgOpt);
            notify(obj, 'ShowErrorDialog', eventdata);
            return;
        end
        
        % get index of the next dataset
        nextDatasetIndex = numel(obj.Sets.names)*obj.Sets.datasetsInSet + 1;
        for i=nextDatasetIndex:nextDatasetIndex+obj.Sets.datasetsInSet-1  % initialize mibDataset
            obj.I{i} = core.MibDataset();
        end
        obj.Sets.names = [obj.Sets.names; BatchOpt.SetName];
        obj.Sets.selectedSet = numel(obj.Sets.names);
        obj.Sets.selectedDataset = [obj.Sets.selectedDataset; 1]; % add 1 as the index of the selected dataset for the added set
        
        % update all widgets of the Datasets panel
        notify(obj, 'DatasetsPanelUpdate');
        
        fprintf('obj.mibModel.datasetsSetsOps: Add set: %s \n', BatchOpt.SetName);
    case 'Rename set'
        obj.Sets.names{obj.Sets.selectedSet} = BatchOpt.SetName;
        % update all widgets of the Datasets panel
        notify(obj, 'DatasetsPanelUpdate');
        
        fprintf('obj.mibModel.datasetsSetsOps: Rename set %s -> %s\n', obj.Sets.names{obj.Sets.selectedSet}, BatchOpt.SetName);
    case 'Remove set'
        if noSets == 1 %#ok<ISCL>
            ErrorDlgOpt.winTitle = 'Error in MibModel.datasetsSetsOps';
            ErrorDlgOpt.optionalPrefix = sprintf('!!! Warning !!!\n\nThe last set can not be removed!');
            eventdata = core.ToggleEventData(ErrorDlgOpt);
            notify(obj, 'ShowErrorDialog', eventdata);
            return;
        end
        % get the global index of the first dataset
        firstDatasetIndex = (obj.Sets.selectedSet-1)*obj.Sets.datasetsInSet + 1;

        datasetIndices = firstDatasetIndex:firstDatasetIndex+obj.Sets.datasetsInSet-1;
        obj.I(datasetIndices) = [];

        obj.Sets.names(obj.Sets.selectedSet) = [];
        obj.Sets.selectedDataset(obj.Sets.selectedSet) = [];
        obj.Sets.selectedSet = 1;
        % update all widgets of the Datasets panel
        notify(obj, 'DatasetsPanelUpdate');

        fprintf('obj.mibModel.datasetsSetsOps: Remove set\n');
end

status = true;
end