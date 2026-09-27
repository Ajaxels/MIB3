function success = setMibTheme(themeName)
% SETMIBTHEME - switch MIB to the light or dark theme, or back to the MATLAB theme.
%
% Syntax:
%   .. code-block:: matlab
%
%      success = utils.setMibTheme(themeName)
%
% The theme is set through the session-only ``TemporaryValue`` of the MATLAB
% setting ``settings().matlab.appearance.MATLABTheme``. This is the only route
% that also switches the ``AppContainer`` chrome (ribbon, panel title bars,
% document area); forcing a theme per figure with ``theme(fig, ...)`` leaves
% the ribbon in the MATLAB theme. Every figure receives the change, so each
% ``ThemeChangedFcn`` of MIB repaints its explicit colors.
%
% Side effects:
%
%   - the setting is global, so while MIB runs from MATLAB the MATLAB desktop and
%     all other figures switch as well
%   - ``TemporaryValue`` lasts for the MATLAB session only and never touches the
%     saved ``PersonalValue`` of the user; ``'System'`` removes it, returning to
%     whatever the user set in MATLAB (which may itself be MATLAB's own
%     ``'System'``, i.e. follow the operating system).
%     ``controllers.MibController.exitProgram`` removes it on exit.
%
% Releases without the setting (before R2025a), and runtimes where the
% ``settings`` API is not available, return ``false`` without an error.
% Investigation and the rejected per-figure route:
% ``development/notes/dark_light_scheme.md``.
%
% Input Arguments:
%   - **themeName** - [char] ``'System'`` (follow the MATLAB theme), ``'Light'``
%     or ``'Dark'``; case-insensitive
%
% Output Arguments:
%   - **success** - [logical] ``true`` when the setting was applied
%
% Usage:
%   **Example 1** - force the dark theme, then return to the MATLAB theme
%
%   .. code-block:: matlab
%
%      utils.setMibTheme('Dark');
%      utils.setMibTheme('System');
%
% See also: utils.themeColors, utils.applyThemeColors

arguments (Input)
    themeName {mustBeTextScalar}
end

success = false;
themeName = validatestring(themeName, {'System', 'Light', 'Dark'});

try
    s = settings;
    if ~hasGroup(s.matlab, 'appearance') || ~hasSetting(s.matlab.appearance, 'MATLABTheme')
        return;
    end
    themeSetting = s.matlab.appearance.MATLABTheme;
    if strcmp(themeName, 'System')
        if hasTemporaryValue(themeSetting)
            clearTemporaryValue(themeSetting);
        end
    else
        themeSetting.TemporaryValue = themeName;
    end
    success = true;
catch err
    warning('MIB:setMibTheme', 'The MIB theme could not be set to %s: %s', themeName, err.message);
end

end
