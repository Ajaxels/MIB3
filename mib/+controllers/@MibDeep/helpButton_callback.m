function helpButton_callback(obj)
% HELPBUTTON_CALLBACK - show Help sections.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.helpButton_callback()

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDeep.helpButton_callback: triggered\n');
end
    helpFilPath = fullfile(utils.getDocsPath(), 'user-interface', 'deepmib');
    switch obj.view.handles.Mode.SelectedTab.Title
        case 'Directories and Preprocessing'
            targetFilename = 'deepmib-dirs.html';
        case 'Train'
            targetFilename = 'deepmib-train.html';
        case 'Predict'
            targetFilename = 'deepmib-predict.html';
        case 'Options'
            targetFilename = 'deepmib-options.html';
    end

    if isfile(fullfile(helpFilPath, targetFilename))
        web(fullfile(helpFilPath, targetFilename), '-browser');
    else
        web(sprintf('http://mib.helsinki.fi/help/main3/user-interface/deepmib/%s', targetFilename), '-browser');
    end
end

