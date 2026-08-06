function [axesX, axesY] = getAxesLimits(obj)
% GETAXESLIMITS - get axes limits for the dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       [axesX, axesY] = obj.getAxesLimits()
%
% Input Arguments:
%
% Output Arguments:
%   - **axesX** - a vector [min, max] for the X
%   - **axesY** - a vector [min, max] for the Y
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     [axesX, axesY] = obj.mibModel.I{obj.mibModel.id}.getAxesLimits();% call from mibController: get axes limits for the currently shown dataset
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     [axesX, axesY] = obj.mibModel.I{2}.getAxesLimits();% call from mibController: get axes limits for dataset 2 (global index)
%

% Updates
% 

axesX = obj.axesX;
axesY = obj.axesY;
end

