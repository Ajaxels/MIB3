function returnBatchOpt(obj, BatchOptOut)
% function returnBatchOpt(obj, BatchOptOut)
% return structure with Batch Options and possible configurations
% via the notify 'SyncBatch' event
% Parameters:
% BatchOptOut: a local structure with Batch Options generated
% during Continue callback. It may contain more fields than
% obj.BatchOpt structure
%
if nargin < 2; BatchOptOut = obj.BatchOpt; end

if isfield(BatchOptOut, 'id'); BatchOptOut = rmfield(BatchOptOut, 'id'); end  % remove id field
% trigger syncBatch event to send BatchOptOut to mibBatchController
eventdata = core.ToggleEventData(BatchOptOut);
notify(obj.mibModel, 'SyncBatch', eventdata);
end

