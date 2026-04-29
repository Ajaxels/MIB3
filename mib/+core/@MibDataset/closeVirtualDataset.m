function closeVirtualDataset(obj)
% CLOSEVIRTUALDATASET - Close opened virtual dataset readers, otherwise the files locked.
%
% Syntax:
%   function closeVirtualDataset(obj)
%
% Input Arguments:
%
% Output Arguments:
%

% Updates
%

% delegate to MibVirtualImage which owns the reader handles
if isa(obj.image, 'core.MibVirtualImage')
    obj.image.closeVirtualDataset();
end
