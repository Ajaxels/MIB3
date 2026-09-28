function duplicateConfigAndNetwork(obj)
% DUPLICATECONFIGANDNETWORK - copy the network file and its config to a new filename.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.duplicateConfigAndNetwork()
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDeep.duplicateConfigAndNetwork: triggered\n');
end

    currPath = fileparts(obj.BatchOpt.NetworkFilename);
    [currFile, currPath] = utils.dlgs.mibUiGetFile({'*.mibDeep', 'mibDeep Files (*.mibDeep)'}, ...
        'Select source network', currPath);
    if isequal(currFile, 0); return; end
    currFile = currFile{1};

    [newFile, newPath]  = uiputfile({'*.mibDeep', 'mibDeep files (*.mibDeep)';
        '*.mat', 'Mat files (*.mat)'}, 'Set target network name', ...
        fullfile(currPath, currFile));
    if newFile == 0; return; end

    wb = uiprogressdlg(obj.view.gui, 'Message', 'Please wait...', 'Title', 'Saving network and config');

    % copy network file
    newNetworkFile = fullfile(newPath, newFile);
    if isfile(fullfile(currPath, currFile))
        copyfile(fullfile(currPath, currFile), newNetworkFile);
    else
        mgsOpt.MsgBoxOnly = true;
        mgsOpt.WindowHeight = 180;
        mgsOpt.headerLines = 1;
        msgText = sprintf('Please select the network file and try again');
        utils.dlgs.inputUniversalDlg(obj.view.gui, 'The network file to copy is missing!', {}, {msgText}, 'Network file is missing!', mgsOpt);
        delete(wb);
        return;
    end
    wb.Value = 0.5;

    % save config
    oldConfigName = fullfile(currPath, replace(currFile,'.mibDeep', '.mibCfg'));
    newConfigName = replace(newNetworkFile,'.mibDeep', '.mibCfg');
    if isfile(oldConfigName)
        copyfile(oldConfigName, newConfigName);
        % update network filename in the new config file
        matObj = matfile(newConfigName, 'Writable', true);
        BatchOpt = matObj.BatchOpt;
        BatchOpt.NetworkFilename = ['[RELATIVE]' newFile];
        matObj.BatchOpt = BatchOpt;
    end
    wb.Value = 1;
    delete(wb);

    % load the duplicated config
    res = uiconfirm(obj.view.gui, ...
        'Would you like to load the duplicated config into DeepMIB now?', ...
        'Load the duplicated config', ...
        'Options', {'Load the duplicated config','Keep the current'}, ...
        'Icon', 'question');
    if strcmp(res, 'Load the duplicated config')
        obj.loadConfig(newConfigName);
    end


end

