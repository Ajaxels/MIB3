function selectionActions(obj, action)
% SELECTIONACTIONS - Wrapper for the A / S / R (Add / Subtract / Replace) buttons in the.
%
% Syntax:
%   function selectionActions(obj, action)
%
% Selection panel.
%
% Determines the destination layer (mask or model) from the currently
% selected "Add to" material index, reads the dataset scope from modifier
% keys, then delegates to obj.mibModel.moveLayers.
%
% Input Arguments:
%   - **action** — char, the button that was pressed
%     - 'add'      - add selection to the active material / mask
%     - 'subtract' - subtract selection from the active material / mask
%     - 'replace'  - replace the active material / mask with selection
%
% Output Arguments:
%   (none)
%
% Usage:
%   Example 1::
%
%     obj.selectionActions('add');      // called from the A button callback
%
%   Example 2::
%
%     obj.selectionActions('subtract'); // called from the S button callback
%
%   Example 3::
%
%     obj.selectionActions('replace');  // called from the R button callback
%

% Updates
%

if obj.mibModel.I{obj.mibModel.id}.enableSelection == 0; return; end

%% Determine destination layer
if obj.mibModel.I{obj.mibModel.id}.getSelectedMaterialIndex('AddTo') == -1
    layerTo = 'mask';
else
    layerTo = 'labels';
end

%% Determine dataset scope from modifier keys
% UIFigure.CurrentModifier is NOT used here because it is only updated by
% keyboard events on that specific sub-figure and returns {} for button
% clicks originating from the Selection panel.
modifier = obj.mibController.currentModifier;

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

%% Map action name ('subtract' -> 'remove' as used by moveLayers)
switch action
    case 'add';      ActionType = 'add';
    case 'subtract'; ActionType = 'remove';
    case 'replace';  ActionType = 'replace';
    otherwise; return;
end

obj.mibModel.moveLayers('selection', layerTo, DatasetType, ActionType);
end
