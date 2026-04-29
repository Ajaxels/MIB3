function materialsTable_render(obj, menuEntry, selectedData)
% MATERIALSTABLE_RENDER - callbacks for the context menu of the Segmentation table widget Render...  entry (obj.view.handles.panels.segmentation.handles.materialsTableContextRen).
%
% Syntax:
%   function materialsTable_render(obj, menuEntry, selectedData)
%
% Input Arguments:
%   - **menuEntry** — handle to the pressed context menu entry, 'matlab.ui.container.Menu' class
%   - **selectedData** — handle to the pressed
%     'matlab.ui.eventdata.MenuSelectedData' class, it can be used to find the
%     button that has the context menu (selectedData.ContextObject)
%
%   Available menu options available from 'menuEntry.Tag':
%   materialsTableContextRenMIB render the material in MIB using volume rendering
%   materialsTableContextRenMat render the material using MATLAB isosurfaces
%   materialsTableContextRenFiji render the material using Fiji volume rendering
%

arguments (Input)
    obj controllers.MibSegmentation
    menuEntry matlab.ui.container.Menu
    selectedData matlab.ui.eventdata.MenuSelectedData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Mibegmentation.materialsTable_render: -> "%s" (%s)\n', menuEntry.Text, menuEntry.Tag);
end

switch menuEntry.Tag
    case 'materialsTableContextRenMIB'

    case 'materialsTableContextRenMat'

    case 'materialsTableContextRenFiji'

end
end
