function clearSelection(obj)
% function clearSelection(obj)
% Clear the Selection layer for the current dataset
%
% Reads modifier keys held at call time to decide the clear scope:
% @li no modifier           -> '2D, Slice'   (current slice only)
% @li Alt or Shift          -> '3D, Stack'   (full z-stack at current t)
% @li Alt + Shift           -> '4D, Dataset' (entire dataset)
%
% When only one time point is present, '4D, Dataset' is demoted to
% '3D, Stack' automatically.
%
% The method simply delegates to obj.mibModel.clearSelection with the
% appropriate scope string; all backup, waitbar, and event handling is
% done there.
%
% Parameters:
%   (none)
%
% Return values:
%   (none)
%

%| 
% @b Examples:
% @code obj.clearSelection();   // called from the Clear button callback or keyboard shortcut @endcode

% Updates
%

if obj.mibModel.I{obj.mibModel.id}.enableSelection == 0; return; end

% Read modifier state stored by gui_WindowKeyPressFcn / cleared by gui_WindowKeyReleaseFcn.
% UIFigure.CurrentModifier is NOT used here: it is only updated by keyboard
% events on that specific sub-figure and returns {} for button clicks coming
% from the Selection panel (a different sub-figure in the AppContainer).
modifier = obj.mibController.currentModifier;
obj.mibController.currentModifier = {};  % clear before notify/drawnow yield points below

if sum(ismember({'alt', 'shift'}, modifier)) == 2
    % Alt + Shift: 4D scope (or 3D if only one time point)
    if obj.mibModel.I{obj.mibModel.id}.image.time == 1
        DatasetType = '3D, Stack';
    else
        DatasetType = '4D, Dataset';
    end
elseif sum(ismember({'alt', 'shift'}, modifier)) == 1
    % Alt or Shift alone: 3D scope
    DatasetType = '3D, Stack';
else
    % No modifier: 2D scope
    DatasetType = '2D, Slice';
end

obj.mibModel.clearSelection(DatasetType);
end
