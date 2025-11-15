function segmentationColorWheel_Schemes(obj, menuEntry, selectedData)
% function segmentationColorWheel_Schemes(obj, menuEntry, selectedData)
% callbacks for the context menu of the segmentation table widget -> Color
% schemes entry
% (obj.view.handles.panels.segmentation.handles.colorWheelContextScheme)
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

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibController.segmentationColorWheel_Schemes: context menu for "obj.view.handles.panels.segmentation.handles.colorWheel" -> selected "%s (%s)"\n', menuEntry.Text, menuEntry.Tag);
end


switch menuEntry.Tag
    case 'colorWheelContextSchemeDef'
        
    case 'colorWheelContextSchemeDist'
        
    case 'colorWheelContextSchemeRandom'
        
    case 'colorWheelContextSchemeSwap'
        
    case 'colorWheelContextSchemeQMC'
        
    case 'colorWheelContextSchemeDDD'
        
    case 'colorWheelContextSchemeDRK'
        
    case 'colorWheelContextSchemeDBG'
        
    case 'colorWheelContextSchemeDCB'
        
    case 'colorWheelContextSchemeSKG'
        
    case 'colorWheelContextSchemeSCB'
        
    case 'colorWheelContextSchemeSM'
        
    case 'colorWheelContextSchemeSAB'
        
    case 'colorWheelContextSchemeSD'
        
    case 'colorWheelContextSchemeMJ'
        
    case 'colorWheelContextSchemeMH'
        
    case 'colorWheelContextSchemeSetDef'
        
    case 'colorWheelContextSchemeUpdate'
        
end
