function homeDevTest_Callback(obj, hWidget, hData)
% function homeDevTest_Callback(obj, hWidget, hData)
% Reserved for MIB developmental purposes

arguments (Input)
    obj controllers.MibRibbon
    hWidget matlab.ui.internal.toolstrip.base.Action
    hData matlab.ui.internal.toolstrip.base.ToolstripEventData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRibbon.homeDevTest_Callback: pressed\n');
end

errorOpts.mibPath = obj.mibModel.mibPath;
errorOpts.WindowWidth  = 500;
errorOpts.WindowHeight = 330;
errorOpts.PrefixHeight = 'fit';
errorOpts.ErrorHeight  = '1x';
errorOpts.SuffixHeight = 'fit';
utils.dlgs.showErrorDialog(obj.view.gui, 'Error text', 'Import Error', ...
    'Failed to load file:', 'Please contact support', errorOpts);

%obj.mibController.mibModel.clearSelection();
%obj.mibController.mibModel.clearLayer('selection');
%obj.mibController.mibModel.clearLayer('selection', '2D, Slice');
%obj.mibController.mibModel.I{obj.mibController.mibModel.id}.clearLayer('selection');
end