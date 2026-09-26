function applyThemeColors(hFig)
% APPLYTHEMECOLORS - adapt the standard dialog button colors to the figure theme.
%
% Syntax:
%   .. code-block:: matlab
%
%      utils.applyThemeColors(hFig)
%
% Most MIB dialogs paint their main action button green and their Close/Cancel
% button orange in App Designer, with the font color on auto. Under the dark theme
% the auto font turns near-white and becomes unreadable on these light colors.
%
% The function finds every ``uibutton`` and ``uistatebutton`` of ``hFig`` whose
% background is one of the standard dialog colors of **either** theme
% (``dialogAction``, ``dialogClose``, ``dialogSecondary`` or ``dialogStop`` of
% ``utils.themeColors``) and repaints it with
% that color of the theme the figure currently uses. The same is done for the
% background of every ``uitab`` and ``uipanel`` painted ``tabHighlight``, of every
% ``uidropdown``, ``uieditfield``, numeric ``uieditfield`` and ``uispinner`` painted
% ``fieldError``, ``fieldYellow`` or ``fieldBlue``, and for the
% color-coded parts of a window: ``uitab``, ``uipanel``, ``uilabel`` and buttons painted one
% of the ``panel...`` tints (``panelYellow``, ``panelBlue``, ``panelGreen``), buttons and
% input fields painted one of the ``widget...`` tints. A button whose background was set
% explicitly to the theme default (``background`` of either theme, typically copied from
% another widget with ``btn.BackgroundColor = panel.BackgroundColor``) is switched back
% to ``BackgroundColorMode = 'auto'``, because the copied value no longer follows the
% theme. Finally, the
% title of every ``uitab`` whose ``ForegroundColor`` was set explicitly to the ``text``
% color of either theme (App Designer writes the light default ``[0.129 0.129 0.129]``
% when the title color is touched, which is invisible in the dark theme). Matching both
% themes makes the call idempotent and reversible, so it is also the handler for a
% theme switch. Widgets with any other background are left untouched; the match
% uses a tolerance of 1e-3 because App Designer stores the colors rounded to 4
% decimals.
%
% Explicitly assigned colors are not remapped by MATLAB on a theme switch, so the
% function installs itself as ``hFig.ThemeChangedFcn``, unless the figure already
% has a different handler (which is then left in place and has to call this
% function itself). On releases without the figure ``Theme`` property (before
% R2025a) the buttons already carry the light colors and nothing is changed.
%
% Input Arguments:
%   - **hFig** - [matlab.ui.Figure] handle of the dialog figure, e.g. ``obj.view.gui``
%
% Usage:
%   .. code-block:: matlab
%
%      obj.view = core.ChildView(obj, 'views.StitchingGUI');
%      utils.applyThemeColors(obj.view.gui);
%
% See also:
%   ``utils.themeColors``
%

if ~isprop(hFig, 'Theme') || isempty(hFig.Theme); return; end

lightPalette = utils.themeColors('light');
darkPalette = utils.themeColors('dark');
currentPalette = utils.themeColors(hFig);

% widget groups and the palette colors each group may carry
buttonList = [findall(hFig, 'Type', 'uibutton'); findall(hFig, 'Type', 'uistatebutton')];
containerList = [findall(hFig, 'Type', 'uitab'); findall(hFig, 'Type', 'uipanel')];
fieldList = [findall(hFig, 'Type', 'uidropdown'); findall(hFig, 'Type', 'uieditfield'); ...
             findall(hFig, 'Type', 'uinumericeditfield'); findall(hFig, 'Type', 'uispinner')];
labelList = findall(hFig, 'Type', 'uilabel');
panelTints = {'panelYellow', 'panelBlue', 'panelGreen'};
widgetTints = {'widgetYellow', 'widgetBlue', 'widgetGreen'};
widgetGroups = {buttonList, [{'dialogAction', 'dialogClose', 'dialogSecondary', 'dialogStop'}, panelTints, widgetTints]; ...
                containerList, [{'tabHighlight'}, panelTints]; ...
                fieldList, [{'fieldError', 'fieldYellow', 'fieldBlue'}, widgetTints]; ...
                labelList, panelTints};

for groupId = 1:size(widgetGroups, 1)
    widgetList = widgetGroups{groupId, 1};
    colorNames = widgetGroups{groupId, 2};
    for widgetId = 1:numel(widgetList)
        backgroundColor = widgetList(widgetId).BackgroundColor;
        if ~isnumeric(backgroundColor); continue; end   % 'none' of an unpainted uilabel
        for colorId = 1:numel(colorNames)
            colorName = colorNames{colorId};
            if max(abs(backgroundColor - lightPalette.(colorName))) < 1e-3 || ...
                    max(abs(backgroundColor - darkPalette.(colorName))) < 1e-3
                widgetList(widgetId).BackgroundColor = currentPalette.(colorName);
                break;
            end
        end
    end
end

% buttons that carry a copy of the theme default background: put them back on auto
for buttonId = 1:numel(buttonList)
    if strcmp(buttonList(buttonId).BackgroundColorMode, 'manual') && ...
            (max(abs(buttonList(buttonId).BackgroundColor - lightPalette.background)) < 1e-3 || ...
             max(abs(buttonList(buttonId).BackgroundColor - darkPalette.background)) < 1e-3)
        buttonList(buttonId).BackgroundColorMode = 'auto';
    end
end

% tab titles given an explicit color equal to the normal text of either theme; switching
% them back to auto mode does not take effect until the next theme change
tabList = findall(hFig, 'Type', 'uitab');
for tabId = 1:numel(tabList)
    if strcmp(tabList(tabId).ForegroundColorMode, 'manual') && ...
            (max(abs(tabList(tabId).ForegroundColor - lightPalette.text)) < 1e-3 || ...
             max(abs(tabList(tabId).ForegroundColor - darkPalette.text)) < 1e-3)
        tabList(tabId).ForegroundColor = currentPalette.text;
    end
end

if isempty(hFig.ThemeChangedFcn)
    hFig.ThemeChangedFcn = @(src, evnt) utils.applyThemeColors(src);
end

end
