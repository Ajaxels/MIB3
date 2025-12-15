function clearLayer(obj, layer, sel_switch, BatchOptIn)
% function clearLayer(obj, layer, sel_switch, BatchOptIn)
% clear the specified layer
%
% Parameters:
% layer: a string with the target layer, can be []
% @li [] -> 'selection'
% @li 'selection' -> clear the selection layer
% @li 'mask' -> clear the mask layer
% @li 'labels' -> clear the labels layer
% @li 'everything' -> clear selection, mask, labels layers for core.MibLabels63 class only
% @li 'image' -> clear the image layer
% sel_switch: a string to define where selection should be cleared:
% @li when @b '2D, Slice' fill holes for the currently shown slice
% @li when @b '3D, Stack' fill holes for the currently shown z-stack
% @li when @b '4D, Dataset' fill holes for the whole dataset
% BatchOptIn: [@em optional], a structure with extra parameters or settings for the batch processing mode, when NaN return
%    a structure with default options via "SyncBatch" event
% optional parameters
% @li .Layer -> cell with one of possible parameters: 'selection', 'mask', 'labels', 'everything', 'image'
% @li .DatasetType -> cell with one of possible parameters: '2D, Slice', '3D, Stack', '4D, Dataset'
% @li .showWaitbar - logical, show or not the waitbar

%| 
% Examples:
% @code obj.mibModel.clearLayer('selection'); // clear the selection layer for the whole dataset % @endcode 
% @code obj.mibModel.clearLayer('selection', '2D, Stack'); // clear the selection layer of the shown slice % @endcode 

% Updates
% 

% do nothing is selection is disabled
if obj.I{obj.id}.enableSelection == 0; return; end

if nargin < 4; BatchOptIn = struct(); end
if nargin < 3; sel_switch = []; end
if nargin < 2; layer = []; end

BatchOpt = struct();
if ~isempty(layer)
    BatchOpt.Layer = {layer};
else
    BatchOpt.Layer = {'selection'};    
end

if ~isempty(sel_switch)
    BatchOpt.DatasetType = {sel_switch};
else
    BatchOpt.DatasetType = {'3D, Stack'};    
end
BatchOpt.Layer{2} = {'everything', 'image', 'labels', 'mask', 'selection'}; 
BatchOpt.DatasetType{2} = {'2D, Slice', '3D, Stack', '4D, Dataset'};
BatchOpt.showWaitbar = true;   % show or not the waitbar
BatchOpt.id = obj.id;   % default BatchOpt.id
BatchOpt.mibBatchTooltip.Layer = 'Layer to clear, "everything" works only for models with 63 materials';
BatchOpt.mibBatchTooltip.DatasetType = 'Select to remove selection from the current slice, stack, or dataset';
BatchOpt.mibBatchTooltip.showWaitbar = sprintf('Show or not the progress bar during execution');

BatchOpt.mibBatchSectionName = 'Panel -> Selection and View settings';    % section name for the Batch
BatchOpt.mibBatchActionName = 'Clear layer';

%% Batch mode check actions
if nargin == 4  % batch mode 
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)     % when varargin{3} == NaN return possible settings
            % trigger SyncBatch event to send BatchOptInOut to mibBatchController 
            BatchOpt = rmfield(BatchOpt, 'id');
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj, 'SyncBatch', eventdata);
        else
            errorText = sprintf('obj.mibModel.clearSelection:\nA structure as the 3rd parameter is required!');
            utils.dlgs.showErrorDialog(obj.mibGUI, errorText, 'BatchOpt Error');
        end
        return;
    else
        % add/update BatchOpt with the provided fields in BatchOptIn
        % combine fields from input and default structures
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end
end

getDataOptions.blockModeSwitch = obj.I{BatchOpt.id}.blockModeSwitch;
[h, w, d] = obj.I{BatchOpt.id}.getDatasetDimensions('image', [], getDataOptions);

setDataOptions.id = BatchOpt.id;
if strcmp(BatchOpt.DatasetType{1} ,'2D, Slice')
    %obj.mibDoBackup('selection', 0, setDataOptions);
    img = zeros([h, w], 'uint8');
    obj.I{obj.id}.setData2D(img, BatchOpt.Layer{1}, [], [], [], setDataOptions);
else 
    if strcmp(BatchOpt.DatasetType{1} ,'3D, Stack') 
        %obj.mibDoBackup('selection', 1, setDataOptions);
        t1 = obj.I{BatchOpt.id}.slices{5}(1);
        t2 = obj.I{BatchOpt.id}.slices{5}(2);
    else
        t1 = 1;
        t2 = obj.I{BatchOpt.id}.time;
    end

    if BatchOpt.showWaitbar
        wb = uiprogressdlg(obj.mibGUI, 'Value', 0, ...
            'Message', sprintf('Clearing the "%s" layer for a whole Z-stack\nPlease wait...', BatchOpt.Layer{1}), ...
            'Title', 'Clear layer', 'Indeterminate', 'on'); 
    end
    
    img = zeros([h, w, d], 'uint8');
    for t=t1:t2
        obj.I{obj.id}.setData3D(img, BatchOpt.Layer{1}, t, obj.I{BatchOpt.id}.orientation, [], setDataOptions);
    end
    if BatchOpt.showWaitbar; delete(wb); end
end

% notify the batch mode
BatchOpt = rmfield(BatchOpt, 'id');     % remove id field
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);

notify(obj, 'ShowImage');
end