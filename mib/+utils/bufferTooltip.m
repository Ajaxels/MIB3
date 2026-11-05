function [tooltip, modelText, lockText] = bufferTooltip(dataset)
% BUFFERTOOLTIP - Tooltip of a buffer button in the Datasets panel: the dataset and its model.
%
% Syntax:
%   .. code-block:: matlab
%
%      tooltip = utils.bufferTooltip(dataset)
%      [tooltip, modelText] = utils.bufferTooltip(dataset)
%      [tooltip, modelText, lockText] = utils.bufferTooltip(dataset)
%
% Two lines: the full path of the image, then ``Model:`` with the full path of
% the model file. A BigData model names its store folder. An empty buffer gets
% the hint about the context menu instead. When the image or the labels are
% locked (``core.MibDataset.getLockedState``), a first line says which, e.g.
% ``LOCKED: image, labels``; a Standard dataset, whose labels lock is the
% disabled selection, gets ``LOCKED: labels (selection disabled)``.
%
% Input Arguments:
%   - **dataset** - ``core.MibDataset`` shown in the buffer
%
% Output Arguments:
%   - **tooltip** - char, the text for the button's ``Tooltip``
%   - **modelText** - char, what the second line says about the model: the
%     full path of its file, ``'not saved yet'`` for a model that was created but
%     never saved (``labels.filename`` empty or the default
%     ``Labels_none.model``), or ``'none'`` without a model. Also used for the
%     Create / Load model tooltips of the Segmentation panel, which show its
%     ``fileparts`` name - for the two placeholders that is the text itself
%   - **lockText** - char, the lock line on its own (``'LOCKED: labels'``), or
%     ``''`` when nothing is locked; ``controllers.MibActiveDataset.update_fromModel``
%     puts it in front of the tooltips it builds itself
%
% See also: controllers.MibController.updateGuiWidgets

% Updates
%

modelText = 'none';
if dataset.modelExist
    modelFile = dataset.labels.filename;
    if iscell(modelFile) && ~isempty(modelFile); modelFile = modelFile{1}; end
    modelFile = char(modelFile);
    [~, modelStem] = fileparts(modelFile);
    if isempty(modelStem) || strcmp(modelStem, 'Labels_none')
        modelText = 'not saved yet';
    else
        modelText = modelFile;
    end
end

imageFile = dataset.image.filename;
if iscell(imageFile) && ~isempty(imageFile); imageFile = imageFile{1}; end
imageFile = char(imageFile);
if strcmp(imageFile, 'none.tif')   % an empty buffer
    tooltip = 'use RMB for a context menu with additional options';
else
    tooltip = sprintf('%s\nModel: %s', imageFile, modelText);
end

% the locked layers; 'readOnly' labels are shown as locked too
lockedLayers = {'image', 'labels'};
isLocked = cellfun(@(layer) ismember(dataset.getLockedState(layer), {'locked', 'readOnly'}), lockedLayers);
lockText = '';
if any(isLocked)
    lockText = ['LOCKED: ' strjoin(lockedLayers(isLocked), ', ')];
    if strcmp(dataset.datasetType, 'Standard'); lockText = [lockText ' (selection disabled)']; end
    tooltip = sprintf('%s\n%s', lockText, tooltip);
end
end
