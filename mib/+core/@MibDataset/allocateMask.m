function allocateMask(obj)
% ALLOCATEMASK - allocate a zero-filled Mask layer when it is missing.
%
% For datasets with a ``MibLabels63`` model the mask is stored in bit 7 of
% the packed labels array and needs no separate container - the method
% returns without action. For all other model types, when ``obj.mask`` is an
% empty placeholder (``obj.mask.exists == false``) it is replaced with a
% zero-filled ``core.MibLabels`` container matching the image dimensions, so
% the mask can be read and written via getData/setData without size-mismatch
% errors. Sets ``obj.maskExist = true`` after allocation.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.allocateMask()
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)
%
% Usage:
%   .. code-block:: matlab
%
%      % ensure the mask container exists before adding data to it
%      obj.mibModel.I{id}.allocateMask();
%

% Updates
%

% the mask of MibLabels63 models lives in the packed bits - nothing to allocate
if isa(obj.labels, 'core.MibLabels63'); return; end
if obj.mask.exists; return; end

maskMeta = core.MibImage.initializeImgInfo( ...
    'pixSize',   obj.image.pixSize, ...
    'Height',    obj.image.height, ...
    'Width',     obj.image.width,  ...
    'Depth',     obj.image.depth,  ...
    'Time',      obj.image.time,   ...
    'Colors',    1, ...
    'SliceSize', obj.image.sliceSize);
maskDims = [obj.image.height, obj.image.width, obj.image.depth, 1, obj.image.time];
obj.mask = core.MibLabels(zeros(maskDims, 'uint8'), maskMeta);
obj.maskExist = true;
end
