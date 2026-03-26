function propertyValue = getImageProperty(obj, propertyName, id)
% function propertyValue = getImageProperty(obj, propertyName, id)
% Get a property of the currently shown or specified MibDataset.
%
% A convenience wrapper that reads a named property directly from
% obj.I{id}.(propertyName).  Useful for code that may not know
% the active dataset index in advance.
%
% Parameters:
% propertyName: string with the property name to read from MibDataset
% id: [@em optional] index of the dataset; default is obj.getActiveId()
%
% Return values:
% propertyValue: value of the requested property, or [] on error
%
%|
% @b Examples:
% @code orientation = obj.mibModel.getImageProperty('orientation');     // get orientation of the active dataset @endcode
% @code depth = obj.mibModel.getImageProperty('depth', 2);             // get depth of dataset 2 @endcode

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
