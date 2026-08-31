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

wholeModelAction = ismember(action, {'Cleanup', 'Compact'});
if ~wholeModelAction && isempty(obj.selectedObjects)
    uialert(obj.view.gui, 'Pick the objects to work on first, in the list or by clicking them in the image.', ...
        'Nothing selected', 'Icon', 'warning');
    return;
end

obj.updateBatchOptFromGUI();

% MaxRows only governs how much of the list is rendered, so it has no business
% in the model's options or in the SyncBatch payload they are published as.
BatchOpt = rmfield(obj.BatchOpt, 'MaxRows');
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
