function setMagFactor(obj, magFactor, id)
% SETMAGFACTOR - set magnification for the currently shown or id dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.setMagFactor(magFactor, id)
%
% Input Arguments:
%   - **magFactor** - magnification factor
%   - **id** - *(optional)* id of the dataset, otherwise the currently shown
%     dataset (obj.id)
%
% Output Arguments:
%
% Usage:
%   **Example 1** - set current magFactor to 2
%
%   .. code-block:: matlab
%
%      obj.mibModel.setMagFactor(2);
%
%   **Example 2** - set magFactor to 2 for dataset 4
%
%   .. code-block:: matlab
%
%      obj.mibModel.setMagFactor(2, 4);
%

% Updates
% 

if nargin < 3; id = obj.id; end 
if nargin < 2
    errordlg(sprintf('!!! Error !!!\n\nthe magFactor parameter is missing'),'mibModel.setMagFactor');
    return;
end

obj.I{id}.magFactor = magFactor;
end


