function outputPath = saveLayout(obj, mode)
% function filename = saveLayout(obj, mode)
% Store the current layout of panels to disk
%
% Parameters:
% mode: char [optional, default='localDefault'] mode to store MIB layout
% @li 'localDefault' - default layout for local installation of MIB, saved to utils.getPrefDir, 'mibDefaultLayout.json'
% @li 'custom' - save layout to utils.getPrefDir using a custom name
% @li 'globalDefault' - update the default MIB layout configuration in MIB\assets\defaultLayout.json
%
% Return values:
% filename: char with the full path to the output file with the stored
% layout. The saved layout can be restored using utils.restoreLayout function.

%|
% @b Examples:
% @code
% filename = obj.storeLayout(obj); // call from MibController class
% @endcode
%
% Updates
%

arguments (Input)
    obj controllers.MibController
    mode (1,:) char = 'localDefault'
end

arguments (Output)
    outputPath (1,:) char
end

switch mode
    case 'localDefault'
        % get the output path
        selection = uiconfirm(obj.view.gui, ...
            sprintf('!!! Warning !!!\nSave the current layout of panels as default?\n\nAre you sure?'), ...
            'Overwrite default layout', ...
            'Options', ["Save", "Cancel"], ...
            'DefaultOption', 2, 'CancelOption', 2, ...
            'Icon', 'warning');
        if strcmp(selection, 'Cancel'); return; end
        
        prefdir = utils.getPrefDir(); % get the directory with MIB preferences
        outputPath = fullfile(prefdir, 'mibDefaultLayout.json');
    case 'custom'
        prefdir = utils.getPrefDir(); % get the directory with MIB preferences
        outputPath = fullfile(prefdir, 'mibCustomLayout.json');

        [filename, pathname, filterindex] = uiputfile(...
            {'*.json','Layout in JSON format'}, ...
            'Filename for layout', outputPath);
        if filename==0; return; end
        outputPath = fullfile(pathname, filename);
    case 'globalDefault'
        outputPath = fullfile(obj.mibPath, 'assets', 'mibDefaultLayout.json'); 
        if isfile(outputPath)
            selection = uiconfirm(obj.view.gui, ...
                sprintf('!!! Warning !!!\n\nYou are going to overwrite default MIB layout config!\nLocated in:\n%s\n\nAre you sure?', outputPath), ...
                'Overwrite default global layout', ...
                'Options', ["Overwrite", "Cancel"], ...
                'DefaultOption', 2, 'CancelOption', 2, ...
                'Icon', 'warning');
            if strcmp(selection, 'Cancel'); return; end
        end       
end

%% Capture the layout
newDefaultLayout = obj.view.gui.LayoutJSON;
newDefaultLayout = jsondecode(newDefaultLayout); % parse JSON string to MATLAB structure
newDefaultLayout = jsonencode(newDefaultLayout, 'PrettyPrint', true); % Convert back to prettified JSON string
writelines(newDefaultLayout, outputPath);
fprintf('MIB layout was saved to %s\n', outputPath);

end