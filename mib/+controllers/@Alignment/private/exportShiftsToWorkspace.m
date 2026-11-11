function exportShiftsToWorkspace(obj)
% EXPORTSHIFTSTOWORKSPACE - Copy the alignment coefficients to the MATLAB base workspace.
%
% Syntax:
%   .. code-block:: matlab
%
%      exportShiftsToWorkspace(obj)
%
% Assigns ``obj.shiftsX`` / ``obj.shiftsY`` to the base workspace as
% ``shiftsX`` / ``shiftsY`` - the variable names used inside the
% ``.coefXY`` file, so the exported values can be saved and loaded back
% with the "Load shifts" option. Called by every ``*_Alignment`` method at
% the point where its coefficients are final (freshly computed or loaded
% from a file), in GUI and batch mode alike.
%
% It must run inside the algorithm, before the algorithm notifies
% ``NewDataset``: that event reaches the controller's listener, whose
% :meth:`updateWidgets` empties ``obj.shiftsX`` / ``obj.shiftsY``, so by
% the time :meth:`continueBtn_Callback` regains control nothing is left
% to export.
%
% The content depends on the algorithm: shift vectors (drift correction,
% single landmark), scalar shifts (three landmarks), cell arrays of tforms
% and imref2d (feature-based v1, AMST, multi-point), or an align struct
% (feature-based v2, shiftsY empty).
%
% Does nothing when ``obj.shiftsX`` is empty or in the deployed app, which
% has no base workspace for the user.
%
% Input Arguments:
%   - **obj** - [controllers.Alignment] the alignment controller

if isdeployed || isempty(obj.shiftsX); return; end

assignin('base', 'shiftsX', obj.shiftsX);
assignin('base', 'shiftsY', obj.shiftsY);
fprintf('Alignment coefficients were exported to MATLAB workspace (shiftsX, shiftsY).\n');
end
