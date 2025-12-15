% mibUpdateFontSize(obj.mibController.mibView.gui, obj.preferences.System.Font);
% utils.fontSizeUpdate(obj.view.gui, obj.mibModel.preferences.System.Font);

% obj.mibModel.mibPython -> obj.mibModel.pythonEnv

% prefdir = getPrefDir(); -> prefdir = utils.getPrefDir();

% errordlg(sprintf('There is a problem with saving preferences to\n%s\n%s', fullfile(prefdir, 'mib.mat'), err.identifier), 'Error');
% see -> utils.dlgs.showErrorDialog
% errorText = sprintf('!!! Error !!!\n\nSomething went wrong!');
% suffix = 'some text at the bottom';
% utils.dlgs.showErrorDialog([], errorText, 'Error', [], suffix);

% BatchOpt = updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn) -> 
%   BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn)

% obj.modelType ->
%   obj.mibModel.I{obj.mibModel.id}.labels.maxMaterials

%obj.setData2D('selection', {slice}, layer_id, orientation, 0, getDataOptions);
%  obj.I{obj.id}.setData2D(slice, 'selection', layer_id, orientation, NaN, getDataOptions);

% obj.mibModel.I{obj.mibModel.Id}.clearSelection(NaN, NaN, NaN, t);
%   ->
% obj.mibModel.I{obj.mibModel.Id}.clearSelection(NaN, NaN, NaN, t);
%   -> obj.mibModel.I{obj.mibModel.id}.clearLayer([], [], [], t);


% wb = waitbar(0,'Clearing the Selection layer for a whole Z-stack...', 'WindowStyle', 'modal'); 
% wb = uiprogressdlg(obj.mibGUI, 'Value', 0, ...
%    'Message', sprintf('Clearing the Selection layer for a whole Z-stack\nPlease wait...'), ...
%    'Title', 'Clear selection', 'Cancelable', 'on'); 
% wb = uiprogressdlg(obj.mibGUI, 'Value', 0, ...
%    'Message', sprintf('\nPlease wait...'), ...
%    'Title', '', 'Indeterminate', 'on'); 
