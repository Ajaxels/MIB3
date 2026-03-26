function childWindowKeyPressFcn(controller, hWidget, hData)
% function childWindowKeyPressFcn(controller, hWidget, hData)
% Shared keyboard shortcut handler for child dialog controllers.
%
% Provides a safe subset of MIB keyboard shortcuts that work correctly
% in child dialog windows (Quantification, Annotations, etc.) without
% requiring a handle to MibController.  Reads the user's KeyShortcuts
% preferences so custom bindings are respected.
%
% Currently supported actions:
% @li Undo/Redo last action — calls mibModel.undo() + fires ShowImage
%
% Additionally handles Escape independently of KeyShortcuts:
% @li Escape — calls controller.closeWindow() if the method exists
%
% Parameters:
% controller: handle to the child controller; must have .mibModel property
% hWidget: the UIFigure that fired the event (passed by WindowKeyPressFcn)
% hData: KeyData event object with .Key and .Modifier fields
%
% How to wire in a child controller's addCallbacks (one line):
%|
% @b Examples:
% @code
% obj.view.gui.WindowKeyPressFcn = @(h,d) utils.childWindowKeyPressFcn(obj, h, d);
% @endcode

% Updates
%

if isempty(hData) || ~isprop(hData, 'Key') || isempty(hData.Key); return; end

% Skip if the focused component is an edit field or text area
focusedComp = hWidget.CurrentObject;
if ~isempty(focusedComp) && isprop(focusedComp, 'Type') && ...
        ismember(focusedComp.Type, {'uieditfield', 'uinumericeditfield', 'uitextarea', 'uispinner'})
    return;
end

char = lower(hData.Key);
modifier = hData.Modifier;

% --- Escape: close the dialog (independent of KeyShortcuts) ---
if strcmp(char, 'escape')
    if ismethod(controller, 'closeWindow')
        controller.closeWindow();
    end
    return;
end

% --- Match against user's KeyShortcuts table ---
if ~isvalid(controller) || ~isprop(controller, 'mibModel'); return; end
mibModel = controller.mibModel;
KeyShortcuts = mibModel.preferences.KeyShortcuts;

keyMask = strcmp(KeyShortcuts.Key, char);
controlSw    = any(strcmp(modifier, 'control'));
shiftPressed = any(strcmp(modifier, 'shift'));
altPressed   = any(strcmp(modifier, 'alt'));

% correct with override shift/alt settings (same logic as gui_WindowKeyPressFcn)
shiftSw = shiftPressed && ~any(strcmp(char, KeyShortcuts.Key(KeyShortcuts.overrideShift == 1)));
if ~altPressed
    altSw = false;
else
    overrideAlt = any(strcmp(char, KeyShortcuts.Key(KeyShortcuts.overrideAlt == 1)));
    altPlusA    = any(strcmp(char, KeyShortcuts.Key(strcmp(KeyShortcuts.Action, 'Add to selection to material')))) && shiftPressed;
    altSw = ~overrideAlt && ~altPlusA;
end

ActionId = find(keyMask & ...
    (KeyShortcuts.control == controlSw) & ...
    (KeyShortcuts.shift   == shiftSw) & ...
    (KeyShortcuts.alt     == altSw));

if isempty(ActionId); return; end

% --- Handle whitelisted actions ---
switch KeyShortcuts.Action{ActionId}
    case 'Undo/Redo last action'
        if ~mibModel.Backup.enableSwitch; return; end
        if mibModel.Backup.prevUndoIndex == 0; return; end
        mibModel.undo();
        notify(mibModel, 'ShowImage');
end
end
