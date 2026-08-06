function updateCheckboxes(obj, BatchOptIn)
% UPDATECHECKBOXES - Batch function to tweak the state of checkboxes in the Segmentation panel.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.updateCheckboxes()
%       obj.updateCheckboxes(BatchOptIn)
%
% Input Arguments:
%   - **BatchOptIn** - *(optional)* [struct] batch processing structure; when ``NaN`` returns
%     default options via ``SyncBatch`` event. Fields:
%
%     - ``.FixSelectionToMaterial`` - [cell] restrict selection to material: ``'Unchanged'``, ``'Checked'``, ``'Unchecked'``
%     - ``.MaskedArea`` - [cell] restrict selection to masked area: ``'Unchanged'``, ``'Checked'``, ``'Unchecked'``
%     - ``.BrushWatershed`` - [cell] use brush with watershed clustering: ``'Unchanged'``, ``'Checked'``, ``'Unchecked'``
%     - ``.BrushSlic`` - [cell] use brush with SLIC clustering: ``'Unchanged'``, ``'Checked'``, ``'Unchecked'``
%     - ``.SelectedMaterial`` - [string] index of the selected material; ``'-1'`` = mask, ``'0'`` = exterior, ``'1'``/``'2'``... = model materials; leave empty to keep unchanged
%     - ``.SelectedAddToMaterial`` - [string] index of the add-to material; same conventions as ``.SelectedMaterial``
%     - ``.UnlinkMaterialFromAddTo`` - [logical] unlink selected material from the AddTo material
%
% **Example 1** - check the Fix Selection To Material checkbox:
%
%   .. code-block:: matlab
%
%       BatchOptIn.FixSelectionToMaterial = {'Checked'};
%       obj.mibController.cSegmentation.updateCheckboxes(BatchOptIn);
%

if nargin < 2; BatchOptIn = struct(); end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
availableOptions = {'Unchanged', 'Checked', 'Unchecked'};
BatchOpt.FixSelectionToMaterial = {'Unchanged'};
BatchOpt.FixSelectionToMaterial{2} = availableOptions;
BatchOpt.MaskedArea = {'Unchanged'};
BatchOpt.MaskedArea{2} = availableOptions;
BatchOpt.BrushWatershed = {'Unchanged'};
BatchOpt.BrushWatershed{2} = availableOptions;
BatchOpt.BrushSlic = {'Unchanged'};
BatchOpt.BrushSlic{2} = availableOptions;
BatchOpt.SelectedMaterial = '';
BatchOpt.SelectedAddToMaterial = '';
BatchOpt.UnlinkMaterialFromAddTo = obj.mibModel.I{obj.mibModel.getActiveId()}.unlinkMaterials;
BatchOpt.id = obj.mibModel.getActiveId();

BatchOpt.mibBatchSectionName = 'Panel -> Segmentation';
BatchOpt.mibBatchActionName = 'Modify parameters';
BatchOpt.mibBatchTooltip.FixSelectionToMaterial = 'Tweak the status of the "Fix selection to material" checkbox';
BatchOpt.mibBatchTooltip.MaskedArea = 'Tweak the status of the "Masked area" checkbox';
BatchOpt.mibBatchTooltip.BrushWatershed = 'Use brush with watershed clustering';
BatchOpt.mibBatchTooltip.BrushSlic = 'Use brush with SLIC clustering';
BatchOpt.mibBatchTooltip.SelectedMaterial = '[Not compatible with 65535 models] index of the selected material; keep empty to not change the state; -1 for mask, 0 for exterior, 1,2,3 for model materials';
BatchOpt.mibBatchTooltip.SelectedAddToMaterial = '[Not compatible with 65535 models] index of the material to be added to; keep empty to not change the state; -1 for mask, 0 for exterior, 1,2,3 for model materials';
BatchOpt.mibBatchTooltip.UnlinkMaterialFromAddTo = 'Unlink selected material from the AddTo material';

if nargin == 2
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)
            BatchOpt = rmfield(BatchOpt, 'id');
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        else
            utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                'A structure as the 2nd parameter is required!', 'Parameter error');
        end
        return;
    else
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end
end

batchOpt2 = rmfield(BatchOpt, {'id', 'mibBatchSectionName', 'mibBatchActionName', 'mibBatchTooltip'});
fieldNames = fieldnames(batchOpt2);
for fieldIndex = 1:numel(fieldNames)
    if iscell(batchOpt2.(fieldNames{fieldIndex}))
        if strcmp(batchOpt2.(fieldNames{fieldIndex}){1}, 'Unchanged'); continue; end

        state = strcmp(batchOpt2.(fieldNames{fieldIndex}){1}, 'Checked');

        switch fieldNames{fieldIndex}
            case 'FixSelectionToMaterial'
                obj.mibModel.I{BatchOpt.id}.restrictSelectionToMaterial = state;
                obj.handles.restrictMaterial.Value = state;
                if BatchOpt.id == obj.mibModel.id; obj.restrictMaterial_Callback(); end
            case 'MaskedArea'
                if obj.mibModel.I{BatchOpt.id}.maskExist
                    obj.mibModel.I{BatchOpt.id}.restrictSelectionToMask = state;
                    obj.handles.restrictMask.Value = state;
                    if BatchOpt.id == obj.mibModel.id; obj.restrictMask_Callback(); end
                end
            case 'BrushWatershed'
                if state
                    obj.handles.brushUseClustering.SelectedObject = obj.handles.watershedClusters;
                elseif strcmp(obj.handles.brushUseClustering.SelectedObject.Text, 'Watershed')
                    obj.handles.brushUseClustering.SelectedObject = obj.handles.noClusters;
                end
                obj.brushPanel_Callback([], [], 'brushUseClustering');
            case 'BrushSlic'
                if state
                    obj.handles.brushUseClustering.SelectedObject = obj.handles.slicClusters;
                elseif strcmp(obj.handles.brushUseClustering.SelectedObject.Text, 'SLIC')
                    obj.handles.brushUseClustering.SelectedObject = obj.handles.noClusters;
                end
                obj.brushPanel_Callback([], [], 'brushUseClustering');
        end
    elseif ischar(batchOpt2.(fieldNames{fieldIndex}))
        if isempty(batchOpt2.(fieldNames{fieldIndex})); continue; end

        switch fieldNames{fieldIndex}
            case 'SelectedMaterial'
                materialId = str2double(batchOpt2.(fieldNames{fieldIndex}));
                obj.mibModel.I{BatchOpt.id}.selectedMaterial = materialId + 2;
            case 'SelectedAddToMaterial'
                materialId = str2double(batchOpt2.(fieldNames{fieldIndex}));
                obj.mibModel.I{BatchOpt.id}.selectedAddToMaterial = materialId + 2;
        end
    else  % logical - UnlinkMaterialFromAddTo
        obj.mibModel.I{BatchOpt.id}.unlinkMaterials = BatchOpt.UnlinkMaterialFromAddTo;
        if ~BatchOpt.UnlinkMaterialFromAddTo
            obj.mibModel.I{BatchOpt.id}.selectedAddToMaterial = ...
                obj.mibModel.I{BatchOpt.id}.selectedMaterial;
        end
    end
end
obj.updateMaterialsTable();
end
