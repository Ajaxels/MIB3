function state = getLockedState(obj, layer)
% GETLOCKEDSTATE - locked state of the image or labels layer, as the GUI shows it.
%
% Syntax:
%   .. code-block:: matlab
%
%       state = obj.getLockedState(layer)
%
% Puts the lock of a layer in the terms the buffer context menu, the buffer
% padlock and the Segmentation panel lock button need: whether the lock applies
% at all, and whether the user may change it. The lock means a different thing
% for the two dataset types that have one:
%
% - **BigData** - ``lockedState`` of ``obj.image`` or ``obj.labels`` (see
%   ``core.MibImage.lockedState``). Locked labels keep their materials; the
%   mask and the selection stay editable.
% - **Standard** - the ``'labels'`` lock is the disabled selection,
%   ``obj.enableSelection == false``: the labels, mask and selection layers are
%   not allocated, so nothing can be segmented. ``models.MibModel.setLockedState``
%   unlocks it by allocating the layers and locks it by releasing them. The
%   ``'image'`` lock does not apply, since Standard edits stay in memory.
%
% An empty placeholder buffer (``none.tif``, 512 x 512 x 1 x 1, the test of
% ``controllers.MibActiveDataset.update_fromModel``) reports ``'none'``, so the
% padlock does not cover the empty buffers when the ``System.EnableSelection``
% preference is off. Virtual datasets are browse-only and report ``'none'``.
%
% Input Arguments:
%   - **layer** - [char] the layer to ask about:
%
%     - ``'image'`` - the image store; locked means the voxel sizes and the
%       bounding box are not written into the file without asking
%     - ``'labels'`` - BigData: the material bits and the material list of
%       the model store; Standard: the whole segmentation (labels, mask and
%       selection)
%
% Output Arguments:
%   - **state** - [char] one of:
%
%     - ``'none'`` - the lock does not apply: a Virtual dataset, an empty
%       placeholder, the image of a Standard dataset or, for BigData
%       ``'labels'``, no model is open
%     - ``'unlocked'`` - the layer can be changed
%     - ``'locked'`` - changes are refused until the layer is unlocked
%     - ``'readOnly'`` - the labels come from a store MIB never writes
%       (``core.MibBigDataLabelsZarr2``, ``core.MibBigDataLabelsIndex``); shown
%       locked, and cannot be unlocked
%
% Usage:
%   .. code-block:: matlab
%
%     state = obj.mibModel.I{obj.mibModel.getActiveId()}.getLockedState('labels');
%     if strcmp(state, 'locked'); disp('the labels are locked'); end
%

arguments
    obj core.MibDataset
    layer {mustBeMember(layer, {'image', 'labels'})}
end

state = 'none';
switch obj.datasetType
    case 'Standard'
        if strcmp(layer, 'image'); return; end
        img = obj.image;
        if strcmp(img.filename, 'none.tif') && img.height == 512 && img.width == 512 && img.depth == 1 && img.time == 1
            return;     % empty placeholder buffer
        end
        if obj.enableSelection
            state = 'unlocked';
        else
            state = 'locked';
        end
        return;
    case 'BigData'
        % below
    otherwise
        return;
end

switch layer
    case 'image'
        layerObject = obj.image;
    case 'labels'
        if ~obj.modelExist; return; end
        layerObject = obj.labels;
        if isa(layerObject, 'core.MibBigDataLabelsZarr2') || isa(layerObject, 'core.MibBigDataLabelsIndex')
            state = 'readOnly';
            return;
        end
end

if layerObject.lockedState
    state = 'locked';
else
    state = 'unlocked';
end

end
