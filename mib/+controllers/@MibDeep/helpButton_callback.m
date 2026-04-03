function helpButton_callback(obj)
    % function helpButton_callback(obj)
    % show Help sections
    global mibPath;

    switch obj.view.handles.Mode.SelectedTab.Title
        case 'Directories and Preprocessing'
            web(fullfile(mibPath, 'techdoc', 'html', 'ug_gui_menu_tools_deeplearning_dirs.html'), '-helpbrowser');
        case 'Train'
            web(fullfile(mibPath, 'techdoc', 'html', 'ug_gui_menu_tools_deeplearning_train.html'), '-helpbrowser');
        case 'Predict'
            web(fullfile(mibPath, 'techdoc', 'html', 'ug_gui_menu_tools_deeplearning_predict.html'), '-helpbrowser');
        case 'Options'
            web(fullfile(mibPath, 'techdoc', 'html', 'ug_gui_menu_tools_deeplearning_options.html'), '-helpbrowser');
    end
end

