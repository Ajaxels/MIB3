function updateWidgets(obj)
% UPDATEWIDGETS - Refresh all GUI widgets from model state.

arguments (Input)
    obj controllers.MembranePixClassifier
end

id = obj.mibModel.getActiveId();
list = obj.mibModel.I{id}.labels.materialNames;

if obj.mibModel.I{id}.modelExist == 0 || numel(list) < 2
    utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
        sprintf(['!!! Error !!!\n\nA model with at least two materials is needed to proceed further!\n\n' ...
        'Please create a new model with two materials - one for the objects and another one ' ...
        'for the background. After that try again!\n\nPlease also refer to the Help section for details']), ...
        'Missing the model');
    obj.view.handles.trainClassifierBtn.Enable = 'off';
    obj.view.handles.predictSlice.Enable = 'off';
    list = {'Add 2 Materials to the model!'};
else
    obj.view.handles.trainClassifierBtn.Enable = 'on';
    obj.view.handles.predictSlice.Enable = 'on';
end

% populate material dropdowns
obj.view.handles.ObjectMaterial.Items     = list;
obj.view.handles.BackgroundMaterial.Items = list;
obj.BatchOpt.ObjectMaterial{2}     = list;
obj.BatchOpt.BackgroundMaterial{2} = list;

if ~ismember(obj.BatchOpt.ObjectMaterial{1}, list)
    obj.BatchOpt.ObjectMaterial{1} = list{1};
end
if ~ismember(obj.BatchOpt.BackgroundMaterial{1}, list)
    obj.BatchOpt.BackgroundMaterial{1} = list{min(2, numel(list))};
end
obj.view.handles.ObjectMaterial.Value     = obj.BatchOpt.ObjectMaterial{1};
obj.view.handles.BackgroundMaterial.Value = obj.BatchOpt.BackgroundMaterial{1};

% path fields
obj.view.handles.TempDir.Value           = obj.dirOut;
obj.view.handles.ClassifierFilename.Value = obj.classFilename;

end
