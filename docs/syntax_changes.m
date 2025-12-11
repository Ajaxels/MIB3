% mibUpdateFontSize(obj.mibController.mibView.gui, obj.preferences.System.Font);
% utils.fontSizeUpdate(obj.view.gui, obj.mibModel.preferences.System.Font);

% obj.mibModel.mibPython -> obj.mibModel.pythonEnv

% prefdir = getPrefDir(); -> prefdir = utils.getPrefDir();

% errordlg(sprintf('There is a problem with saving preferences to\n%s\n%s', fullfile(prefdir, 'mib.mat'), err.identifier), 'Error');
% see -> utils.dlgs.showErrorDialog
% errorText = sprintf('!!! Error !!!\n\nSomething went wrong!');
% suffix = 'some text at the bottom';
% utils.dlgs.showErrorDialog([], errorText, 'Error', [], suffix);

% BatchOpt = updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn) -> BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn)

obj.mibModel.I{obj.mibModel.id}.labels.maxMaterials
