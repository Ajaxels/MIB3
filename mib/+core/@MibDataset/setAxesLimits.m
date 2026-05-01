function setAxesLimits(obj, axesX, axesY)
% SETAXESLIMITS - set axes limits for the dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.setAxesLimits(axesX, axesY)
%
% Input Arguments:
%   - **axesX** — a vector [min, max] for for X
%   - **axesY** — a vector [min, max] for for Y
%
% Output Arguments:
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     [axesX, axesY] = obj.mibModel.I{obj.mibModel.id}.setAxesLimits([1 512],  [1, 512]);% call from mibController: set axes limits for the currently shown dataset
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     [axesX, axesY] = obj.mibModel.I{2}.setAxesLimits([1 512],  [1, 512]);% call from mibController: set axes limits for dataset 2
%

% Updates
% 

if nargin < 3
    errordlg(sprintf('!!! Error !!!\n\nthe axesX, axesY parameters are missing'),'MibDataset.setAxesLimits');
    return; 
end

obj.axesX = axesX;
obj.axesY = axesY;

% update obj.slices
if obj.orientation == 3    % xy
    obj.slices{1}(1) = ceil(max([axesY(1) 1]));
    obj.slices{1}(2) = ceil(min([axesY(2) obj.image.height]));
    obj.slices{2}(1) = ceil(max([axesX(1) 1]));
    obj.slices{2}(2) = ceil(min([axesX(2) obj.image.width]));
elseif obj.orientation == 1     % xz
    obj.slices{2}(1) = ceil(max([axesY(1) 1]));
    obj.slices{2}(2) = ceil(min([axesY(2) obj.image.width]));
    obj.slices{3}(1) = ceil(max([axesX(1) 1]));
    obj.slices{3}(2) = ceil(min([axesX(2) obj.image.depth]));    
elseif obj.orientation == 2     % yz
    obj.slices{1}(1) = ceil(max([axesY(1) 1]));
    obj.slices{1}(2) = ceil(min([axesY(2) obj.image.height]));
    obj.slices{3}(1) = ceil(max([axesX(1) 1]));
    obj.slices{3}(2) = ceil(min([axesX(2) obj.image.depth])); 
end

end
