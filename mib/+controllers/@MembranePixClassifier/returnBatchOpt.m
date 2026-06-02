function returnBatchOpt(obj, BatchOptOut)
% RETURNBATCHOPT - Fire SyncBatch event with current (or supplied) BatchOpt.

arguments (Input)
    obj controllers.MembranePixClassifier
    BatchOptOut struct = struct()
end

if isempty(fieldnames(BatchOptOut)); BatchOptOut = obj.BatchOpt; end
eventdata = core.ToggleEventData(BatchOptOut);
notify(obj.mibModel, 'SyncBatch', eventdata);

end
