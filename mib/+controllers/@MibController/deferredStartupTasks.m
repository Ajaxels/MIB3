function deferredStartupTasks(obj)
% DEFERREDSTARTUPTASKS - Run startup tasks that were deferred to keep startup fast.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.deferredStartupTasks()
%
% Executed once from the single-shot ``obj.updateCheckTimer`` a few seconds
% after the main window becomes visible. Performs work that would otherwise
% block the startup:
%
% - warms up ``MibModel.cpuParallelLimitMax`` (the lazy getter queries the
%   parallel cluster profile, ~250 ms, and clamps
%   ``preferences.System.cpuParallelLimit`` to the available workers)
% - checks the MIB website for availability of a newer version
%
% Output Arguments:
%   (none)
%

arguments (Input)
    obj controllers.MibController
end

% MIB may have been closed between timer creation and firing
if isempty(obj.view) || ~isvalid(obj.view.gui); return; end

try
    parallelLimit = obj.mibModel.cpuParallelLimitMax; %#ok<NASGU> % warm up the lazy parcluster query
catch
    % parallel computing toolbox may be unavailable; consumers fall back gracefully
end

obj.checkForUpdate();

end
