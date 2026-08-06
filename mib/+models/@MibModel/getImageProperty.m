function propertyValue = getImageProperty(obj, propertyName, id)
% GETIMAGEPROPERTY - Get a property of the currently shown or specified MibDataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       propertyValue = obj.getImageProperty(propertyName, id)
%
% A convenience wrapper that reads a named property directly from
% obj.I{id}.(propertyName).  Useful for code that may not know
% the active dataset index in advance.
%
% Input Arguments:
%   - **propertyName** - string with the property name to read from MibDataset
%   - **id** - *(optional)* index of the dataset; default is obj.getActiveId()
%
% Output Arguments:
%   - **propertyValue** - value of the requested property, or [] on error
%
% Usage:
%   **Example 1** - get orientation of the active dataset
%
%   .. code-block:: matlab
%
%      orientation = obj.mibModel.getImageProperty('orientation');
%
%   **Example 2** - get depth of dataset 2
%
%   .. code-block:: matlab
%
%      depth = obj.mibModel.getImageProperty('depth', 2);
%

% Updates
%

propertyValue = [];

if nargin < 3; id = obj.getActiveId(); end
if ~isprop(obj.I{id}, propertyName)
    utils.dlgs.showErrorDialog([], ...
        sprintf('Error in MibModel.getImageProperty!\n\nUnknown property: "%s"', propertyName), ...
        'Wrong property');
    return;
end
propertyValue = obj.I{id}.(propertyName);
end
