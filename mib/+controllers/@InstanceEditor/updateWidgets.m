function updateWidgets(obj)
% UPDATEWIDGETS - Refresh the window from the current state of the model.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.updateWidgets()
%
% Called from the constructor, from the ``UpdateGuiWidgets`` / ``NewDataset`` /
% ``Undo`` listeners and after every operation. Disables the operations when the
% active dataset holds no instance model, drops picked objects that no longer
% exist, and repaints the object list.
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)

% Updates
%

if isempty(obj.view) || ~isvalid(obj.view.gui); return; end
h = obj.view.handles;

editable = obj.modelIsEditable();
operationWidgets = {'mergeButton', 'splitComponentsButton', 'splitBySelectionButton', ...
    'cutAtSliceButton', 'connectButton', 'deleteButton', 'cleanupButton', ...
    'cleanupOptions', 'compactButton', 'rebuildButton', 'pickByClick', ...
    'updateTable', 'autoUpdateTable', 'detectionSettings'};
for widget = operationWidgets
    h.(widget{1}).Enable = editable;
end

if ~editable
    % Leaving the list populated would invite clicks on objects of a model that
    % is no longer there.
    obj.selectedObjects = [];
    obj.displayedIds = [];
    h.objectTable.Data = table();
    h.selectedList.Items = {};
    if obj.pickModeActive; obj.setPickMode(false); end
    h.indexStatusLabel.Text = 'No instance model in the active dataset';
    h.indexStatusLabel.FontColor = [0.5 0.5 0.5];
    return;
end

obj.applyModeToWidgets();

% Drop anything picked that the model no longer contains - after an undo, a
% merge, or a switch of time point.
dataset = obj.mibModel.I{obj.mibModel.getActiveId()};
index = dataset.instanceIndex;
if ~isempty(obj.selectedObjects) && obj.indexIsUsable()
    stillThere = obj.selectedObjects <= index.maxIndex;
    stillThere(stillThere) = index.exists(obj.selectedObjects(stillThere));
    obj.selectedObjects = obj.selectedObjects(stillThere);
end

obj.updateObjectTable();
obj.updateSelectedList();
obj.updateStatusLine();
end
