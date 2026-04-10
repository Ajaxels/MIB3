function updateActionLog(obj, logEntry)
% function updateActionLog(obj, logEntry)
% Append a new timestamped entry to the action log of the MibImage instance.
%
% The current date/time stamp is prepended automatically in the format
% 'MIB(yymmddHHMM): <logEntry>'. When logEntry is omitted or empty
% the call is a no-op.
%
% Parameters:
% logEntry: [@em optional] char or string, description of the processing step
%   to record, e.g. 'ImFilter: Median, HSize:3 3, Orient:4'.
%   When omitted or empty, no entry is added.
%
% Return values:
% (none) — modifies obj.actionLog in place.
%

%|
% @b Examples:
% @code
% obj.mibModel.I{obj.mibModel.id}.image.updateActionLog('ImFilter: Median, HSize:3 3, Orient:4');
% @endcode

% Updates
% 11.04.2026 - created

if nargin < 2 || isempty(logEntry); return; end
obj.actionLog{end+1} = sprintf('MIB(%s): %s', datestr(now, 'yymmddHHMM'), char(logEntry));
end
