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
BatchOpt.SetName = obj.Set.setNames{obj.Set.setId}; % current set name
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

noSets = numel(obj.Set.setNames); % current number of sets
switch BatchOpt.Mode{1}
    case 'Select set'
        fprintf('obj.mibModel.datasetsSetsOps: Select set\n');
    case 'Add set'
        fprintf('obj.mibModel.datasetsSetsOps: Add set: %s \n', BatchOpt.SetName);
    case 'Rename set'
        fprintf('obj.mibModel.datasetsSetsOps: Rename set %s -> %s\n', obj.Set.setNames{obj.Set.setId}, BatchOpt.SetName);
    case 'Remove set'
        % if noSets == 1
        %     notify(obj, 'uialert');
        %     uialert(obj.gui, sprintf('!!! Warning !!!\n\nThe last set can not be removed!'), 'Remove set'); return;
        % end
        fprintf('obj.mibModel.datasetsSetsOps: Remove set\n');
end

status = true;
end