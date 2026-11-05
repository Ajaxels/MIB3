function buffersContext_Opening(obj, hContextMenu, openingData)
% BUFFERSCONTEXT_OPENING - set the lock items of the buffer context menu for the clicked buffer.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.buffersContext_Opening(hContextMenu, openingData)
%
% ``ContextMenuOpeningFcn`` of ``obj.handles.buffersContext``. One menu is
% shared by all ten buffer buttons, so the check marks of *Lock image* and
% *Lock labels* are set here, each time the menu opens, from
% ``core.MibDataset.getLockedState`` of the dataset under the clicked button:
%
%   - ``'none'`` - the item is disabled (not a BigData dataset, or no model)
%   - ``'unlocked'`` / ``'locked'`` - enabled, unchecked / checked
%   - ``'readOnly'`` - checked and disabled: the labels come from a store MIB
%     never writes
%
% Input Arguments:
%   - **hContextMenu** - [matlab.ui.container.ContextMenu] the buffer context menu
%   - **openingData** - event data; ``openingData.ContextObject`` is the clicked
%     buffer button, whose ``Text`` is its number within the set
%

arguments (Input)
    obj controllers.MibActiveDataset
    hContextMenu matlab.ui.container.ContextMenu %#ok<INUSA>
    openingData
end

buttonId = str2double(erase(openingData.ContextObject.Tag, 'buffer'));
if isnan(buttonId); return; end
globalDatasetIndex = buttonId + (obj.mibModel.Sets.selectedSet - 1) * obj.mibModel.Sets.datasetsInSet;
dataset = obj.mibModel.I{globalDatasetIndex};

menuItems = struct('image', obj.handles.buffersContextLockImage, 'labels', obj.handles.buffersContextLockLabels);
for layer = ["image", "labels"]
    menuItem = menuItems.(layer);
    state = dataset.getLockedState(char(layer));
    menuItem.Checked = matlab.lang.OnOffSwitchState(ismember(state, {'locked', 'readOnly'}));
    menuItem.Enable = matlab.lang.OnOffSwitchState(ismember(state, {'unlocked', 'locked'}));
end

end
