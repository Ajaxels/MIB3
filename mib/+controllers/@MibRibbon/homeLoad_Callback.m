function homeLoad_Callback(obj, hWidget, hData)
% HOMELOAD_CALLBACK - callback on press of the load button in the Home ribbon.
%
% Syntax:
%   function homeLoad_Callback(obj, hWidget, hData)
%
% Handles the following widget(s):
% - obj.handles.ribbonHome.loadFile
%
% Input Arguments:
%   - **hWidget** — handle to the pressed widget
%   - **hData** — handle to supporting EventData class
%

arguments (Input)
    obj controllers.MibRibbon
    hWidget matlab.ui.internal.toolstrip.base.Action
    hData matlab.ui.internal.toolstrip.base.ToolstripEventData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRibbon.homeLoad: Load dataset pressed\n');
end

end
