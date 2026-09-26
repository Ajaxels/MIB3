function palette = themeColors(themeSource)
% THEMECOLORS - named MIB widget colors for the light or the dark theme.
%
% Syntax:
%   .. code-block:: matlab
%
%      palette = utils.themeColors(themeSource)
%
% The single definition of the colors that MIB assigns explicitly to widgets and
% that therefore have to be adapted to the MATLAB theme. Colors left on auto
% (``...ColorMode = 'auto'``) follow the theme by themselves and are not listed.
%
% The light colors are the original MIB colors. The dark colors are darker tones of
% the same hues, chosen to keep a WCAG contrast of at least 4.5:1 against the
% near-white text (``[0.851 0.851 0.851]``) that the dark theme uses for buttons;
% the font color is therefore always left on auto. Measurements and the rejected
% alternative (pastels with black text) are in
% ``development/notes/dark_light_scheme.md``.
%
% Input Arguments:
%   - **themeSource** - one of:
%
%     - ``'light'`` or ``'dark'`` - the palette of that theme
%     - a figure handle - the palette of the theme the figure currently uses
%       (``hFig.Theme.BaseColorStyle``); releases without the figure ``Theme``
%       property (before R2025a) get the light palette
%
% Output Arguments:
%   - **palette** - [struct] RGB triplets, fields:
%
%     - ``.bufferInMemory``   - Datasets panel, buffer with data but no file on disk
%     - ``.bufferFileBacked`` - Datasets panel, buffer with data loaded from a file
%     - ``.bufferSelected``   - Datasets panel, the currently shown buffer
%     - ``.dialogAction``     - main action button of a dialog (e.g. Stitch, Continue),
%       light ``[0.149 0.902 0.1804]``
%     - ``.dialogClose``      - Close/Cancel button of a dialog, light ``[1 0.5294 0.102]``
%     - ``.dialogSecondary``  - secondary action button, weaker than ``dialogAction``
%       (e.g. Update in BatchProcessing), light ``[0.6314 0.9412 0.6471]``
%     - ``.dialogStop``       - a running action that can be stopped (e.g. Stop protocol),
%       light ``[1 0 0]``
%     - ``.fieldError``       - background of an input field (dropdown, edit field) that
%       shows a missing or invalid input (e.g. the material dropdowns of Graphcut without
%       a model), light ``[1 0 0]``
%     - ``.tabHighlight``     - background of a tab or panel that is set apart from the
%       rest of the window (e.g. the Animation tab of VolRenApp), light ``[0.8 0.8 0.8]``
%     - ``.tableCell``        - background of table cells painted explicitly with a
%       ``uistyle`` (e.g. the value columns of the Preferences color tables), light
%       ``[1 1 1]``, dark the theme's field background; the table's own
%       ``ForegroundColor`` is ignored in the dark theme, so the cells must be dark
%       for the auto text to be readable
%     - ``.tableHighlight``   - background of a table cell marked as the current choice
%       by a ``uistyle`` (e.g. the selected material in the Segmentation panel), light
%       ``[0.2 0.6 1]``; its text is ``.text``
%     - ``.text``             - normal text, equal to the auto font color of MATLAB
%       widgets. For places that do not follow the theme by themselves: ``uihtml``
%       content (a web page that ignores the MATLAB theme, colored via CSS), tab
%       titles set explicitly in App Designer and ``uistyle`` table cells
%     - ``.disabledText``     - greyed-out text of table cells that are shown but not in
%       use at the moment (e.g. the materials when the selection is restricted to a
%       material), light ``[0.78 0.78 0.78]``. Deliberately below 4.5:1 so that it reads
%       as inactive, dark ``[0.4 0.4 0.4]`` gives 3.3:1 on ``.tableCell``
%     - ``.dimmedText``       - secondary, subdued text on the dialog background (e.g.
%       the suffix line of ``utils.dlgs.showErrorDialog``); dimmer than the normal
%       text but still at least 4.5:1 against the background
%     - ``.htmlLink``         - hyperlinks of ``uihtml`` content; the browser default
%       dark blue is unreadable on the dark background
%
% Usage:
%   .. code-block:: matlab
%
%      palette = utils.themeColors(obj.UIFigure);
%      buttonHandle.BackgroundColor = palette.bufferSelected;
%
% See also:
%   ``utils.applyThemeColors``, ``controllers.MibActiveDataset.paintBufferButton``
%

if ~ischar(themeSource) && ~isstring(themeSource)
    hFig = themeSource;
    if isprop(hFig, 'Theme') && ~isempty(hFig.Theme)
        themeSource = hFig.Theme.BaseColorStyle;
    else
        themeSource = 'light';
    end
end

if strcmp(themeSource, 'dark')
    palette.bufferInMemory   = [0.42 0.30 0.08];
    palette.bufferFileBacked = [0.20 0.32 0.20];
    palette.bufferSelected   = [0 0.42 0];
    palette.dialogAction     = palette.bufferSelected;
    palette.dialogClose      = palette.bufferInMemory;
    palette.dialogSecondary  = palette.bufferFileBacked;
    palette.dialogStop       = [0.6 0.1 0.1];
    palette.fieldError       = palette.dialogStop;
    palette.tabHighlight     = [0.25 0.25 0.25];
    palette.tableCell        = [0.0706 0.0706 0.0706];
    palette.tableHighlight   = [0.10 0.33 0.62];
    palette.text             = [0.851 0.851 0.851];
    palette.disabledText     = [0.4 0.4 0.4];
    palette.htmlLink         = [0.55 0.75 1];
    palette.dimmedText       = [0.65 0.65 0.65];
else
    palette.bufferInMemory   = [1 0.85 0.6];
    palette.bufferFileBacked = [0.7 1 0.7];
    palette.bufferSelected   = [0 1 0];
    palette.dialogAction     = [0.149 0.902 0.1804];
    palette.dialogClose      = [1 0.5294 0.102];
    palette.dialogSecondary  = [0.6314 0.9412 0.6471];
    palette.dialogStop       = [1 0 0];
    palette.fieldError       = palette.dialogStop;
    palette.tabHighlight     = [0.8 0.8 0.8];
    palette.tableCell        = [1 1 1];
    palette.tableHighlight   = [0.2 0.6 1];
    palette.text             = [0.129 0.129 0.129];
    palette.disabledText     = [0.78 0.78 0.78];
    palette.htmlLink         = [0 0 0.933];
    palette.dimmedText       = [0.4 0.4 0.4];
end

end
