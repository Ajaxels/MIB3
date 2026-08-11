function openHelpPage(helpFilePath, onlineUrl)
% OPENHELPPAGE - Show a documentation page in the system web browser.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      utils.openHelpPage(helpFilePath, onlineUrl)
%
% Opens the local copy of a help page when it is present, and the page on
% mib.helsinki.fi otherwise.  The local copy is missing in the compiled
% standalone, which ships no ``docs`` folder, so the online address is the
% normal path there rather than an error case.
%
% Local pages are launched through the shell rather than through
% ``web(..., '-browser')``.  On Windows ``web`` reports success while the
% browser never raises a window for some ``file:///`` addresses, so the page
% silently fails to appear; handing the address to the shell lets the default
% browser open it the same way a double-click in Explorer would.  The online
% branch keeps using ``web``, which is reliable for ``http`` addresses and
% works on every platform.
%
% Input Arguments:
%   - **helpFilePath** - [char] full path to the local ``.html`` page, as built with ``fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', ...)``
%   - **onlineUrl** - [char] address of the same page on mib.helsinki.fi, used when the local copy is absent
%
% Usage:
%
%   **Example 1** - a help button callback
%
%   .. code-block:: matlab
%
%      helpFilePath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', ...
%          'user-interface', 'ribbon', 'dataset', 'dataset-alignment.html');
%      utils.openHelpPage(helpFilePath, ...
%          'http://mib.helsinki.fi/help/main3/user-interface/ribbon/dataset/dataset-alignment.html');
%

if ~isfile(helpFilePath)
    web(onlineUrl, '-browser');
    return;
end

pageUrl = ['file:///' strrep(helpFilePath, '\', '/')];

if ispc
    % "" is the title argument of start; without it start treats a quoted
    % address as the window title and opens a console instead of the page
    status = system(sprintf('start "" "%s"', pageUrl));
elseif ismac
    status = system(sprintf('open "%s"', pageUrl));
else
    status = system(sprintf('xdg-open "%s"', pageUrl));
end

% falling back to web keeps the page reachable if no shell handler is
% registered, which is the usual case on a bare Linux session
if status ~= 0
    web(pageUrl, '-browser');
end
end
