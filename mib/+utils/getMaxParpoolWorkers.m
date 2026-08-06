function cpuParallelLimitMax = getMaxParpoolWorkers()
% GETMAXPARPOOLWORKERS - Define maximum number of parallel workers for deployed versions.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      cpuParallelLimitMax = getMaxParpoolWorkers()
%
% Returns the smaller of the hardware-available worker count and the
% platform-specific compiled-app limit (8 on Windows, 4 on macOS/Linux).
% In the MATLAB development environment, returns ``Inf`` (no limit).
%
% Output Arguments:
%   - **cpuParallelLimitMax** - [numeric] maximum number of workers available for parallel processing
%
% Usage:
%
%   **Example 1** - retrieve the worker limit
%
%   .. code-block:: matlab
%
%      cpuParallelLimitMax = utils.getMaxParpoolWorkers();
%

arguments (Output)
    % https://se.mathworks.com/help/releases/R2025a/matlab/input-and-output-arguments.html
    cpuParallelLimitMax (1,1) double % return maximal number of workers available for parallel 
end

% use try block to make it work with MATLAB Online
try
    % if no pool, do not create new one
    parPool = parcluster('local'); 
catch err
    parPool.NumWorkers = 1;
end

% according to MATLAB license, the deployed version should not have more
% parallel processing workers than workstation where it was compiled
if isdeployed
    if ispc()
        cpuParallelLimitMax = 8;
    elseif ismac()
        cpuParallelLimitMax = 4;
    elseif isunix()
		cpuParallelLimitMax = 4;
	else
        cpuParallelLimitMax = 2;
    end
else % MIB for MATLAB
    cpuParallelLimitMax = Inf;
end

cpuParallelLimitMax = min([cpuParallelLimitMax, parPool.NumWorkers]);

end

