function outputPath = saveLayout(obj, mode)
% SAVELAYOUT - Store the current layout of panels to disk.
%
% Syntax:
%   .. code-block:: matlab
%
%      outputPath = obj.saveLayout()
%      outputPath = obj.saveLayout(mode)
%
% Input Arguments:
%   - **mode** — *(optional)* char, default: ``'localDefault'``
%
%     - ``'localDefault'`` — save to ``utils.getPrefDir/mibDefaultLayout.json``
%     - ``'custom'`` — save to ``utils.getPrefDir`` using a custom name
%     - ``'globalDefault'`` — overwrite the bundled default in ``MIB/assets/defaultLayout.json``
%
% Output Arguments:
%   - **outputPath** — char with the full path to the saved layout JSON file;
%     the file can be restored with ``loadLayout``
%
% **Example** — save the current layout as the local default:
%
%   .. code-block:: matlab
%
%      outputPath = obj.saveLayout();
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
