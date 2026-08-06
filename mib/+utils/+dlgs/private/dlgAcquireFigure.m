function [fig, isCached] = dlgAcquireFigure(tag, dlgTitle, mibDir)
% DLGACQUIREFIGURE - Reuse or create the hidden uifigure shell for a dialog.
%
% Syntax:
%   .. code-block:: matlab
%
%      [fig, isCached] = dlgAcquireFigure(tag, dlgTitle, mibDir)
%
% Keeps one cached figure per dialog tag to avoid the ~200-400 ms uifigure
% creation cost on every call. When the cached figure is currently in use
% (visible - e.g. a nested dialog of the same type), a temporary figure is
% created WITHOUT touching the cache and ``isCached`` returns false; the caller
% must delete such a figure on close instead of hiding it, otherwise it leaks.
%
% Input Arguments:
%   - **tag** - [char] dialog identity, e.g. ``'inputUniversalDlg'``; also set as ``fig.Tag``
%   - **dlgTitle** - [char] window title
%   - **mibDir** - [char] MIB installation folder (for the window icon)
%
% Output Arguments:
%   - **fig** - [handle] hidden uifigure with stale children/callbacks cleared
%   - **isCached** - [logical] ``true`` when fig is the cached shell (hide on close);
%     ``false`` when it is a temporary instance (delete on close)

persistent figureCache   % dictionary: tag -> {uifigure handle}

if isempty(figureCache)
    figureCache = configureDictionary("string", "cell");
end
key = string(tag);

fig = [];
cacheBusy = false;
if isKey(figureCache, key)
    cached = figureCache{key};
    if ~isempty(cached) && isvalid(cached)
        if strcmp(cached.Visible, 'off')
            % Reuse: strip previous content and stale callbacks
            fig = cached;
            delete(fig.Children);
            fig.Name = dlgTitle;
            fig.KeyPressFcn = '';
            fig.WindowKeyPressFcn = '';
            fig.CloseRequestFcn = 'closereq';
        else
            cacheBusy = true;   % cached shell is showing another dialog right now
        end
    end
end

isCached = true;
if isempty(fig)
    fig = uifigure('Name', dlgTitle, 'Visible', 'off');
    fig.Tag = tag;
    fig.AutoResizeChildren = 'off';
    iconFile = fullfile(mibDir, 'assets', 'icons', 'mib_icon_16px.png');
    if exist(iconFile, 'file'); fig.Icon = iconFile; end
    if cacheBusy
        isCached = false;   % temporary second instance; caller deletes it on close
    else
        figureCache(key) = {fig};
    end
end
end
