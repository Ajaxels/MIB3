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


% obj.mibController

%obj.mibController.mibModel.clearSelection();
obj.mibController.mibModel.clearLayer('selection');

end