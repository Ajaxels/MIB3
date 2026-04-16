% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <https://www.gnu.org/licenses/>

% Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
% part of Microscopy Image Browser, http:\\mib.helsinki.fi
% Date: 16.04.2025

function crop(obj, cropF)
% function crop(obj, cropF)
% Crop @em obj.data{1} in-place and update all scalar dimension properties.
%
% Crops the stored 5-D array along X, Y, Z and T according to the supplied
% crop parameters.  Scalar dimension properties (@em height, @em width,
% @em depth, @em time, @em dim_yxzct) and the @em sliceName list are
% updated to reflect the new extents.  The bounding box and @em pixSize
% are @b not updated here — the caller (@em core.MibDataset.cropDataset)
% is responsible for that.
%
% Because @em core.MibLabels and @em core.MibLabels63 both inherit from
% @em core.MibImage and share the same @code [h, w, d, c, t] @endcode
% layout for their @em data{1} array (with @em c = 1 for label layers),
% this method works unchanged for all layer types.
%
% Parameters:
% cropF: a vector @code [x1, y1, dx, dy, z1, dz, t1, dt] @endcode
%   in pixels where @em x1, @em y1 are the top-left corner,
%   @em dx, @em dy are width and height of the crop region,
%   @em z1, @em dz are the first slice and depth, and @em t1, @em dt
%   are the first frame and number of frames.

%|
% @b Examples:
% @code obj.mibModel.I{obj.mibModel.id}.image.crop([10 20 100 200 1 5 1 1]);  // call from controller; crop to x=10..109, y=20..219, z=1..5, t=1 @endcode
% @code obj.mibModel.I{obj.mibModel.id}.labels.crop(cropF);                   // crop the labels layer with the same cropF vector @endcode

x1 = cropF(1);  dx = cropF(3);
y1 = cropF(2);  dy = cropF(4);
z1 = cropF(5);  dz = cropF(6);
t1 = cropF(7);  dt = cropF(8);

% Crop data{1}: layout is [height, width, depth, colors, time]
obj.data{1} = obj.data{1}( ...
    y1:y1+dy-1, ...
    x1:x1+dx-1, ...
    z1:z1+dz-1, ...
    :, ...
    t1:t1+dt-1);

% Update scalar dimension properties from the cropped array
obj.height = size(obj.data{1}, 1);
obj.width  = size(obj.data{1}, 2);
obj.depth  = size(obj.data{1}, 3);
obj.time   = size(obj.data{1}, 5);
obj.dim_yxzct = [obj.height, obj.width, obj.depth, obj.colors, obj.time];

% Trim sliceName if the dataset had per-slice filenames
if numel(obj.sliceName) > 1
    obj.sliceName = obj.sliceName(z1 : z1+dz-1);
end
end
