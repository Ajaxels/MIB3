function updateBoundingBox(obj, newBB, xyzShift, imgDims)
% UPDATEBOUNDINGBOX - Delegate bounding-box update to the image layer.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.updateBoundingBox(newBB, xyzShift, imgDims)
%
% After the call obj.image.pixSize and obj.image.boundingBox are updated.
% The other layers (labels, mask, selection) share the same pixSize because
% setPixSize() was called by the controller prior to this call (see
% BoundingBox.applyButton_Callback for the canonical usage pattern).
%
% Parameters: identical to core.MibImage.updateBoundingBox - see that file.

if nargin < 4; imgDims  = []; end
if nargin < 3; xyzShift = []; end
if nargin < 2; newBB    = []; end

obj.image.updateBoundingBox(newBB, xyzShift, imgDims);

% updateBoundingBox recalculates pixSize.x/y/z and boundingBox from the
% new extent.  Propagate both to all other layers so savers always have
% consistent metadata regardless of which layer they write.
obj.setPixSize(obj.image.pixSize);
for layerName = {'labels', 'mask', 'selection'}
    layer = obj.(layerName{1});
    if isobject(layer) && isprop(layer, 'boundingBox')
        layer.boundingBox = obj.image.boundingBox;
    end
end
end
