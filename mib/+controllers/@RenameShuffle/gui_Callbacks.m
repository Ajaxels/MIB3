function gui_Callbacks(obj, source, event) %#ok<INUSD>
% GUI_CALLBACKS - Dispatcher for every RenameShuffle widget callback.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.gui_Callbacks(source, event)
%
% Routes by ``source.Tag`` to the appropriate action method.
% Checkbox cases show a warning dialog when the box is checked.
%
% Input Arguments:
%   - **obj** — :class:`controllers.RenameShuffle` instance.
%   - **source** — widget handle that fired the event.
%   - **event** — event data (unused).

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.RenameShuffle.gui_Callbacks/%s: triggered\n', source.Tag);
end

switch source.Tag
    case 'closeBtn'
        obj.closeWindow();

    case 'selectDirBtn'
        obj.selectDirBtn_Callback();

    case 'addDirBtn'
        obj.addDirBtn_Callback();

    case 'removeDirBtn'
        obj.removeDirBtn_Callback();

    case 'randomBtn'
        obj.randomBtn_Callback();

    case 'helpBtn'
        helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'ribbon', 'home', 'home-renameandshuffle.html');
        if isfile(helpFilPath)
            web(helpFilPath, '-browser');
        else
            web('http://mib.helsinki.fi/help/main3/user-interface/ribbon/home/home-renameandshuffle.html', '-browser');
        end

    case 'dirEdit'
        obj.dirEdit_Callback();

    case {'includeModelCheck','includeMaskCheck','includeAnnotationsCheck','includeMeasurementsCheck'}
        if source.Value
            warningMessages = struct( ...
                'includeModelCheck',         sprintf('Please make sure:\n1. Each folder has only one model file in the *.model format\n2. Material names should be the same in all models\n3. The width/height dimensions of images should be the same for all files'), ...
                'includeMaskCheck',          sprintf('Please make sure:\n1. Each folder has only one mask file in the *.mask format\n2. The width/height dimensions of images should be the same for all files'), ...
                'includeAnnotationsCheck',   sprintf('Please make sure:\n1. Each folder has only one annotation file in the *.ann format'), ...
                'includeMeasurementsCheck',  sprintf('Please make sure:\n1. Each folder has only one measurement file in the *.measure format'));
            dlgOpt.MsgBoxOnly   = true;
            dlgOpt.Icon         = 'puffin_warning';
            dlgOpt.WindowHeight = 190;
            utils.dlgs.inputUniversalDlg(obj.view.gui, '', {''}, ...
                {warningMessages.(source.Tag)}, 'Attention', dlgOpt);
        end
end

end
