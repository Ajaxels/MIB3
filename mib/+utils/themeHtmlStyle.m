function styleTag = themeHtmlStyle(hFig, backgroundColor)
% THEMEHTMLSTYLE - CSS that gives a uihtml page the colors of a dark-themed window.
%
% Syntax:
%   .. code-block:: matlab
%
%      styleTag = utils.themeHtmlStyle(hFig, backgroundColor)
%
% A ``uihtml`` component renders a web page that ignores the MATLAB theme: it
% always shows a white background with black text, which stands out as a bright
% block in a dark window, and the browser default link color (dark blue) is
% unreadable on a dark background. In the dark theme this function returns a
% ``<style>`` element that sets the page background to ``backgroundColor``, the
% text to ``utils.themeColors('dark').text`` and links to ``.htmlLink``; in the
% light theme it returns an empty char, so the page keeps the browser defaults.
%
% Insert the element **before** any style of the caller (first in ``<head>``, or
% at the very beginning of an HTML fragment), so that the caller's own styles
% still win. The colors are fixed at the moment the page is written: a window
% has to rewrite its ``uihtml`` content from its ``ThemeChangedFcn`` to follow
% a theme switch.
%
% Input Arguments:
%   - **hFig** - [matlab.ui.Figure] the window that holds the ``uihtml``; its
%     ``Theme.BaseColorStyle`` decides the result. Releases without the figure
%     ``Theme`` property (before R2025a) are treated as light
%   - **backgroundColor** - [RGB triplet] the color the page should take, usually
%     the ``BackgroundColor`` of the ``uihtml`` parent or ``hFig.Color``, so that
%     the page merges into the window
%
% Output Arguments:
%   - **styleTag** - [char] ``'<style>html,body{...} a{...}</style>'`` in the dark
%     theme, ``''`` otherwise
%
% Usage:
%   .. code-block:: matlab
%
%      hHtml = obj.view.handles.infoText;
%      hHtml.HTMLSource = [utils.themeHtmlStyle(obj.view.gui, hHtml.Parent.BackgroundColor), ...
%          '<p style="font-family: Sans-serif;">Text</p>'];
%
% See also:
%   ``utils.themeColors``, ``utils.applyThemeColors``
%

styleTag = '';
if ~isprop(hFig, 'Theme') || isempty(hFig.Theme) || ~strcmp(hFig.Theme.BaseColorStyle, 'dark')
    return;
end

palette = utils.themeColors('dark');
rgbCss = @(color) sprintf('rgb(%d,%d,%d)', round(255 * color));
styleTag = sprintf('<style>html,body{background-color:%s;color:%s} a{color:%s}</style>', ...
    rgbCss(backgroundColor), rgbCss(palette.text), rgbCss(palette.htmlLink));
end
