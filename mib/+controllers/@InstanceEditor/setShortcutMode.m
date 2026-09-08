function setShortcutMode(obj, enable)
% SETSHORTCUTMODE - Take over, or hand back, the a / s / c / Ctrl+F keyboard shortcuts.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.setShortcutMode(true)
%
% Proofreading is a two-handed job: the mouse is on the object and the other
% hand should be able to merge or split without going to the buttons. The keys
% chosen are the ones the hand is already on, which is why they have to be
% taken **off** their normal duty while this is on:
%
% ===================  ==================================  ==========================
% Key                  Normally (``generateKeyShortcuts``)  While shortcut mode is on
% ===================  ==================================  ==========================
% ``a`` / ``shift+a``  Add selection to material           **Merge**
% ``s`` / ``shift+s``  Subtract from material              **Split by selection**
% ``c`` / ``shift+c``  Clear selection                     **Empty the list of picked objects**
% ``ctrl+f``           Find material under cursor          **Add the object under the cursor to the selection**
% ===================  ==================================  ==========================
%
% MIB treats ``a`` and ``shift+a`` as one shortcut with two scopes
% (``overrideShift``), so both variants have to be swallowed or ``shift+a``
% would still write to the material. Both do the same thing here; the 2D/3D
% scope is the ``Mode3D`` checkbox, not the modifier. Everything else - and every
% key at all once this is off - reaches MIB untouched.
%
% The takeover is registered on ``MibController.keyPressOverride`` rather than by
% replacing a figure callback. ``WindowKeyPressFcn`` is reinstalled from at least
% five places in ``@MibImageDocument`` (after every pan, brush stroke and
% drag-and-drop), so a takeover of that handle would keep dying the way pick mode
% did before ``reassertPickMode``.
%
% Input Arguments:
%   - **enable** - logical, take the keys over or give them back
%
% Output Arguments:
%   (none)
%
% See also: controllers.InstanceEditor.handleShortcut,
% controllers.InstanceEditor.setPickMode

% Updates
%

if isempty(obj.mibController) || ~isvalid(obj.mibController)
    obj.shortcutModeActive = false;
    return;
end

if enable
    obj.mibController.keyPressOverride = struct(...
        'owner', obj, ...
        'fcn', @(key, modifier) obj.handleShortcut(key, modifier));
    obj.shortcutModeActive = true;
else
    % Only ever give back what is still ours: another tool may have taken the
    % keys since, and clearing its claim would leave it believing it has them.
    override = obj.mibController.keyPressOverride;
    if ~isempty(override) && isequal(override.owner, obj)
        obj.mibController.keyPressOverride = [];
    end
    obj.shortcutModeActive = false;
end

% The checkbox follows the state rather than the other way round, so a takeover
% dropped from anywhere - closeWindow above all - cannot leave it claiming the
% editor still owns the keys.
if ~isempty(obj.view) && isvalid(obj.view.gui)
    obj.view.handles.useShortcuts.Value = obj.shortcutModeActive;
end
end
