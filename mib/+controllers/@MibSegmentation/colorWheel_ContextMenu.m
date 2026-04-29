function colorWheel_ContextMenu(obj, menuEntry, selectedData)
% COLORWHEEL_CONTEXTMENU - callbacks for the context menu of the color wheel button.
%
% Syntax:
%   function colorWheel_ContextMenu(obj, menuEntry, selectedData)
%
% (obj.view.handles.panels.segmentation.handles.colorWheel)
%
% Input Arguments:
%   - **menuEntry** — handle to the pressed context menu entry, 'matlab.ui.container.Menu' class
%   - **selectedData** — handle to the pressed
%     'matlab.ui.eventdata.MenuSelectedData' class, it can be used to find the
%     button that has the context menu (selectedData.ContextObject)
%
%   Available menu options available from 'menuEntry.Tag':
%   colorWheelContextSchemeDef Default, 6 colors
%   colorWheelContextSchemeDist Distinct colors, 20 colors
%   colorWheelContextSchemeRandom Random colors
%   colorWheelContextSchemeSwap Swap colors
%   colorWheelContextSchemeQMC Qualitative, Monte Carlo Half Baked, 3-12 colors
%   colorWheelContextSchemeDDD Diverging, Deep Bronze->Deep Teal, 3-11 colors
%   colorWheelContextSchemeDRK Diverging, Ripe Plum->Kaitoke Green, 3-11 colors
%   colorWheelContextSchemeDBG Diverging, Bordeaux->Green Vogue, 3-11 colors
%   colorWheelContextSchemeDCB Diverging, Carmine->Bay of Many, 3-11 colors
%   colorWheelContextSchemeSKG Sequential, Kaitoke Green, 3-9 colors
%   colorWheelContextSchemeSCB Sequential, Catalina Blue, 3-9 colors
%   colorWheelContextSchemeSM Sequential, Maroon, 3-9 colors
%   colorWheelContextSchemeSAB Sequential, Astronaut Blue, 3-9 colors
%   colorWheelContextSchemeSD Sequential, Downriver, 3-9 colors
%   colorWheelContextSchemeMJ MATLAB, Jet
%   colorWheelContextSchemeMH MATLAB, HSV
%   colorWheelContextSchemeSetDef Make current scheme as default
%   colorWheelContextSchemeUpdate Update colors from default
%

arguments (Input)
    obj controllers.MibSegmentation
    menuEntry matlab.ui.container.Menu
    selectedData matlab.ui.eventdata.MenuSelectedData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSegmentation.colorWheel_ContextMenu: context menu for "obj.view.handles.panels.segmentation.handles.colorWheel" -> selected "%s (%s)"\n', menuEntry.Text, menuEntry.Tag);
end

switch menuEntry.Tag
    case 'colorWheelContextSchemeDef'
        obj.mibModel.setDefaultColorPalette('Default, 6 colors');

    case 'colorWheelContextSchemeDist'
        obj.mibModel.setDefaultColorPalette('Distinct colors, 20 colors');

    case 'colorWheelContextSchemeRandom'
        obj.mibModel.setDefaultColorPalette('Random Colors');

    case 'colorWheelContextSchemeSwap'
        id = obj.mibModel.getActiveId();
        matCount = numel(obj.mibModel.I{id}.labels.materialNames);
        if matCount < 2
            utils.dlgs.showErrorDialog(obj.mibModel.mibGUI, ...
                'At least two materials are required to swap colors!', 'Swap colors');
            return;
        end
        % default indices from the currently selected materials
        mat1def = max(1, obj.mibModel.I{id}.selectedMaterial - 2);
        mat2def = max(1, obj.mibModel.I{id}.selectedAddToMaterial - 2);
        if mat1def == mat2def; mat2def = min(matCount, mat1def + 1); end

        prompts = {sprintf('Index of the first material [1-%d]:', matCount); ...
                   sprintf('Index of the second material [1-%d]:', matCount)};
        defAns = {num2str(mat1def); num2str(mat2def)};
        dlgOpt.PromptLines = [1, 1];
        answer = utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, '', prompts, defAns, 'Swap material colors', dlgOpt);
        if isempty(answer); return; end
        mat1 = str2double(answer{1});
        mat2 = str2double(answer{2});
        if isnan(mat1) || isnan(mat2) || mat1 < 1 || mat2 < 1 || mat1 > matCount || mat2 > matCount
            utils.dlgs.showErrorDialog(obj.mibModel.mibGUI, ...
                sprintf('Material indices must be integers between 1 and %d!', matCount), 'Swap colors');
            return;
        end
        if mat1 == mat2; return; end
        colors = obj.mibModel.I{id}.labels.materialColors;
        colors([mat1, mat2], :) = colors([mat2, mat1], :);
        obj.mibModel.I{id}.labels.materialColors = colors;
        eventdata = core.ToggleEventData({'ribbonModel', 'checkboxes'});
        notify(obj.mibModel, 'UpdateGuiWidgets', eventdata);
        notify(obj.mibModel, 'ShowImage');

    case 'colorWheelContextSchemeQMC'
        obj.mibModel.setDefaultColorPalette('Qualitative (Monte Carlo->Half Baked), 3-12 colors');

    case 'colorWheelContextSchemeDDD'
        obj.mibModel.setDefaultColorPalette('Diverging (Deep Bronze->Deep Teal), 3-11 colors');

    case 'colorWheelContextSchemeDRK'
        obj.mibModel.setDefaultColorPalette('Diverging (Ripe Plum->Kaitoke Green), 3-11 colors');

    case 'colorWheelContextSchemeDBG'
        obj.mibModel.setDefaultColorPalette('Diverging (Bordeaux->Green Vogue), 3-11 colors');

    case 'colorWheelContextSchemeDCB'
        obj.mibModel.setDefaultColorPalette('Diverging (Carmine->Bay of Many), 3-11 colors');

    case 'colorWheelContextSchemeSKG'
        obj.mibModel.setDefaultColorPalette('Sequential (Kaitoke Green), 3-9 colors');

    case 'colorWheelContextSchemeSCB'
        obj.mibModel.setDefaultColorPalette('Sequential (Catalina Blue), 3-9 colors');

    case 'colorWheelContextSchemeSM'
        obj.mibModel.setDefaultColorPalette('Sequential (Maroon), 3-9 colors');

    case 'colorWheelContextSchemeSAB'
        obj.mibModel.setDefaultColorPalette('Sequential (Astronaut Blue), 3-9 colors');

    case 'colorWheelContextSchemeSD'
        obj.mibModel.setDefaultColorPalette('Sequential (Downriver), 3-9 colors');

    case 'colorWheelContextSchemeMJ'
        obj.mibModel.setDefaultColorPalette('Matlab Jet');

    case 'colorWheelContextSchemeMH'
        obj.mibModel.setDefaultColorPalette('Matlab HSV');

    case 'colorWheelContextSchemeSetDef'
        obj.mibModel.setDefaultColorPalette('current2default');

    case 'colorWheelContextSchemeUpdate'
        obj.mibModel.setDefaultColorPalette('default2current');

end




end
