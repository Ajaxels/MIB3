function [axesX, axesY] = getAxesLimits(obj, id)
% function [axesX, axesY] = getAxesLimits(obj, id)
% get axes limits for the currently shown or id dataset
%
% Parameters:
% id: [@b optional], id of the dataset, otherwise the currently shown
% dataset (obj.mibModel.id)
%
% Return values:
% axesX: a vector [min, max] for the X
% axesY: a vector [min, max] for the Y

%| 
% @b Examples:
% @code [axesX, axesY] = obj.mibModel.getAxesLimits();     // call from mibController: get axes limits for the currently shown dataset @endcode
% @code [axesX, axesY] = obj.mibModel.getAxesLimits(2);     // call from mibController: get axes limits for dataset 2 @endcode

% Updates
% 

if nargin < 2; id = obj.id; end
axesX = obj.I{id}.axesX;
axesY = obj.I{id}.axesY;
end
