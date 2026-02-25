function setAxesLimits(obj, axesX, axesY, id)
% function setAxesLimits(obj, axesX, axesY, id)
% set axes limits for the currently shown or id dataset
%
% Parameters:
% id: [@b optional], id of the dataset, otherwise the currently shown
% dataset (obj.id)
%
% Return values:
% axesX: a vector [min, max] for X
% axesY: a vector [min, max] for Y

%| 
% @b Examples:
% @code [axesX, axesY] = obj.mibModel.setAxesLimits([1 512],  [1 512]);     // call from mibController: set axes limits for the currently shown dataset @endcode
% @code [axesX, axesY] = obj.mibModel.setAxesLimits([1 512],  [1 512], 2);     // call from mibController: set axes limits for dataset 2 @endcode

% Updates
% 

if nargin < 4; id = obj.id; end
if nargin < 3
    errordlg(sprintf('!!! Error !!!\n\nthe axesX, axesY parameters are missing'),'mibModel.setAxesLimits');
    return; 
end

obj.I{id}.setAxesLimits(axesX, axesY);

end