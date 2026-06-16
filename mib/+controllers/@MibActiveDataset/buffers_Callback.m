function buffers_Callback(obj, hWidget, hData, buttonId)
% BUFFERS_CALLBACK - buffers_Callback(obj, hWidget, hData).
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.buffers_Callback(hWidget, hData, buttonId)
%
% callbacks for press obj.handles.panels.activeDataset.handles.buffer1 buttons, selects the dataset
% stored in a buffer defined by the pressed button
%
% Handles the following widgets:
% - obj.handles.panels.activeDataset.handles.bufferN, where N is number 1 to 10,
%
% Input Arguments:
%   - **obj** — controllers.MibActiveDataset
%   - **hWidget** — handle to the pressed widget (matlab.ui.control.Button)
%   - **hData** — handle to supporting ButtonPushedData class (matlab.ui.eventdata.ButtonPushedData)
%   - **buttonId** — [optional] index of dataset in MibModel (the shown one is
%     obj.mibModel.id), when omitted a generic callback on the buffer button
%     press is executed
%

if nargin < 4
    % get index of the pressed button
    buttonId = str2double(hWidget.Text); 
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibActiveDataset.buffers_Callback -> button "%d" pressed\n', buttonId);
end

% generate identifier of the buffer handle
prevBufferStringId = sprintf('buffer%d', obj.mibModel.Sets.selectedDataset(obj.mibModel.Sets.selectedSet));
prevDatasetId = obj.mibModel.id; % store the previous dataset index
obj.mibModel.previouslySelectedDataset = prevDatasetId; % store the previous dataset id
newBufferStringId = sprintf('buffer%d', buttonId);

obj.mibModel.Sets.selectedDataset(obj.mibModel.Sets.selectedSet) = buttonId; % update index of the dataset selected in the current set
obj.mibModel.id = buttonId + (obj.mibModel.Sets.selectedSet-1)*obj.mibModel.Sets.datasetsInSet; % update the selected dataset in the global index

% update the background color for the selected buffer
if ~strcmp(prevBufferStringId, newBufferStringId)
    prevImg = obj.mibModel.I{prevDatasetId}.image;
    if strcmp(prevImg.filename, 'none.tif') && prevImg.height == 512 && prevImg.width == 512 && prevImg.depth == 1 && prevImg.time == 1
        % Empty placeholder buffer
        obj.view.handles.panels.activeDataset.handles.(prevBufferStringId).BackgroundColor = ...
            obj.view.handles.panels.dirContents.handles.updateFileList.BackgroundColor;
    elseif strcmp(prevImg.filename, 'none.tif')
        % In-memory dataset — data present but no file on disk
        obj.view.handles.panels.activeDataset.handles.(prevBufferStringId).BackgroundColor = [1 0.85 0.6];
    else
        % File-backed dataset
        obj.view.handles.panels.activeDataset.handles.(prevBufferStringId).BackgroundColor = [0.7 1 0.7];
    end

    % update description of the set tab
    obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.setDescription(...
        sprintf('Buffer %d:\n%s', buttonId, obj.mibModel.I{obj.mibModel.id}.image.filename));
end
obj.view.handles.panels.activeDataset.handles.(newBufferStringId).BackgroundColor = [0 1 0];

% update Dataset Type dropdown in the Datasets panel
obj.view.handles.panels.activeDataset.handles.datasetType.Value = obj.mibModel.Sets.datasetTypes{obj.mibModel.Sets.selectedSet, obj.mibModel.Sets.selectedDataset(obj.mibModel.Sets.selectedSet)};

% Linked-view: when switching TO a buffer that is linked to the one just left,
% copy the previous buffer's view state so both show the same position.
prevDatasetIdLocal = obj.mibModel.previouslySelectedDataset;
newDatasetId = obj.mibModel.id;
partnerOfNew = obj.mibModel.getLinkedDataset(newDatasetId);
if ~isempty(partnerOfNew) && partnerOfNew == prevDatasetIdLocal
    src = obj.mibModel.I{prevDatasetIdLocal};
    dst = obj.mibModel.I{newDatasetId};
    for iDim = 1:5
        maxVal = dst.dim_yxzct(iDim);
        dst.slices{iDim} = min(src.slices{iDim}, [maxVal maxVal]);
    end
    [axX, axY] = obj.mibModel.getAxesLimits(prevDatasetIdLocal);
    obj.mibModel.setAxesLimits(axX, axY, newDatasetId);
    obj.mibModel.setMagFactor(obj.mibModel.getMagFactor(prevDatasetIdLocal), newDatasetId);
end

notify(obj.mibModel, 'UpdateGuiWidgets');
notify(obj.mibModel, 'ShowImage');

end
