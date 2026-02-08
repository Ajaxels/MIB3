function slice_no = getCurrentSliceNumber(obj)
% function slice_no = getCurrentSliceNumber(obj)
% Get slice number of the currently shown image
%
% Parameters:
%
% Return values:
% slice_no: index of the currently shown slice

%| 
% @b Examples:
% @code slice_no = obj.mibModel.I{obj.mibModel.id}.getCurrentSliceNumber();      // Call from MibController @endcode

% Updates
% 

slice_no = obj.slices{obj.orientation}(1);
end