function transpose(obj, new_orient)
% function transpose(obj, new_orient)
% Change orientation of the image to the YX, XZ, or YZ plane.
% Converted from MIB2 @mibImage/transpose.m
%
% @note This function updates only the slices and orientation fields; it does
%       NOT rearrange the underlying image data in memory.
%
% Parameters:
% new_orient: desired orientation:
%   @li @b 1 -> XZ plane (xz)
%   @li @b 2 -> YZ plane (yz)
%   @li @b 3 -> YX plane (yx, default view)
%
% Return values:
%   none
%
% Example:
%   obj.transpose(1);   % switch to XZ plane
%   obj.transpose(2);   % switch to YZ plane
%   obj.transpose(3);   % switch to YX plane
%   obj.mibModel.I{obj.mibModel.id}.transpose(3);   % switch to YX plane, call from MibController


% Save the current slice index for the orientation being left, so we can
% return to the same position when switching back.
if obj.orientation == 1         % leaving XZ: remember y-row
    obj.current_yxz(1) = obj.slices{1}(1);
elseif obj.orientation == 2     % leaving YZ: remember x-column
    obj.current_yxz(2) = obj.slices{2}(1);
elseif obj.orientation == 3     % leaving YX: remember z-depth
    obj.current_yxz(3) = obj.slices{3}(1);
end

switch new_orient
    case 3  % YX: show full height × width at a single z-slice
        obj.orientation = 3;
        obj.slices{1} = [1, obj.dim_yxzct(1)];                             % full height
        obj.slices{2} = [1, obj.dim_yxzct(2)];                             % full width
        obj.slices{3} = [obj.current_yxz(3), obj.current_yxz(3)];          % single z
    case 1  % XZ: show single y-row × full width × full depth
        obj.orientation = 1;
        obj.slices{1} = [obj.current_yxz(1), obj.current_yxz(1)];          % single y
        obj.slices{2} = [1, obj.dim_yxzct(2)];                             % full width
        obj.slices{3} = [1, obj.dim_yxzct(3)];                             % full depth
    case 2  % YZ: show full height × single x-column × full depth
        obj.orientation = 2;
        obj.slices{1} = [1, obj.dim_yxzct(1)];                             % full height
        obj.slices{2} = [obj.current_yxz(2), obj.current_yxz(2)];          % single x
        obj.slices{3} = [1, obj.dim_yxzct(3)];                             % full depth
end
end
