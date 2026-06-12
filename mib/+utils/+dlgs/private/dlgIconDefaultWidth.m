function iconWidth = dlgIconDefaultWidth(iconName)
% DLGICONDEFAULTWIDTH - Default icon column width in pixels for a dialog icon id.
%
% Syntax:
%   .. code-block:: matlab
%
%      iconWidth = dlgIconDefaultWidth(iconName)
%
% 48 px for the standard 48px icons, 220 px for the large special puffins,
% 96 px for all other puffin icons and for unknown ids (the fallback icon is
% a 96 px puffin).
%
% Input Arguments:
%   - **iconName** — [char] icon identifier, e.g. ``'puffin_question'``, ``'warning_48px'``
%
% Output Arguments:
%   - **iconWidth** — [numeric] default icon column width in pixels (48, 96, or 220)

switch iconName
    case {'warning_48px', 'question_48px'}
        iconWidth = 48;
    case {'celebrate', 'call4help'}
        iconWidth = 220;
    otherwise
        iconWidth = 96;
end
end
