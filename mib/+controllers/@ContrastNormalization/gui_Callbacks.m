function gui_Callbacks(obj, source, event) %#ok<INUSD>
% GUI_CALLBACKS - Dispatcher for every ContrastNormalization widget callback.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.gui_Callbacks(source, event)
%
% Routes by ``source.Tag`` to the appropriate action method.  ``Target``
% and ``Mode`` cases also update context-sensitive widget enable states.
% All other widgets fall through to :meth:`updateBatchOptFromGUI`.
%
% Input Arguments:
%   - **obj** — :class:`controllers.ContrastNormalization` instance.
%   - **source** — widget handle that fired the event.
%   - **event** — event data (unused).

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.ContrastNormalization.gui_Callbacks/%s: triggered\n', source.Tag);
end
switch source.Tag
    case 'continueBtn'
        obj.continueBtn_Callback();

    case 'closeBtn'
        obj.closeWindow();

    case 'helpBtn'
        helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'site', 'user-interface', 'ribbon', 'image', 'normalize.html');
        if isfile(helpFilPath)
            web(helpFilPath, '-browser');
        else
            web('http://mib.helsinki.fi/help/main3/user-interface/ribbon/image/normalize.html', '-browser');
        end

    case 'Target'
        obj.updateBatchOptFromGUI(source);
        obj.updateContextualWidgets();

    case 'Mode'
        obj.updateBatchOptFromGUI(source);
        obj.updateContextualWidgets();

    otherwise
        obj.updateBatchOptFromGUI(source);
end

end
