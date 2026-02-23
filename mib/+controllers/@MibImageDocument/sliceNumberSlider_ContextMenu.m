function sliceNumberSlider_ContextMenu(obj, menuEntry, selectedData)
% function sliceNumberSlider_ContextMenu(obj, menuEntry, selectedData)
% callbacks for the context menu of change of slices slider
% (obj.handles.panels.activeDataset.handles.buffer1) buttons

% Parameters:
% menuEntry: handle to the pressed context menu entry, 'matlab.ui.container.Menu' class
% selectedData: handle to the pressed
% 'matlab.ui.eventdata.MenuSelectedData' class, it can be used to find the
% button that has the context menu (selectedData.ContextObject)
%
% Available menu options available from 'menuEntry.Tag':
% sliceNumberSliderContextDefault - reset slider settings to default values
% sliceNumberSliderContextSetStep - update slider settings with new values

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibImageDocument.sliceNumberSlider_ContextMenu: selected menu entry (menuEntry.Tag): %s\n', menuEntry.Tag);
end

switch menuEntry.Tag
    case 'sliceNumberSliderContextDefault'  % set brightness on the screen to be the same as in the image
        obj.sliderStep = 1;         % default slider step
        obj.sliderShiftStep = 10;   % default slider step with shift pressed
    case 'sliceNumberSliderContextSetStep'
        prompt = {'Enter step for use with arrows or Q/W buttons:', 'Enter step for use with Shift+arrows or Shift+Q/W buttons:'};
        defAns = {obj.sliderStep, obj.sliderShiftStep};
        mibInputMultiDlgOpt.PromptLines = [1, 1];
        mibInputMultiDlgOpt.WindowHeight = 120;
        mibInputMultiDlgOpt.ParentFigure = obj.view.gui;
        answer = utils.dlgs.mibInputUniversalDlg(obj.mibModel.mibPath, prompt, defAns, 'Set step...', mibInputMultiDlgOpt);
        if isempty(answer); return; end

        obj.sliderStep = round(answer{1});     % parameters for slider movement
        obj.sliderShiftStep = round(answer{2});
end

end