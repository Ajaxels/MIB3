function row = findKeyShortcut(KeyShortcuts, key, modifier)
% FINDKEYSHORTCUT - Find the action of KeyShortcuts triggered by a key press.
%
% Syntax:
%   .. code-block:: matlab
%
%      row = utils.findKeyShortcut(KeyShortcuts, key, modifier)
%
% The single implementation of the matching rules, used by every key press handler
% and to be used by any new one. Actions that take Shift or Alt as an argument, for
% example Shift+A adds the selection to the material in the whole stack, have
% ``overrideShift`` or ``overrideAlt`` set. When any row bound to the pressed key has
% such a flag, the modifier is ignored for this key, so the row without the modifier
% is the one found. Alt is also ignored in Alt+Shift+A, on the key of ``'Add to
% selection to material'``, which stands for the 4D scope of this action.
%
% The full table is scanned once, with one ``strcmp`` on ``KeyShortcuts.Key``; the
% rules are evaluated only on the few rows of the pressed key, which keeps a key
% press fast with a long list of actions. Nothing is cached, so a change of the
% preferences needs no invalidation.
%
% Rows without a shortcut have an empty ``Key`` and an empty ``key`` finds nothing.
% Two rows with one combination should not exist, as Preferences does not allow to
% create them, but a hand-edited override file may have them: the first row is
% returned, because callers use the result in a ``switch``, which needs one value.
%
% Input Arguments:
%   - **KeyShortcuts** - [struct] shortcuts from ``mibModel.preferences.KeyShortcuts``,
%     see ``utils.defaults.generateKeyShortcuts``
%   - **key** - [char] lower-case name of the key, as in ``KeyData.Key``
%   - **modifier** - [cell] pressed modifiers, as in ``KeyData.Modifier``, for
%     example ``{'control', 'shift'}``
%
% Output Arguments:
%   - **row** - [number] index of the action in ``KeyShortcuts``, ``[]`` when the
%     pressed combination has no action
%
% Usage:
%
%   **Example 1** - find the action of a key press
%
%   .. code-block:: matlab
%
%      KeyShortcuts = obj.mibModel.preferences.KeyShortcuts;
%      row = utils.findKeyShortcut(KeyShortcuts, hData.Key, hData.Modifier);
%      if isempty(row); return; end
%      switch KeyShortcuts.Action{row}
%          case 'Undo/Redo last action'
%              obj.mibModel.undo();
%      end
%

% Updates
%

row = [];
if isempty(key); return; end
keyRows = find(strcmp(KeyShortcuts.Key, key));
if isempty(keyRows); return; end

controlPressed = any(strcmp(modifier, 'control'));
shiftPressed = any(strcmp(modifier, 'shift'));
altPressed = any(strcmp(modifier, 'alt'));

shiftExpected = shiftPressed && ~any(KeyShortcuts.overrideShift(keyRows) == 1);
altExpected = altPressed && ~any(KeyShortcuts.overrideAlt(keyRows) == 1) && ...
    ~(shiftPressed && any(strcmp(KeyShortcuts.Action(keyRows), 'Add to selection to material')));

isMatch = KeyShortcuts.control(keyRows) == controlPressed & ...
    KeyShortcuts.shift(keyRows) == shiftExpected & ...
    KeyShortcuts.alt(keyRows) == altExpected;
row = keyRows(find(isMatch, 1));
end
