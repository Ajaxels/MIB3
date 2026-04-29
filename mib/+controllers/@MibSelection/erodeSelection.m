function erodeSelection(obj)
% ERODESELECTION - Shrink (erode) the Selection layer for the current dataset.
%
% Syntax:
%   function erodeSelection(obj)
%
% Reads modifier keys to determine the dataset scope, then reads the
% Apply-in-3D, Difference and Strel-size widgets from the Selection panel.
% When Apply-in-3D is checked the user is asked to confirm before
% proceeding, and the scope is promoted to at least '3D, Stack'.
% All heavy lifting is delegated to obj.mibModel.erodeImage.
%
% Modifier-key scope rules (same as clearSelection):
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
%     obj.erodeSelection();  // called from the Erode button callback
%
%   Example 2 - Simulated call with 3D strel confirmed::
%
%     % Simulated call with 3D strel confirmed:
%     % (modifier keys are read automatically; no arguments needed)
%     obj.mibController.cImageDoc{1}.erodeSelection();
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
differenceSelection = obj.mibModel.differenceSelection;
strelSize  = obj.handles.strel.Value;

%% Decide ErodeMode; confirm 3D with the user
if applySegmentationIn3D
    button = utils.dlgs.inputQuestDlg(obj.mibModel.mibGUI, ...
        sprintf('You are going to erode the image in 3D!\nContinue?'), ...
        'Erode 3D objects', 'Continue', 'Cancel', 'Continue');
    if ~strcmp(button, 'Continue'); return; end
    ErodeMode = '3D';
    if strcmp(DatasetType, '2D, Slice'); DatasetType = '3D, Stack'; end
else
    ErodeMode = '2D';
end

%% Build BatchOpt and delegate to MibModel
BatchOpt.TargetLayer = {'selection'};
BatchOpt.DatasetType = {DatasetType};
BatchOpt.ErodeMode   = {ErodeMode};
BatchOpt.Difference  = logical(differenceSelection);
BatchOpt.StrelSize   = strelSize;

obj.mibModel.erodeImage(BatchOpt);
end
