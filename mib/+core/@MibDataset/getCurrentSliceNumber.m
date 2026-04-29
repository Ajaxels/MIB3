function slice_no = getCurrentSliceNumber(obj)
% GETCURRENTSLICENUMBER - Get slice number of the currently shown image.
%
% Syntax:
%   function slice_no = getCurrentSliceNumber(obj)
%
% Input Arguments:
%
% Output Arguments:
%   - **slice_no** — index of the currently shown slice
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     slice_no = obj.mibModel.I{obj.mibModel.id}.getCurrentSliceNumber();% Call from MibController
%

% Updates
% 

slice_no = obj.slices{obj.orientation}(1);
end
