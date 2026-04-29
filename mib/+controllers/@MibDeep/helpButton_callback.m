function helpButton_callback(obj)
% HELPBUTTON_CALLBACK - show Help sections.
%
% Syntax:
%   function helpButton_callback(obj)
%
    switch obj.view.handles.Mode.SelectedTab.Title
        case 'Directories and Preprocessing'
            web(fullfile(obj.mibModel.mibPath, 'techdoc', 'html', 'ug_gui_menu_tools_deeplearning_dirs.html'), '-helpbrowser');
        case 'Train'
            web(fullfile(obj.mibModel.mibPath, 'techdoc', 'html', 'ug_gui_menu_tools_deeplearning_train.html'), '-helpbrowser');
        case 'Predict'
            web(fullfile(obj.mibModel.mibPath, 'techdoc', 'html', 'ug_gui_menu_tools_deeplearning_predict.html'), '-helpbrowser');
        case 'Options'
            web(fullfile(obj.mibModel.mibPath, 'techdoc', 'html', 'ug_gui_menu_tools_deeplearning_options.html'), '-helpbrowser');
    end
end

