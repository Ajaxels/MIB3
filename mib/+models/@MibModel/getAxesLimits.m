function [axesX, axesY] = getAxesLimits(obj, id)
% GETAXESLIMITS - get axes limits for the currently shown or id dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       [axesX, axesY] = obj.getAxesLimits(id)
%
% Input Arguments:
%   - **id** — *(optional)* id of the dataset, otherwise the currently shown
%     dataset (obj.mibModel.id)
%
% Output Arguments:
%   - **axesX** — a vector [min, max] for the X
%   - **axesY** — a vector [min, max] for the Y
%
% Usage:
%   **Example 1** — get axes limits for the currently shown dataset
%
%   .. code-block:: matlab
%
%      [axesX, axesY] = obj.mibModel.getAxesLimits();
%
%   **Example 2** — get axes limits for dataset 2
%
%   .. code-block:: matlab
%
%      [axesX, axesY] = obj.mibModel.getAxesLimits(2);
%

% Updates
% 

if nargin < 2; id = obj.id; end
axesX = obj.I{id}.axesX;
axesY = obj.I{id}.axesY;
end
