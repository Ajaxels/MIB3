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


obj.mibModel.loadImages('Combine datasets');

%obj.mibController.mibModel.clearSelection();
%obj.mibController.mibModel.clearLayer('selection');
%obj.mibController.mibModel.clearLayer('selection', '2D, Slice');
%obj.mibController.mibModel.I{obj.mibController.mibModel.id}.clearLayer('selection');
end