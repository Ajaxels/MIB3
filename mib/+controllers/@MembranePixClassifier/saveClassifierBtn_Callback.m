function saveClassifierBtn_Callback(obj)
% SAVECLASSIFIERBTN_CALLBACK - Save the trained classifier to a .mat file.

arguments (Input)
    obj controllers.MembranePixClassifier
end

obj.view.handles.logList.Items = {''};
obj.view.handles.logList.Value = '';
obj.updateLoglist('======= Saving classifier... =======');
outFile = obj.classFilename;

if exist(outFile, 'file') == 2
    obj.updateLoglist('The classifier already exist!');
    button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
        sprintf('!!! Warning !!!\n\nThe file already exist!\n\nOverwrite?'), ...
        'Overwrite existing forest?', 'Overwrite', 'Cancel', 'Cancel');
    if strcmp(button, 'Cancel')
        obj.updateLoglist('Save classifier: Canceled!');
        return;
    end
    obj.updateLoglist('Save classifier: Overwriting...');
end

if isempty(obj.forest)
    utils.dlgs.showErrorDialog(obj.view.gui, ...
        sprintf('!!! Error !!!\n\nThe classifier is not created yet!\nTry to train the classifer first!'), ...
        'Missing the classifier');
    obj.updateLoglist('Save classifier: The classifier is not created yet!');
    return;
end

forest = obj.forest; %#ok<PROP,NASGU>
save(outFile, 'forest', '-mat', '-v7.3');
obj.updateLoglist('The classifier was saved!');
obj.updateLoglist(outFile);

end
