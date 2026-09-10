function [modifier, available] = trueModifierKeys()
% TRUEMODIFIERKEYS - Ask the operating system which modifier keys are held right now.
%
% Syntax:
%   .. code-block:: matlab
%
%       [modifier, available] = utils.trueModifierKeys()
%
% MIB tracks the modifier keys by listening to key press / key release events
% (``MibController.gui_WindowKeyPressFcn`` / ``gui_WindowKeyReleaseFcn``, stored in
% ``MibController.currentModifier``). That bookkeeping breaks whenever something blocks
% MATLAB while a modifier is down - a ``pyrun`` call into SAM, a native file dialog, a long
% training run: the release event goes to whatever owns the keyboard at that moment and is
% never delivered, so ``currentModifier`` keeps claiming the key is down. The scroll wheel
% then resizes the brush instead of changing the slice.
%
% This function sidesteps the event stream and reads the live keyboard state from the OS, so
% a caller returning from a blocking operation can re-synchronise instead of guessing.
% Implemented through .NET ``System.Windows.Forms.Control.ModifierKeys``, hence Windows only;
% the assembly is loaded once and cached, and a query costs ~0.06 ms.
%
% Output Arguments:
%   - **modifier** - ``{1 x n}`` cell array of the held modifier names, using the same
%     spelling as MATLAB key events: ``'shift'``, ``'control'``, ``'alt'``. Empty when no
%     modifier is held **and** when the state could not be read - always check *available*
%     before treating an empty result as "nothing is held"
%   - **available** - [logical] ``true`` when the OS was queried successfully. ``false`` on
%     non-Windows platforms or if .NET is unreachable, in which case the caller has to fall
%     back to its own policy (usually: assume the keys were released)
%
% **Example** - re-synchronise after a blocking call:
%
%   .. code-block:: matlab
%
%      [realModifier, modifierIsKnown] = utils.trueModifierKeys();
%      if ~modifierIsKnown; realModifier = {}; end
%      obj.mibController.currentModifier = realModifier;

% Updates
%

persistent assemblyState     % [] = not tried yet, true = usable, false = unavailable

modifier = {};
available = false;

if ~ispc; return; end        % System.Windows.Forms is a Windows-only assembly

if isempty(assemblyState)
    try
        NET.addAssembly('System.Windows.Forms');
        assemblyState = true;
    catch
        assemblyState = false;
    end
end
if ~assemblyState; return; end

try
    heldKeys = int32(System.Windows.Forms.Control.ModifierKeys);
catch
    % a single failure is treated as permanent: this runs on the mouse-click path and
    % retrying a broken .NET call on every click would cost more than the feature is worth
    assemblyState = false;
    return;
end

available = true;
if bitand(heldKeys, int32(System.Windows.Forms.Keys.Shift))   ~= 0; modifier{end+1} = 'shift';   end
if bitand(heldKeys, int32(System.Windows.Forms.Keys.Control)) ~= 0; modifier{end+1} = 'control'; end
if bitand(heldKeys, int32(System.Windows.Forms.Keys.Alt))     ~= 0; modifier{end+1} = 'alt';     end
end
