function gui_Callbacks(obj, source, event) %#ok<INUSD>
% GUI_CALLBACKS - Dispatcher for every DatasetInfo widget callback.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.gui_Callbacks(source, event)
%
% Routes by ``source.Tag`` to the appropriate action method.
%
% Input Arguments:
%   - **obj** — :class:`controllers.DatasetInfo` instance.
%   - **source** — widget handle that fired the event.
%   - **event** — event data (unused).

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.DatasetInfo.gui_Callbacks/%s: triggered\n', source.Tag);
end
switch source.Tag
    case 'closeButton'
        obj.closeWindow();

    case 'refreshButton'
        obj.updateWidgets();

    case 'simplifyButton'
        obj.simplifyButton_Callback();

    case 'insertButton'
        obj.insertButton_Callback();

    case 'modifyButton'
        obj.modifyButton_Callback();

    case 'deleteButton'
        obj.deleteButton_Callback();

    case 'findNextButton'
        obj.searchEdit_Callback('next');

    case 'findPreviousButton'
        obj.searchEdit_Callback('previous');

    case 'searchEdit'
        obj.searchEdit_Callback('new');
end

end
