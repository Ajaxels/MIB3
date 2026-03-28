function thresholdSlider_ContextMenu(obj, menuEntry, selectedData)
% function thresholdSlider_ContextMenu(obj, menuEntry, selectedData)
% Callbacks for the context menu of the threshold Low/High sliders
% (obj.handles.thresholdLow, obj.handles.thresholdHigh)
%
% Parameters:
% menuEntry: handle to the pressed context menu entry, 'matlab.ui.container.Menu' class
% selectedData: handle to 'matlab.ui.eventdata.MenuSelectedData' class;
%   selectedData.ContextObject identifies the slider that was right-clicked
%
% Available menu options from 'menuEntry.Tag':
% @li 'thresholdSliderContextDefault' - reset slider step to default (1)
% @li 'thresholdSliderContextSetStep' - set custom slider step via dialog
%
%|
% @b Examples:
% @code obj.thresholdSlider_ContextMenu(menuEntry, selectedData);  // called from context menu @endcode

arguments (Input)
    obj controllers.MibSegmentation
    menuEntry matlab.ui.container.Menu
    selectedData matlab.ui.eventdata.MenuSelectedData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSegmentation.thresholdSlider_ContextMenu: selected menu entry (menuEntry.Tag): %s\n', menuEntry.Tag);
end

switch menuEntry.Tag
    case 'thresholdSliderContextDefault'
        obj.thresholdSliderStep = 1;
    case 'thresholdSliderContextSetStep'
        prompt = {'Enter the step for the threshold sliders:'};
        defAns = struct('Value', obj.thresholdSliderStep, 'Limits', [1 Inf], 'Step', 1, ...
                'Round', false);
        dlgOpt.WindowHeight = 100;
        dlgOpt.Type = 'spinner';
        newStep = utils.dlgs.inputSingleDlg(obj.view.gui, prompt, defAns, 'Set step...', dlgOpt);
        if isempty(newStep); return; end
        
        obj.thresholdSliderStep = newStep;
end

end
