function [stretchX, stretchY] = getDisplayStretch(obj, orient)
% GETDISPLAYSTRETCH - Aspect-ratio stretch of the shown slice along the screen axes.
%
% A slice is rendered with one image pixel per data pixel, then stretched on screen
% so that anisotropic voxels keep their physical proportions. The stretch is applied
% through the image ``XData``/``YData`` (see :meth:`controllers.MibController.showImage`)
% and must be undone by every conversion between axes and data coordinates.
%
% Exactly one screen axis is stretched, the one that carries Z in the ZX/ZY views:
%
%   - ``3`` (YX): horizontal X relative to vertical Y, ``[pixSize.x / pixSize.y, 1]``
%   - ``2`` (ZY): horizontal Z relative to vertical Y, ``[pixSize.z / pixSize.y, 1]``
%   - ``1`` (ZX): vertical Z relative to horizontal X, ``[1, pixSize.z / pixSize.x]``;
%     ZX slices are ``[z, x]`` (rows = Z, columns = X, see :meth:`core.MibImage.getData`),
%     so X stays horizontal as in the other two views
%
% Syntax:
%   .. code-block:: matlab
%
%      [stretchX, stretchY] = obj.getDisplayStretch()
%      [stretchX, stretchY] = obj.getDisplayStretch(orient)
%
% Input Arguments:
%   - **orient** - *(optional)* [numeric] orientation ``1`` (ZX), ``2`` (ZY) or
%     ``3`` (YX); ``[]`` or missing uses the current ``obj.orientation``
%
% Output Arguments:
%   - **stretchX** - [double] axes units per data pixel along the horizontal axis
%   - **stretchY** - [double] axes units per data pixel along the vertical axis
%
% Usage:
%   **Example 1** - stretch of the currently shown slice:
%
%   .. code-block:: matlab
%
%      [stretchX, stretchY] = obj.mibModel.I{obj.mibModel.id}.getDisplayStretch();
%

% Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
% Part of Microscopy Image Browser, http://mib.helsinki.fi
% License: GNU General Public License v3, https://www.gnu.org/licenses/gpl-3.0.en.html

if nargin < 2 || isempty(orient); orient = obj.orientation; end
pixSize = obj.image.pixSize;
switch orient
    case 1      % zx: Z vertical
        stretchX = 1;
        stretchY = pixSize.z / pixSize.x;
    case 2      % zy: Z horizontal
        stretchX = pixSize.z / pixSize.y;
        stretchY = 1;
    otherwise   % yx
        stretchX = pixSize.x / pixSize.y;
        stretchY = 1;
end
end
