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
%     - ``.panelYellow``, ``.panelBlue``, ``.panelGreen`` - tinted background of a tab,
%       panel or label that color-codes a part of a window (e.g. the Preprocess, Train and
%       Predict tabs of DeepMIB), light ``[1 0.9804 0.7686]``, ``[0.7686 0.902 0.9882]``,
%       ``[0.8588 0.9294 0.7804]``. The dark versions keep the hue (amber-brown instead
%       of olive for yellow) at a brightness slightly above the dark theme background,
%       7.4-8.1:1 with the auto text
%     - ``.widgetYellow``, ``.widgetBlue``, ``.widgetGreen`` - buttons and input fields
%       placed on the matching ``panel...`` color, light ``[1 0.9882 0.9098]``,
%       ``[0.8784 0.9608 1]``, ``[0.9098 0.9608 0.9098]``. Light: paler than the panel;
%       dark: darker than the panel (10.4-10.6:1), following the dark theme, where
%       input fields are darker than the background they sit on
%     - ``.fieldYellow``, ``.fieldBlue`` - input fields on the plain window background
%       tinted to tell two kinds of values apart (e.g. the probability and the Min/Max
%       spinners of the DeepMIB augmentation settings), light ``[0.9804 0.9765 0.8235]``,
%       ``[0.8314 0.9333 1]``. Dark: **lighter** than the background (6.7:1 and 7.6:1),
%       because at the brightness of the theme's own fields (darker than the background)
%       the hue is no longer recognizable
%     - ``.background``       - the theme's own default background of figures, panels
%       and buttons (light ``[0.9608 0.9608 0.9608]``, dark ``[0.1294 0.1294 0.1294]``);
%       used to recognize a default color that was copied from another widget and
%       therefore no longer follows the theme
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
    palette.panelYellow      = [0.28 0.245 0.14];
    palette.panelBlue        = [0.144 0.238 0.3];
    palette.panelGreen       = [0.199 0.27 0.149];
    palette.widgetYellow     = [0.17 0.153 0.102];
    palette.widgetBlue       = [0.11 0.158 0.19];
    palette.widgetGreen      = [0.12 0.17 0.111];
    palette.fieldYellow      = [0.3 0.278 0.135];
    palette.fieldBlue        = [0.17 0.249 0.34];
    palette.background       = [0.1294 0.1294 0.1294];
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
    palette.panelYellow      = [1 0.9804 0.7686];
    palette.panelBlue        = [0.7686 0.902 0.9882];
    palette.panelGreen       = [0.8588 0.9294 0.7804];
    palette.widgetYellow     = [1 0.9882 0.9098];
    palette.widgetBlue       = [0.8784 0.9608 1];
    palette.widgetGreen      = [0.9098 0.9608 0.9098];
    palette.fieldYellow      = [0.9804 0.9765 0.8235];
    palette.fieldBlue        = [0.8314 0.9333 1];
    palette.background       = [0.9608 0.9608 0.9608];
    palette.tableCell        = [1 1 1];
    palette.tableHighlight   = [0.2 0.6 1];
    palette.text             = [0.129 0.129 0.129];
    palette.disabledText     = [0.78 0.78 0.78];
    palette.htmlLink         = [0 0 0.933];
    palette.dimmedText       = [0.4 0.4 0.4];
end

end
