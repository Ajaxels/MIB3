function status = setLockedState(obj, id, layer, state, options)
% SETLOCKEDSTATE - lock or unlock the image or the labels of a dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%      status = obj.setLockedState(id, layer, state)
%      status = obj.setLockedState(id, layer, state, Confirm = true)
%
% The lock means a different thing for the two dataset types that have one
% (see ``core.MibDataset.getLockedState``):
%
% - **BigData** - sets ``lockedState`` of ``obj.I{id}.image`` or
%   ``obj.I{id}.labels`` (see ``core.MibImage.lockedState``). Nothing is
%   allocated or released. Labels from a read-only store
%   (``core.MibBigDataLabelsZarr2``, ``core.MibBigDataLabelsIndex``) stay
%   locked: a request to unlock them is refused.
% - **Standard**, ``'labels'`` only - the lock is the disabled selection.
%
%   - *Unlock* sets ``enableSelection = true`` and allocates the 63-material
%     labels layer (``controllers.Preferences.allocateLabelsLayer``). An empty
%     container of another model type (a dataset opened with the
%     ``System.EnableSelection`` preference off and a 255 or 65535 default
%     model type) is first replaced with an empty 63-material one
%     (``controllers.Preferences.releaseSegmentationLayers``): it holds no model,
%     and only the 63-material layer can be allocated in place.
%   - *Lock* releases the labels, mask and selection
%     (``controllers.Preferences.releaseSegmentationLayers``), sets
%     ``enableSelection = false`` and, for the active dataset, clears the undo
%     history, whose entries belong to the released layers. This deletes the
%     model, so with ``Confirm = true`` the user is asked first.
%
%   This is the per-dataset switch; the ``System.EnableSelection`` preference
%   stays as it is and decides only for datasets opened later. The helpers are
%   static methods of ``controllers.Preferences``, which also calls them from
%   its Apply and OK handlers; ``tests/controllers/PreferencesSelectionLayerTest``
%   drives them there.
%
% Where the lock does not apply (``getLockedState`` returns ``'none'``: Virtual,
% an empty placeholder buffer, the image of a Standard dataset, BigData labels
% without an open model) nothing is changed. On a change ``UpdateGuiWidgets``
% is notified, and ``ShowImage`` too when the Standard layers were allocated or
% released, so the padlock of the buffer button and the lock button of the
% Segmentation panel follow; a caller that changes a buffer that is not the
% active one notifies ``DatasetsPanelUpdate`` itself.
%
% Input Arguments:
%   - **id** - [numeric] index of the dataset in ``obj.I``; ``[]`` for the
%     active dataset (``obj.getActiveId()``)
%   - **layer** - [char] ``'image'`` or ``'labels'``
%   - **state** - [logical] ``true`` to lock, ``false`` to unlock
%
% Name-Value Arguments:
%   - **Confirm** - [logical, default ``false``] ask before locking a Standard
%     dataset, which deletes its labels, mask and selection. Pass ``true`` from
%     interactive callers; batch mode and code leave it ``false``
%
% Output Arguments:
%   - **status** - [logical] ``true`` when the layer is now in the requested
%     state, ``false`` when the lock does not apply, the labels are read-only
%     or the user cancelled the confirmation
%
% Usage:
%   .. code-block:: matlab
%
%      obj.mibModel.setLockedState([], 'labels', true);   % lock the labels of the active dataset
%      obj.mibModel.setLockedState(3, 'image', false);    % unlock the image of dataset 3
%      obj.mibModel.setLockedState([], 'labels', true, Confirm = true);   % Standard: ask, then disable the selection
%

arguments
    obj models.MibModel
    id {mustBeNumeric}
    layer {mustBeMember(layer, {'image', 'labels'})}
    state (1,1) logical
    options.Confirm (1,1) logical = false
end

status = false;
if isempty(id); id = obj.getActiveId(); end
dataset = obj.I{id};

currentState = dataset.getLockedState(layer);
switch currentState
    case 'none'
        return;
    case 'readOnly'
        status = state;     % already locked, and it stays so
        return;
end
if state == strcmp(currentState, 'locked')
    status = true;          % already in the requested state
    return;
end

if strcmp(dataset.datasetType, 'Standard')
    if state
        if options.Confirm
            dlgOptions = struct('Icon', 'puffin_warning', 'WindowWidth', 460, 'WindowHeight', 170);
            answer = utils.dlgs.inputQuestDlg(obj.getProgressBarParent(), ...
                sprintf(['Lock the labels by disabling the selection of this dataset?\n\n' ...
                'The labels, mask and selection are deleted and the undo history is cleared.']), ...
                'Lock labels', 'Lock', 'Cancel', 'Cancel', dlgOptions);
            if ~strcmp(answer, 'Lock'); return; end
        end
        controllers.Preferences.releaseSegmentationLayers(dataset);
        dataset.enableSelection = false;
        if id == obj.getActiveId(); obj.Backup.clearContents(); end
    else
        dataset.enableSelection = true;
        if ~isa(dataset.labels, 'core.MibLabels63') && ~dataset.modelExist
            controllers.Preferences.releaseSegmentationLayers(dataset);
        end
        if isa(dataset.labels, 'core.MibLabels63') && ~dataset.labels.exists
            controllers.Preferences.allocateLabelsLayer(dataset);
        end
    end
    status = true;
    notify(obj, 'ShowImage');
    notify(obj, 'UpdateGuiWidgets');
    return;
end

dataset.(layer).lockedState = state;
if strcmp(layer, 'labels'); dataset.labels.lastWriteRefused = false; end
status = true;

notify(obj, 'UpdateGuiWidgets');

end
