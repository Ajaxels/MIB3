function setAxesLimits(obj, axesX, axesY, id)
% SETAXESLIMITS - set axes limits for the currently shown or id dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.setAxesLimits(axesX, axesY, id)
%
% Input Arguments:
%   - **id** - *(optional)* id of the dataset, otherwise the currently shown
%     dataset (obj.id)
%
% Output Arguments:
%   - **axesX** - a vector [min, max] for X
%   - **axesY** - a vector [min, max] for Y
%
% Usage:
%   **Example 1** - set axes limits for the currently shown dataset
%
%   .. code-block:: matlab
%
%      obj.mibModel.setAxesLimits([1 512], [1 512]);
%
%   **Example 2** - set axes limits for dataset 2
%
%   .. code-block:: matlab
%
%      obj.mibModel.setAxesLimits([1 512], [1 512], 2);
%

% Updates
% 

if nargin < 4; id = obj.id; end
if nargin < 3
    errordlg(sprintf('!!! Error !!!\n\nthe axesX, axesY parameters are missing'),'mibModel.setAxesLimits');
    return; 
end

obj.I{id}.setAxesLimits(axesX, axesY);

end
