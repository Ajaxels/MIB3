function trainClassifierBtn_Callback(obj)
% TRAINCLASSIFIERBTN_CALLBACK - Dispatch to train or predict based on the current mode.

arguments (Input)
    obj controllers.MembranePixClassifier
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MembranePixClassifier.trainClassifierBtn_Callback: triggered\n');
end

obj.view.handles.trainClassifierBtn.BackgroundColor = [1.00,0.53,0.10];
switch obj.BatchOpt.Mode{1}
    case 'trainClassifier'; obj.trainClassifier();
    case 'predictDataset';  obj.predictDataset();
end
obj.view.handles.trainClassifierBtn.BackgroundColor = [0.15,0.90,0.18];

end
