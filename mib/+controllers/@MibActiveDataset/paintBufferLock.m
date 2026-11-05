function paintBufferLock(obj, buttonHandle, dataset)
% PAINTBUFFERLOCK - show a padlock instead of the number on a buffer button when the image or the labels of its dataset are locked.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.paintBufferLock(buttonHandle, dataset)
%
% A locked buffer shows the padlock icon (``assets/icons/lock_closed_16px.png``)
% centred, with no text; an unlocked one shows its buffer number and no icon.
% The number is dropped because the buttons are too narrow to show both: next
% to the text the icon is squeezed out of sight. MATLAB scales the icon down to
% the button size. The buffer number is restored from the button ``Tag``
% (``'buffer1'`` ... ``'buffer10'``), which is also where ``buffers_Callback``
% and the buffer context menu read it, so they keep working on a blank button.
%
% The lock is not shown with a background color: ``paintBufferButton``
% already uses the background for four states, and the ``'selected'`` color
% overrides the others, so a lock color would disappear on the very buffer
% that is shown. The tooltip says which layer is locked
% (``utils.bufferTooltip``, third output).
%
% Called for every buffer by ``update_fromModel`` and for the active buffer by
% ``controllers.MibController.updateGuiWidgets``, next to ``paintBufferButton``.
%
% Input Arguments:
%   - **buttonHandle** - [matlab.ui.control.Button] handle of the buffer button
%   - **dataset** - [core.MibDataset] the dataset stored in the buffer
%
% Usage:
%   .. code-block:: matlab
%
%      obj.paintBufferLock(obj.handles.buffer2, obj.mibModel.I{2});
%

arguments
    obj controllers.MibActiveDataset
    buttonHandle matlab.ui.control.Button
    dataset core.MibDataset
end

isLocked = ismember(dataset.getLockedState('image'), {'locked', 'readOnly'}) || ...
    ismember(dataset.getLockedState('labels'), {'locked', 'readOnly'});
if isLocked
    buttonHandle.Text = '';
    buttonHandle.Icon = fullfile(obj.mibModel.mibPath, 'assets', 'icons', 'lock_closed_16px.png');
    buttonHandle.IconAlignment = 'center';
else
    buttonHandle.Text = erase(buttonHandle.Tag, 'buffer');
    buttonHandle.Icon = '';
end

end
