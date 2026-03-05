function sliceNumberSlider_ContextMenu(obj, menuEntry, selectedData)
% function sliceNumberSlider_ContextMenu(obj, menuEntry, selectedData)
% callbacks for the context menu of change of slices slider
% obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.handles.sliceNumberSlider
% or
% obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.handles.frameNumberSlider

% Parameters:
% menuEntry: handle to the pressed context menu entry, 'matlab.ui.container.Menu' class
% selectedData: handle to the pressed
% 'matlab.ui.eventdata.MenuSelectedData' class, it can be used to find the
% button that has the context menu (selectedData.ContextObject)
%
% Available menu options available from 'menuEntry.Tag':
% sliceNumberSliderContextDefault - reset Z slider settings to default values
% sliceNumberSliderContextSetStep - update Z slider settings with new values
% frameNumberSliderContextDefault - reset T slider settings to default values
% frameNumberSliderContextSetStep - update T slider settings with new values


if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibImageDocument.sliceNumberSlider_ContextMenu: selected menu entry (menuEntry.Tag): %s\n', menuEntry.Tag);
end

if ismember(menuEntry.Tag, {'sliceNumberSliderContextDefault', 'sliceNumberSliderContextSetStep'})
    sliderStep = 'sliderZStep';
    sliderShiftStep = 'sliderZShiftStep';
else
    sliderStep = 'sliderTStep';
    sliderShiftStep = 'sliderTShiftStep';
end


switch menuEntry.Tag
    case {'sliceNumberSliderContextDefault', 'frameNumberSliderContextDefault'}  % set brightness on the screen to be the same as in the image
        obj.(sliderStep) = 1;         % default slider step
        obj.(sliderShiftStep) = 10;   % default slider step with shift pressed
    case {'sliceNumberSliderContextSetStep', 'frameNumberSliderContextSetStep'}
        prompt = {'Enter step for use with arrows or Q/W buttons:', 'Enter step for use with Shift+arrows or Shift+Q/W buttons:'};
        defAns = {obj.(sliderStep), obj.(sliderShiftStep)};
        mibInputMultiDlgOpt.PromptLines = [1, 1];
        mibInputMultiDlgOpt.WindowHeight = 120;
        mibInputMultiDlgOpt.ParentFigure = obj.view.gui;
        mibInputMultiDlgOpt.mibPath  = .obj.mibModel.mibPath;
        answer = utils.dlgs.inputUniversalDlg(obj.view.gui, prompt, defAns, 'Set step...', mibInputMultiDlgOpt);
        if isempty(answer); return; end

        obj.(sliderStep) = round(answer{1});     % parameters for slider movement
        obj.(sliderShiftStep) = round(answer{2});
end

end