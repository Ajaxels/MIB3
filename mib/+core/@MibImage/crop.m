function crop(obj, cropF)
% CROP - Crop *obj.data* in-place and update all scalar dimension properties.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.crop(cropF)
%
% Crops the stored 5-D array along X, Y, Z and T according to the supplied
% crop parameters.  Scalar dimension properties (*height,* *width,*
% *depth,* *time,* *dim_yxzct)* and the *sliceName* list are
% updated to reflect the new extents.  The bounding box and *pixSize*
% are **not** updated here - the caller (*core.MibDataset.cropDataset)*
% is responsible for that.
%
% Because *core.MibLabels* and *core.MibLabels63* both inherit from
% *core.MibImage* and share the same ``[h, w, d, c, t]``
% layout for their *data{1}* array (with *c* = 1 for label layers),
% this method works unchanged for all layer types.
%
% Input Arguments:
%   - **cropF** - a vector ``[x1, y1, dx, dy, z1, dz, t1, dt]``
%     in pixels where *x1,* *y1* are the top-left corner,
%     *dx,* *dy* are width and height of the crop region,
%     *z1,* *dz* are the first slice and depth, and *t1,* *dt*
%     are the first frame and number of frames.
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.I{obj.mibModel.id}.image.crop([10 20 100 200 1 5 1 1]);% call from controller; crop to x=10..109, y=20..219, z=1..5, t=1
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.I{obj.mibModel.id}.labels.crop(cropF);% crop the labels layer with the same cropF vector
%

x1 = cropF(1);  dx = cropF(3);
y1 = cropF(2);  dy = cropF(4);
z1 = cropF(5);  dz = cropF(6);
t1 = cropF(7);  dt = cropF(8);

% Check if X/Y dimensions are changing (needed for sliceSize clearing)
xyChanged = (x1 > 1) || (y1 > 1) || (dx < obj.width) || (dy < obj.height);

% Crop data{1}: layout is [height, width, depth, colors, time]
obj.data = obj.data( ...
    y1:y1+dy-1, ...
    x1:x1+dx-1, ...
    z1:z1+dz-1, ...
    :, ...
    t1:t1+dt-1);

% Update scalar dimension properties from the cropped array
obj.height = size(obj.data, 1);
obj.width  = size(obj.data, 2);
obj.depth  = size(obj.data, 3);
obj.time   = size(obj.data, 5);
obj.dim_yxzct = [obj.height, obj.width, obj.depth, obj.colors, obj.time];

% Trim sliceName if the dataset had per-slice filenames
if numel(obj.sliceName) > 1
    obj.sliceName = obj.sliceName(z1 : z1+dz-1);
end

% Clear sliceSize if X or Y was cropped (original sizes no longer restorable);
% otherwise trim to the new Z range
if ~isempty(obj.sliceSize)
    if xyChanged
        obj.sliceSize = [];
    elseif size(obj.sliceSize, 1) > 1
        obj.sliceSize = obj.sliceSize(z1:z1+dz-1, :);
    end
end
end
