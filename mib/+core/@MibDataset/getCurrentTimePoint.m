function timePnt = getCurrentTimePoint(obj)
% GETCURRENTTIMEPOINT - Get time point of the currently shown image.
%
% Syntax:
%   function timePnt = getCurrentTimePoint(obj)
%
% Input Arguments:
%
% Output Arguments:
%   - **timePnt** — index of the currently shown slice
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     timePnt = obj.mibModel.I{obj.mibModel.id}.getCurrentTimePoint();% get the time point
%

% Updates
% 

timePnt = obj.slices{5}(1);
end
