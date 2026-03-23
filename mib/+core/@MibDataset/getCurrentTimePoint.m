function timePnt = getCurrentTimePoint(obj)
% function timePnt = getCurrentTimePoint(obj)
% Get time point of the currently shown image.
%
% Parameters:
%
% Return values:
% timePnt: index of the currently shown slice

%| 
% @b Examples:
% @code timePnt = obj.mibModel.I{obj.mibModel.id}.getCurrentTimePoint();      // get the time point  @endcode

% Updates
% 

timePnt = obj.slices{5}(1);
end