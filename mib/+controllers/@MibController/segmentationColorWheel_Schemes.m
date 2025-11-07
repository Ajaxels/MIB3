function segmentationColorWheel_Schemes(obj, menuEntry, selectedData)
% function segmentationColorWheel_Schemes(obj, menuEntry, selectedData)
% callbacks for the context menu of the segmentation table widget -> Color
% schemes entry
% (obj.handles.panels.segmentation.handles.colorWheelContextScheme)
%
% Parameters:
% menuEntry: handle to the pressed context menu entry, 'matlab.ui.container.Menu' class
% selectedData: handle to the pressed
% 'matlab.ui.eventdata.MenuSelectedData' class, it can be used to find the
% button that has the context menu (selectedData.ContextObject)
%
% Available menu options available from 'menuEntry.Tag':
% colorWheelContextSchemeDef -> Default, 6 colors
% colorWheelContextSchemeDist -> Distinct colors, 20 colors
% colorWheelContextSchemeRandom -> Random colors
% colorWheelContextSchemeSwap -> Swap colors
% colorWheelContextSchemeQMC ->  Qualitative (Monte Carlo -> Half Baked), 3-12 colors
% colorWheelContextSchemeDDD -> Diverging (Deep Bronze->Deep Teal), 3-11 colors
% colorWheelContextSchemeDRK -> Diverging (Ripe Plum->Kaitoke Green), 3-11 colors
% colorWheelContextSchemeDBG -> Diverging (Bordeaux->Green Vogue), 3-11 colors
% colorWheelContextSchemeDCB -> Diverging (Carmine->Bay of Many), 3-11 colors
% colorWheelContextSchemeSKG -> Sequential (Kaitoke Green), 3-9 colors
% colorWheelContextSchemeSCB -> Sequential (Catalina Blue), 3-9 colors
% colorWheelContextSchemeSM -> Sequential (Maroon), 3-9 colors
% colorWheelContextSchemeSAB -> Sequential (Astronaut Blue), 3-9 color
% colorWheelContextSchemeSD -> Sequential (Downriver), 3-9 colors
% colorWheelContextSchemeMJ -> 'Matlab Jet
% colorWheelContextSchemeMH -> Matlab HSV
% colorWheelContextSchemeSetDef -> Make current scheme as default
% colorWheelContextSchemeUpdate -> Update colors from default

arguments (Input)
    obj controllers.MibController
    menuEntry matlab.ui.container.Menu
    selectedData matlab.ui.eventdata.MenuSelectedData
end

switch menuEntry.Tag
    case 'colorWheelContextSchemeDef'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.colorWheelContextScheme -> %s\n', menuEntry.Tag);
    case 'colorWheelContextSchemeDist'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.colorWheelContextScheme -> %s\n', menuEntry.Tag);
    case 'colorWheelContextSchemeRandom'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.colorWheelContextScheme -> %s\n', menuEntry.Tag);
    case 'colorWheelContextSchemeSwap'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.colorWheelContextScheme -> %s\n', menuEntry.Tag);
    case 'colorWheelContextSchemeQMC'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.colorWheelContextScheme -> %s\n', menuEntry.Tag);
    case 'colorWheelContextSchemeDDD'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.colorWheelContextScheme -> %s\n', menuEntry.Tag);
    case 'colorWheelContextSchemeDRK'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.colorWheelContextScheme -> %s\n', menuEntry.Tag);
    case 'colorWheelContextSchemeDBG'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.colorWheelContextScheme -> %s\n', menuEntry.Tag);
    case 'colorWheelContextSchemeDCB'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.colorWheelContextScheme -> %s\n', menuEntry.Tag);
    case 'colorWheelContextSchemeSKG'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.colorWheelContextScheme -> %s\n', menuEntry.Tag);
    case 'colorWheelContextSchemeSCB'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.colorWheelContextScheme -> %s\n', menuEntry.Tag);
    case 'colorWheelContextSchemeSM'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.colorWheelContextScheme -> %s\n', menuEntry.Tag);
    case 'colorWheelContextSchemeSAB'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.colorWheelContextScheme -> %s\n', menuEntry.Tag);
    case 'colorWheelContextSchemeSD'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.colorWheelContextScheme -> %s\n', menuEntry.Tag);
    case 'colorWheelContextSchemeMJ'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.colorWheelContextScheme -> %s\n', menuEntry.Tag);
    case 'colorWheelContextSchemeMH'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.colorWheelContextScheme -> %s\n', menuEntry.Tag);
    case 'colorWheelContextSchemeSetDef'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.colorWheelContextScheme -> %s\n', menuEntry.Tag);
    case 'colorWheelContextSchemeUpdate'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.colorWheelContextScheme -> %s\n', menuEntry.Tag);
end
