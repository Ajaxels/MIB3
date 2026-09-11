function runOperation(obj, action)
% RUNOPERATION - Hand an operation to models.MibModel.editInstanceObjects.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.runOperation('Merge')
%
% The controller holds no editing logic: it collects the widget values and the
% picked objects into a BatchOpt and calls the model method, which owns the
% undo, the writes and the refresh of the object index. That is also what makes
% every operation available to batch protocols without a second implementation.
%
% Input Arguments:
%   - **action** - char, one of the actions of ``MibModel.editInstanceObjects``
%
% Output Arguments:
%   (none)

% Updates
%

% One callback serves all eight operation buttons and the action is what tells
% them apart, so it is the action that the marker prints.
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.InstanceEditor.runOperation(%s): triggered\n', action);
end

if ~obj.modelIsEditable(); return; end

% Merge, Split by selection and Connect need no pick: the drawing says which
% objects are meant and the model works them out from it - for Connect, the
% objects at either end of the bridge. Picking objects anyway restricts the
% action to them, which is what a line clipping a neighbour needs. With nothing
% picked *and* nothing drawn the model says so, in words that name what to draw;
% the generic warning below would be a worse answer.
needsObjects = ~ismember(action, {'Cleanup', 'Compact', 'Merge', 'SplitBySelection', 'Connect'});
if needsObjects && isempty(obj.selectedObjects)
    uialert(obj.view.gui, 'Pick the objects to work on first, in the list or by clicking them in the image.', ...
        'Nothing selected', 'Icon', 'warning');
    return;
end

% Cleanup is the only operation with settings of its own and no widgets for
% them: they are asked for here, seeded with the last answer of the session.
% Cancelling the dialog cancels the operation, rather than running it on
% thresholds the user was in the middle of changing.
if strcmp(action, 'Cleanup') && ~obj.askCleanupSettings(true); return; end

obj.updateBatchOptFromGUI();

% The Selection layer is the user's drawing surface and the editor's highlight
% at once, and two of the operations read it as their input. The highlight is
% handed back before the model looks at it: it covers the whole of the picked
% object, so a Split by selection would otherwise be told that the cut covers
% everything and there is nothing left to keep. The model clears what it
% consumed afterwards, so a drawing cannot be applied twice.
obj.releaseHighlight();

BatchOpt = obj.BatchOpt;
BatchOpt.Action = {action};
BatchOpt.ObjectIndices = strjoin(arrayfun(@num2str, obj.selectedObjects, 'UniformOutput', false), ', ');
BatchOpt.id = obj.mibModel.getActiveId();

% editInstanceObjects refreshes the object index itself. Without this guard the
% SetData listener would fire during its write and mark the index it has just
% refreshed as stale, forcing a needless whole-volume rebuild on the next click.
obj.internalEdit = true;
restoreFlag = onCleanup(@() obj.clearInternalEditFlag());
applied = obj.mibModel.editInstanceObjects(BatchOpt);
clear restoreFlag;

% The slice the 2D list is measured from has just been rewritten.
if applied; obj.invalidateSliceStats(); end

% An applied operation ends the job the selection was made for, so it is dropped
% and the highlight with it. Leaving the survivor of a Merge picked is worse than
% useless: a plain click adds to the selection, so the next pair the user picks
% would quietly be a triple including an object they had already finished with.
% Only when the edit actually happened, though - a rejected Connect on three
% objects must not clear the selection as if it had worked.
if applied
    obj.selectedObjects = [];
end

obj.updateWidgets();
obj.highlightObjects();

% editInstanceObjects notifies UpdateGuiWidgets, and MibController answers that
% by reinstalling the image document's own mouse callbacks.
obj.reassertPickMode();
end
