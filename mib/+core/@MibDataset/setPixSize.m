function setPixSize(obj, val)
% function setPixSize(obj, val)
% Propagate a new pixSize struct to all four dataset layers.
%
% Usage:
%   .. code-block:: matlab
%
%       obj.setPixSize(newPixSize)
%
% This is the ONLY sanctioned write path for voxel size on a MibDataset.
% After the call every layer that has its own save/load method (image,
% labels, mask, selection) holds the same up-to-date pixSize, so those
% methods never need to receive pixSize via an options argument.
%
% To READ the current voxel size use:
%   pixSize = obj.image.pixSize;   % authoritative copy
%
% Parameters:
%   val  struct with fields .x .y .z .t .units .tunits (same as utils.defaults.initializePixSize)

for layerName = {'image', 'labels', 'mask', 'selection'}
    layer = obj.(layerName{1});
    if isobject(layer) && isprop(layer, 'pixSize')
        layer.pixSize = val;
    end
end
end
