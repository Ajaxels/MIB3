function wipeTempDirBtn_Callback(obj)
% WIPETEMPDIRBTN_CALLBACK - Delete the temporary feature directory after user confirmation.

arguments (Input)
    obj controllers.MembranePixClassifier
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MembranePixClassifier.wipeTempDirBtn_Callback: triggered\n');
end

if exist(obj.dirOut, 'dir') == 0; return; end

button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
    sprintf('!!! Warning !!!\n\nThe whole directory:\n\n%s\n\nwill be deleted!!!\n\nAre you sure?', obj.dirOut), ...
    'Delete directory?', 'Delete', 'Cancel', 'Cancel');
if strcmp(button, 'Cancel')
    obj.updateLoglist('Wipe Temp directory: Canceled!');
    return;
end
rmdir(obj.dirOut, 's');
obj.updateLoglist('Temp directory was deleted');

end
