function closeVirtualDataset(obj)
% CLOSEVIRTUALDATASET - Close virtual dataset readers to release file locks.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.closeVirtualDataset()
%
% Closes all opened virtual dataset readers. Necessary to release file locks on
% virtual datasets before closing or switching datasets. No effect if the dataset
% is not a virtual image (``core.MibVirtualImage`` instance).
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)
%

% Updates
%

% delegate to MibVirtualImage which owns the reader handles
if isa(obj.image, 'core.MibVirtualImage')
    obj.image.closeVirtualDataset();
end
