function cpuParallelLimitMax = getMaxParpoolWorkers()
% function cpuParallelLimitMax = getMaxParpoolWorkers()
%
% define max number of parallel workers for deployed versions
% define workers for parallel pools
%
% Parameters:
%
% Return values:
% cpuParallelLimitMax: maximal number of workers available for parallel
% processing

%|
% @b Examples:
% @code
% cpuParallelLimitMax = utils.getMaxParpoolWorkers();
% @endcode
%
% Updates
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

