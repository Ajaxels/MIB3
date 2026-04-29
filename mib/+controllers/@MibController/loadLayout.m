function status = loadLayout(obj, mode, layoutFilename)
% LOADLAYOUT - Restore MIB layout from a JSON file.
%
% Syntax:
%   function status = loadLayout(obj, mode, layoutFilename)
%
% Input Arguments:
%   - **mode** — char [optional, default='localDefault'] mode to restore MIB layout
%     - 'localDefault' - default layout for local installation of MIB, restored from utils.getPrefDir, 'mibDefaultLayout.json'
%     - 'custom' - restore layout from utils.getPrefDir
%     - 'globalDefault' - restore the default MIB layout configuration from MIB\assets\defaultLayout.json
%   - **layoutFilename** — [OPTIONAL] char with the full path to the file to the
%     layout JSON file. This file can be generated using utils.storeLayout function
%
% Usage:
%   Example 1::
%
%     status = obj.loadLayout(obj); // call from MibController class, restore the default layout
%
%   Example 2::
%
%     status = obj.loadLayout(obj, 'custom', 'c:\temp\mibLayout.json'); // call from MibController class, restore layout from mibLayout.json
%

%
% Updates
%

arguments (Input)
    obj controllers.MibController
    mode (1,:) char = 'custom'
    layoutFilename (1,:) char = ''
end

arguments (Output)
    status (1,1) logical
end

status = false;

switch mode
    case 'localDefault'
        % get the output path
        prefdir = utils.getPrefDir(); % get the directory with MIB preferences
        layoutFilename = fullfile(prefdir, 'mibDefaultLayout.json');
        
        if ~isfile(layoutFilename) % get default MIB layout
            layoutFilename = fullfile(obj.mibPath, 'assets', 'mibDefaultLayout.json'); 
        end
    case 'custom'
        if isempty(layoutFilename)
            prefdir = utils.getPrefDir(); % get the directory with MIB preferences
            [fileName, filePath] = uigetfile({'*.json', 'JSON format'; '*.*','All Files (*.*)'}, 'Select layout file', prefdir);
            if isequal(fileName, 0), return; end
            layoutFilename = fullfile(filePath, fileName); % construct the full file path
        end

        if ~isfile(layoutFilename)
            uialert(obj.view.gui, ...
                sprintf('!!! Error !!!\n\nThe custom layout file is missing!\n\nLocation of the selected custom layout file:\n%s', layoutFilename), ...
                'Missing MIB custom layout');
        end

    case 'globalDefault'
        layoutFilename = fullfile(obj.mibPath, 'assets', 'mibDefaultLayout.json'); 
        if ~isfile(layoutFilename)
            uialert(obj.view.gui, ...
                sprintf('!!! Error !!!\n\nThe default MIB layout is missing!\n\nLocation of the default MIB layout:\n%s', layoutFilename), ...
                'Missing MIB default layout');
        end
end

% Load the layout from the JSON file
layoutData = jsondecode(fileread(layoutFilename));
% Restore the layout using the loaded data
obj.view.gui.PanelLayout = layoutData.panelLayout;

status = true;
end
