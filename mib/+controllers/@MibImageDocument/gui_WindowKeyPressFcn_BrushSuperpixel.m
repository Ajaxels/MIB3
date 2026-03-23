function gui_WindowKeyPressFcn_BrushSuperpixel(obj, eventdata)
% function gui_WindowKeyPressFcn_BrushSuperpixel(obj, eventdata)
% Handle key callbacks during brush superpixel mode
%
% Currently supports Ctrl+Z to undo the last selected superpixel
% during an active superpixel brush stroke.
%
% Parameters:
% eventdata: KeyData structure with fields:
% @li .Key - name of the key pressed, in lower case
% @li .Character - character interpretation of the key
% @li .Modifier - cell array of modifier key names ('control', 'shift', 'alt')
%
% Return values:
%   (none)
%

%|
% @b Examples:
% @code % typically set as a callback, not called directly:
% hFig.WindowKeyPressFcn = @(hWidget, hData)obj.gui_WindowKeyPressFcn_BrushSuperpixel(hData); @endcode

% Updates
%

char = eventdata.Key;
if strcmp(char, 'alt'); return; end
modifier = eventdata.Modifier;

% find shortcut action
controlSw = 0;
shiftSw = 0;
altSw = 0;
if ismember('control', modifier); controlSw = 1; end
if ismember('shift', modifier); shiftSw = 1; end
if ismember('alt', modifier); altSw = 1; end

ActionId = ismember(obj.mibModel.preferences.KeyShortcuts.Key, char) & ...
    ismember(obj.mibModel.preferences.KeyShortcuts.control, controlSw) & ...
    ismember(obj.mibModel.preferences.KeyShortcuts.shift, shiftSw) & ...
    ismember(obj.mibModel.preferences.KeyShortcuts.alt, altSw);
ActionId = find(ActionId > 0);

if ~isempty(ActionId)
    switch obj.mibModel.preferences.KeyShortcuts.Action{ActionId}
        case 'Undo/Redo last action'
            if numel(obj.brushSelection{2}.selectedSlicIndices) == 0
                return;
            end
            % remove the last selected superpixel
            removeId = obj.brushSelection{2}.selectedSlicIndices(end);
            obj.brushSelection{2}.selectedSlicIndices(end) = [];
            obj.brushSelection{2}.selectedSlic(obj.brushSelection{2}.slic == removeId) = 0;

            % redraw CData from stored boundaries + remaining selected superpixels
            CData = obj.brushSelection{2}.CData;
            CData(obj.brushSelection{2}.selectedSlic == 1) = intmax(class(obj.imageHandle.CData)) * .4;
            obj.imageHandle.CData = CData;
    end
end

end
