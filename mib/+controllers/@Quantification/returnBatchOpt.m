function returnBatchOpt(obj, BatchOptOut)
% RETURNBATCHOPT - Publish BatchOpt to the macro recorder via 'SyncBatch' event.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.returnBatchOpt()
%       obj.returnBatchOpt(BatchOptOut)
%
% Fires a SyncBatch event carrying the current (or provided) BatchOpt
% so that the MIB batch controller can record this action.
%
% Input Arguments:
%   - **BatchOptOut** - *(optional)* struct with Batch Options to publish;
%     defaults to obj.BatchOpt
%
% Usage:
%   Example 1::
%
%     obj.returnBatchOpt();                  // publish current BatchOpt
%
%   Example 2::
%
%     obj.returnBatchOpt(myCustomBatchOpt);  // publish custom BatchOpt
%

% Updates
%

if nargin < 2; BatchOptOut = obj.BatchOpt; end

eventdata = core.ToggleEventData(BatchOptOut);
notify(obj.mibModel, 'SyncBatch', eventdata);
end
