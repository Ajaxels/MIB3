function dilateSelection(obj)
% DILATESELECTION - Expand (dilate) the Selection layer for the current dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.dilateSelection()
%
% Reads modifier keys to determine the dataset scope, then reads the
% Apply-in-3D, Difference and Strel-size widgets from the Selection panel.
% When Apply-in-3D is checked the user is asked to confirm before
% proceeding, and the scope is promoted to at least '3D, Stack'.
% All heavy lifting is delegated to obj.mibModel.dilateImage.
%
% Modifier-key scope rules (same as erodeSelection and clearSelection):
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
%     obj.dilateSelection();  // called from the Dilate button callback
%
%   Example 2 - Simulated call with 3D strel confirmed::
%
%     % Simulated call with 3D strel confirmed:
%     % (modifier keys are read automatically; no arguments needed)
%     obj.mibController.cImageDoc{1}.dilateSelection();
%

% Updates
%

if obj.mibModel.I{obj.mibModel.id}.enableSelection == 0; return; end

% Read modifier state stored by gui_WindowKeyPressFcn / cleared by gui_WindowKeyReleaseFcn.
% UIFigure.CurrentModifier is NOT used here because it is only updated by
% keyboard events on that specific sub-figure and returns {} for button clicks
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

%% Read Selection panel state
applySegmentationIn3D = obj.mibModel.applySegmentationIn3D;
differenceSelection   = obj.mibModel.differenceSelection;
strelSize = obj.handles.strel.Value;

%% Restrict-to-material and restrict-to-mask (dataset-level properties)
dataset = obj.mibModel.I{obj.mibModel.id};
if dataset.restrictSelectionToMaterial
    restrictMaterial = num2str(dataset.getSelectedMaterialIndex());
else
    restrictMaterial = 'NaN';
end
restrictMask = logical(dataset.restrictSelectionToMask);

%% Decide DilateMode; confirm 3D with the user
if applySegmentationIn3D
    button = utils.dlgs.inputQuestDlg(obj.mibModel.mibGUI, ...
        sprintf('You are going to dilate the image in 3D!\nContinue?'), ...
        'Dilate 3D objects', 'Continue', 'Cancel', 'Continue');
    if ~strcmp(button, 'Continue'); return; end
    DilateMode = '3D';
    if strcmp(DatasetType, '2D, Slice'); DatasetType = '3D, Stack'; end
else
    DilateMode = '2D';
end

%% Build BatchOpt and delegate to MibModel
BatchOpt.TargetLayer = {'selection'};
BatchOpt.DatasetType = {DatasetType};
BatchOpt.DilateMode  = {DilateMode};
BatchOpt.Difference  = logical(differenceSelection);
BatchOpt.StrelSize   = strelSize;
BatchOpt.restrictSelectionToMaterial = restrictMaterial;
BatchOpt.restrictSelectionToMask     = restrictMask;

obj.mibModel.dilateImage(BatchOpt);
end
