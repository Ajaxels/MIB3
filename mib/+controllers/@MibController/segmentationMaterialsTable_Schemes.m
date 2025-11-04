function segmentationMaterialsTable_Schemes(obj, menuEntry, selectedData)
% function segmentationMaterialsTable_Schemes(obj, menuEntry, selectedData)
% callbacks for the context menu of the segmentation table widget -> Color
% schemes entry
% (obj.handles.panels.segmentation.handles.materialsTableContextScheme)
%
% Parameters:
% menuEntry: handle to the pressed context menu entry, 'matlab.ui.container.Menu' class
% selectedData: handle to the pressed
% 'matlab.ui.eventdata.MenuSelectedData' class, it can be used to find the
% button that has the context menu (selectedData.ContextObject)
%
% Available menu options available from 'menuEntry.Tag':
% materialsTableContextSchemeDef -> Default, 6 colors
% materialsTableContextSchemeDist -> Distinct colors, 20 colors
% materialsTableContextSchemeRandom -> Random colors
% materialsTableContextSchemeSwap -> Swap colors
% materialsTableContextSchemeQMC ->  Qualitative (Monte Carlo -> Half Baked), 3-12 colors
% materialsTableContextSchemeDDD -> Diverging (Deep Bronze->Deep Teal), 3-11 colors
% materialsTableContextSchemeDRK -> Diverging (Ripe Plum->Kaitoke Green), 3-11 colors
% materialsTableContextSchemeDBG -> Diverging (Bordeaux->Green Vogue), 3-11 colors
% materialsTableContextSchemeDCB -> Diverging (Carmine->Bay of Many), 3-11 colors
% materialsTableContextSchemeSKG -> Sequential (Kaitoke Green), 3-9 colors
% materialsTableContextSchemeSCB -> Sequential (Catalina Blue), 3-9 colors
% materialsTableContextSchemeSM -> Sequential (Maroon), 3-9 colors
% materialsTableContextSchemeSAB -> Sequential (Astronaut Blue), 3-9 color
% materialsTableContextSchemeSD -> Sequential (Downriver), 3-9 colors
% materialsTableContextSchemeMJ -> 'Matlab Jet
% materialsTableContextSchemeMH -> Matlab HSV
% materialsTableContextSchemeSetDef -> Make current scheme as default
% materialsTableContextSchemeUpdate -> Update colors from default

arguments (Input)
    obj controllers.MibController
    menuEntry matlab.ui.container.Menu
    selectedData matlab.ui.eventdata.MenuSelectedData
end

switch menuEntry.Tag
    case 'materialsTableContextSchemeDef'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContextScheme -> %s\n', menuEntry.Tag);
    case 'materialsTableContextSchemeDist'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContextScheme -> %s\n', menuEntry.Tag);
    case 'materialsTableContextSchemeRandom'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContextScheme -> %s\n', menuEntry.Tag);
    case 'materialsTableContextSchemeSwap'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContextScheme -> %s\n', menuEntry.Tag);
    case 'materialsTableContextSchemeQMC'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContextScheme -> %s\n', menuEntry.Tag);
    case 'materialsTableContextSchemeDDD'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContextScheme -> %s\n', menuEntry.Tag);
    case 'materialsTableContextSchemeDRK'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContextScheme -> %s\n', menuEntry.Tag);
    case 'materialsTableContextSchemeDBG'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContextScheme -> %s\n', menuEntry.Tag);
    case 'materialsTableContextSchemeDCB'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContextScheme -> %s\n', menuEntry.Tag);
    case 'materialsTableContextSchemeSKG'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContextScheme -> %s\n', menuEntry.Tag);
    case 'materialsTableContextSchemeSCB'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContextScheme -> %s\n', menuEntry.Tag);
    case 'materialsTableContextSchemeSM'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContextScheme -> %s\n', menuEntry.Tag);
    case 'materialsTableContextSchemeSAB'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContextScheme -> %s\n', menuEntry.Tag);
    case 'materialsTableContextSchemeSD'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContextScheme -> %s\n', menuEntry.Tag);
    case 'materialsTableContextSchemeMJ'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContextScheme -> %s\n', menuEntry.Tag);
    case 'materialsTableContextSchemeMH'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContextScheme -> %s\n', menuEntry.Tag);
    case 'materialsTableContextSchemeSetDef'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContextScheme -> %s\n', menuEntry.Tag);
    case 'materialsTableContextSchemeUpdate'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContextScheme -> %s\n', menuEntry.Tag);
end
