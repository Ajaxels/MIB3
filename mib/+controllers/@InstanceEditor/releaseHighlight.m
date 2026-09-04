function releaseHighlight(obj)
% RELEASEHIGHLIGHT - Take the highlight back out of the Selection layer.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.releaseHighlight()
%
% The highlight borrows the layer the user draws in, and two operations read
% that same layer as their input: ``SplitBySelection`` takes it as the cut and
% ``Connect`` in ``selection`` mode takes it as the bridge. A highlight covers
% the **whole** of a picked object, so leaving it in place would swallow the
% cut - the split would find nothing left to keep and report that the Selection
% covers the whole object. The layer is therefore handed back before any
% operation reads it, and as soon as the user starts drawing in it.
%
% What goes back is what was in the box before the highlight was painted, plus
% anything drawn since that does not sit on the highlight itself. Voxels drawn
% *inside* a highlighted object cannot be told apart from the highlight and are
% not recoverable, which is why the workflow is to draw the cut first and pick
% the object afterwards. Nothing is silently lost: the highlight disappears the
% moment the user draws, so what is left in the layer is what will be used.
%
% Writes are confined to the box the highlight was painted into and go to the
% dataset and time point it was painted from, not to whatever is active now.
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)
%
% See also: controllers.InstanceEditor.highlightObjects,
% controllers.InstanceEditor.runOperation

% Updates
%

if isempty(obj.highlightState); return; end

% Dropped before the write, which comes back through the SetData listener.
state = obj.highlightState;
obj.highlightState = [];

% The dataset the highlight was taken from is not necessarily the active one any
% more, so the box is checked against that dataset as it stands now: one that has
% been closed, or reloaded at a different size, gets nothing written into it.
if numel(obj.mibModel.I) < state.id; return; end
dataset = obj.mibModel.I{state.id};
if ~isvalid(dataset) || dataset.enableSelection == 0; return; end
if state.box(2) > dataset.image.height || state.box(4) > dataset.image.width || ...
        state.box(6) > dataset.image.depth || state.timePoint > dataset.image.time
    return;
end
options = struct('blockModeSwitch', 0, 'id', state.id, ...
    'y', state.box(1:2), 'x', state.box(3:4), 'z', state.box(5:6));

current = cell2mat(obj.mibModel.getData3D('selection', state.timePoint, 3, NaN, options));
restored = state.stash;
restored(current > 0 & ~state.painted) = 1;

obj.internalEdit = true;
restoreFlag = onCleanup(@() obj.clearInternalEditFlag());
obj.mibModel.setData3D(restored, 'selection', state.timePoint, 3, [], options);
clear restoreFlag;

notify(obj.mibModel, 'ShowImage');
end
