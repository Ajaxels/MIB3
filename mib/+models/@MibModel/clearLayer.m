function clearLayer(obj, layer, sel_switch, BatchOptIn)
% CLEARLAYER - clear the specified layer.
%
% Syntax:
%   function clearLayer(obj, layer, sel_switch, BatchOptIn)
%
% Input Arguments:
%   - **layer** — a string with the target layer
%
%     - ``[]`` — default (``'selection'``)
%     - ``'selection'`` — clear the selection layer
%     - ``'mask'`` — clear the mask layer
%     - ``'labels'`` — clear the labels layer
%     - ``'everything'`` — clear selection, mask, and labels layers (core.MibLabels63 only)
%     - ``'image'`` — clear the image layer
%
%   - **sel_switch** — a string to define the extent of the clear operation
%
%     - ``'2D, Slice'`` — clear the currently shown slice only
%     - ``'3D, Stack'`` — clear the currently shown z-stack
%     - ``'4D, Dataset'`` — clear the whole dataset
%
%   - **BatchOptIn** — *(optional)* structure with extra parameters for batch processing mode;
%     when NaN, returns a structure with default options via ``SyncBatch`` event
%
%     - ``.Layer`` — cell with one of: ``'selection'``, ``'mask'``, ``'labels'``, ``'everything'``, ``'image'``
%     - ``.DatasetType`` — cell with one of: ``'2D, Slice'``, ``'3D, Stack'``, ``'4D, Dataset'``
%     - ``.showWaitbar`` — logical, show or not the waitbar
%
% Usage:
%   **Example 1** — clear the selection layer for the whole dataset
%
%   .. code-block:: matlab
%
%      obj.mibModel.clearLayer('selection');
%
%   **Example 2** — clear the selection layer of the shown slice
%
%   .. code-block:: matlab
%
%      obj.mibModel.clearLayer('selection', '2D, Stack');
%

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
BatchOpt.id = obj.getActiveId();   % default BatchOpt.id
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
            ErrorDlgOpt.winTitle = 'BatchOpt Error';
            ErrorDlgOpt.optionalPrefix = 'Error in MibModel.clearLayer';
            ErrorDlgOpt.err = 'A structure as the 3rd parameter is required!';
            ErrorDlgOpt.WindowHeight = 150;
            eventdata = core.ToggleEventData(ErrorDlgOpt);
            notify(obj, 'ShowErrorDialog', eventdata);
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
    obj.backup(BatchOpt.Layer{1}, 0, setDataOptions);
    img = zeros([h, w], 'uint8');
    obj.I{obj.id}.setData2D(img, BatchOpt.Layer{1}, [], [], [], setDataOptions);
else
    if strcmp(BatchOpt.DatasetType{1} ,'3D, Stack')
        obj.backup(BatchOpt.Layer{1}, 1, setDataOptions);
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
