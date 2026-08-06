function returnBatchOpt(obj, BatchOptOut)
% RETURNBATCHOPT - Send BatchOpt to mibBatchController.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.returnBatchOpt()
%      obj.returnBatchOpt(BatchOptOut)
%
% Input Arguments:
%   - **BatchOptOut** *(optional)* - [struct] BatchOpt to send; defaults to ``obj.BatchOpt``
%

if nargin < 2; BatchOptOut = obj.BatchOpt; end
eventdata = core.ToggleEventData(BatchOptOut);
notify(obj.mibModel, 'SyncBatch', eventdata);

end
