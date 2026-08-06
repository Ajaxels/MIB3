function selectionActions(obj, action)
% SELECTIONACTIONS - Wrapper for Add/Subtract/Replace buttons to move selection to material/mask.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.selectionActions(action)
%
% Determines destination layer (mask or model) from selected "Add to" material index,
% reads dataset scope from modifier keys, then delegates to ``obj.mibModel.moveLayers``.
%
% Input Arguments:
%   - **action** - [char] the button that was pressed:
%
%     - ``'add'`` - add selection to active material/mask
%     - ``'subtract'`` - subtract selection from active material/mask
%     - ``'replace'`` - replace active material/mask with selection
%
% **Example 1** - called from Add button:
%
%   .. code-block:: matlab
%
%      obj.selectionActions('add');
%
% **Example 2** - called from Subtract button:
%
%   .. code-block:: matlab
%
%      obj.selectionActions('subtract');
%
% **Example 3** - called from Replace button:
%
%   .. code-block:: matlab
%
%      obj.selectionActions('replace');
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
