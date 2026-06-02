function updateBatchOptFromGUI(obj, hObject)
% UPDATEBATCHOPTFROMGUI - Sync BatchOpt from a changed widget value.

arguments (Input)
    obj     controllers.MembranePixClassifier
    hObject
end

obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, hObject);

end
