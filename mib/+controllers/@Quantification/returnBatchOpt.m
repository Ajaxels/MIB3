function returnBatchOpt(obj, BatchOptOut)
% function returnBatchOpt(obj, BatchOptOut)
% Publish BatchOpt to the macro recorder via 'SyncBatch' event.
%
% Fires a SyncBatch event carrying the current (or provided) BatchOpt
% so that the MIB batch controller can record this action.
%
% Parameters:
% BatchOptOut: [@em optional] struct with Batch Options to publish;
%   defaults to obj.BatchOpt
%
%|
% @b Examples:
% @code obj.returnBatchOpt();                  // publish current BatchOpt @endcode
% @code obj.returnBatchOpt(myCustomBatchOpt);  // publish custom BatchOpt @endcode

% Updates
%

if nargin < 2; BatchOptOut = obj.BatchOpt; end

eventdata = core.ToggleEventData(BatchOptOut);
notify(obj.mibModel, 'SyncBatch', eventdata);
end
