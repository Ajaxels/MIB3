function [axesX, axesY] = getAxesLimits(obj)
% function [axesX, axesY] = getAxesLimits(obj)
% get axes limits for the dataset
%
% Parameters:
%
% Return values:
% axesX: a vector [min, max] for the X
% axesY: a vector [min, max] for the Y

%| 
% @b Examples:
% @code [axesX, axesY] = obj.mibModel.I{obj.mibModel.id}.getAxesLimits();     // call from mibController: get axes limits for the currently shown dataset @endcode
% @code [axesX, axesY] = obj.mibModel.I{2}.getAxesLimits();     // call from mibController: get axes limits for dataset 2 (global index) @endcode

% Updates
% 

axesX = obj.axesX;
axesY = obj.axesY;
end

