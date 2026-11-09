function popup = homeUpdateParallelPool(obj, ~, ~)
% HOMEUPDATEPARALLELPOOL - Refresh the Parallel pool entry of the Preferences menu just before the menu opens.
%
% The callback of ``DynamicPopupFcn`` of the Preferences split button. A
% pool is also started by the tools that run in parallel and closed by the
% idle timeout of MATLAB, neither of which passes through the entry, so its
% tick and description are read from the pool each time the menu opens.
% Without Parallel Computing Toolbox the entry is disabled.
%
% Syntax:
%   .. code-block:: matlab
%
%       popup = obj.homeUpdateParallelPool(hButton, hData)
%
% Input Arguments:
%   - **hButton** - the split button, not used
%   - **hData** - event data of the toolstrip, not used
%
% Output Arguments:
%   - **popup** - ``matlab.ui.internal.toolstrip.PopupList``, the popup of the Preferences split button
%

popup = obj.handles.ribbonHome.preferences.Popup;
poolEntry = obj.handles.ribbonHome.parallelPool;
try
    pool = gcp('nocreate');
catch
    poolEntry.Enabled = false;
    poolEntry.Description = 'Requires Parallel Computing Toolbox';
    return;
end
poolEntry.Value = ~isempty(pool);
if isempty(pool)
    poolEntry.Description = sprintf('Not running, tick to start %d workers', obj.mibModel.preferences.System.cpuParallelLimit);
else
    poolEntry.Description = sprintf('Running with %d workers, clear to stop', pool.NumWorkers);
end
end
