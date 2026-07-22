function predictSlice_Callback(obj)
% PREDICTSLICE_CALLBACK - Run prediction on the currently displayed slice.

arguments (Input)
    obj controllers.MembranePixClassifier
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MembranePixClassifier.predictSlice_Callback: triggered\n');
end

obj.view.handles.predictSlice.BackgroundColor = [1 0 0];
id = obj.mibModel.getActiveId();
sliceNo = obj.mibModel.I{id}.slices{3}(1);
obj.predictDataset(sliceNo);
obj.view.handles.predictSlice.BackgroundColor = [0 1 0];

end
