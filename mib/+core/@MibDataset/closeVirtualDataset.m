function closeVirtualDataset(obj)
% function closeVirtualDataset(obj)
% Close opened virtual dataset readers, otherwise the files locked
%
% Parameters:
%
% Return values:
%

% Updates
%

% delegate to MibVirtualImage which owns the reader handles
if isa(obj.image, 'core.MibVirtualImage')
    obj.image.closeVirtualDataset();
end