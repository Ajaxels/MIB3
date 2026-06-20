function gui_Callbacks(obj, source, event) %#ok<INUSD>
% GUI_CALLBACKS - Dispatcher for every RenameRestore widget callback.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.gui_Callbacks(source, event)
%
% Routes by ``source.Tag`` to the appropriate action method.
% Context-menu items for the two directory listboxes are also routed here.
%
% Input Arguments:
%   - **obj** — :class:`controllers.RenameRestore` instance.
%   - **source** — widget handle that fired the event.
%   - **event** — event data (unused).

switch source.Tag
    case 'closeBtn'
        obj.closeWindow();

    case 'helpBtn'
        helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'site', 'user-interface', 'ribbon', 'home', 'home-renameandshuffle.html');
        if isfile(helpFilPath)
            web(helpFilPath, '-browser');
        else
            web('http://mib.helsinki.fi/help/main3/user-interface/ribbon/home/home-renameandshuffle.html', '-browser');
        end

    case 'selectSettingsFileBtn'
        obj.selectSettingsFileBtn_Callback();

    case 'projectFilenameEdit'
        obj.projectFilenameEdit_Callback();

    case 'restoreBtn'
        obj.restoreBtn_Callback();

    case 'resaveProjectBtn'
        obj.resaveProject();

    case {'includeMaskCheck','includeAnnotationsCheck','includeMeasurementsCheck','includeModelCheck'}
        if source.Value
            warningMessages = struct( ...
                'includeModelCheck',        sprintf('Please make sure:\n1. Each folder has only one model file in the *.model format\n2. Material names should be the same in all models\n3. The width/height dimensions of images should be the same for all files'), ......
                'includeMaskCheck',         sprintf('Please make sure:\n1. Each folder has only one mask file in the *.mask format\n2. The width/height dimensions of images should be the same for all files'), ...
                'includeAnnotationsCheck',  sprintf('Please make sure:\n1. Each folder has only one annotation file in the *.ann format'), ...
                'includeMeasurementsCheck', sprintf('Please make sure:\n1. Each folder has only one measurements file in the *.measure format'));
            dlgOpt.MsgBoxOnly  = true;
            dlgOpt.Icon        = 'puffin_warning';
            dlgOpt.WindowHeight = 190;
            utils.dlgs.inputUniversalDlg(obj.view.gui, '', {''}, ...
                {warningMessages.(source.Tag)}, 'Attention!', dlgOpt);
        end

    % --- Context menu items for randomDirsList ---
    case 'randomDirsList_updateDir'
        obj.updateDir('randomDirsList');

    case 'randomDirsList_updateParentDir'
        obj.updateParentDir('randomDirsList');

    case 'randomDirsList_clipboard'
        obj.copyShowDirectory('randomDirsList', 'clipboard');

    case 'randomDirsList_fileexplorer'
        obj.copyShowDirectory('randomDirsList', 'fileexplorer');

    % --- Context menu items for destinationDirsList ---
    case 'destinationDirsList_updateDir'
        obj.updateDir('destinationDirsList');

    case 'destinationDirsList_updateParentDir'
        obj.updateParentDir('destinationDirsList');

    case 'destinationDirsList_clipboard'
        obj.copyShowDirectory('destinationDirsList', 'clipboard');

    case 'destinationDirsList_fileexplorer'
        obj.copyShowDirectory('destinationDirsList', 'fileexplorer');
end

end
