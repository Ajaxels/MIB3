function fillSelection(obj)
% FILLSELECTION - Fill holes in the Selection layer for the current dataset.
%
% Syntax:
%   function fillSelection(obj)
%
% Reads modifier keys to determine the dataset scope, then reads the
% restrictSelectionToMaterial state from the dataset and delegates to
% obj.mibModel.fillSelectionOrMask.
%
% Modifier-key scope rules (same as erodeSelection, dilateSelection, clearSelection):
%   - no modifier '2D, Slice'  (current slice only)
%   - Alt or Shift '3D, Stack'  (full z-stack at current t)
%   - Alt + Shift '4D, Dataset' (entire dataset)
%
% When only one time point is present, '4D, Dataset' is demoted to
% '3D, Stack' automatically.
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)
%
% Usage:
%   Example 1::
%
%     obj.fillSelection();  // called from the Fill button callback or keyboard shortcut
%

% Updates
%

if obj.mibModel.I{obj.mibModel.id}.enableSelection == 0; return; end

% Read modifier state stored by gui_WindowKeyPressFcn / cleared by gui_WindowKeyReleaseFcn.
% UIFigure.CurrentModifier is NOT used here: it is only updated by keyboard
% events on that specific sub-figure and returns {} for button clicks
% originating from the Selection panel.
modifier = obj.mibController.currentModifier;

%% Determine dataset scope from modifier keys
if sum(ismember({'alt', 'shift'}, modifier)) == 2
    if obj.mibModel.I{obj.mibModel.id}.image.time == 1
        DatasetType = '3D, Stack';
    else
        DatasetType = '4D, Dataset';
    end
elseif sum(ismember({'alt', 'shift'}, modifier)) == 1
    DatasetType = '3D, Stack';
else
    DatasetType = '2D, Slice';
end

%% Read dataset-level restrict settings
dataset = obj.mibModel.I{obj.mibModel.id};

%% Build BatchOpt and delegate to MibModel
BatchOpt.TargetLayer = {'selection'};
BatchOpt.DatasetType = {DatasetType};
BatchOpt.SelectedMaterial            = num2str(dataset.getSelectedMaterialIndex());
BatchOpt.restrictSelectionToMaterial = logical(dataset.restrictSelectionToMaterial);

obj.mibModel.fillSelectionOrMask('selection', BatchOpt);
end
