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
% mib.helsinki.fi otherwise.  Callers spell the address for the source tree,
% where ``docs`` is a sibling of ``mib``; when nothing is found there the
% address is rebuilt against ``utils.getDocsPath()``, which is where the
% compiled standalone keeps its copy.  The online address remains the normal
% outcome for a checkout with no built documentation, rather than an error
% case.
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
    helpFilePath = relocateToDocsRoot(helpFilePath);
end

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

function relocatedPath = relocateToDocsRoot(helpFilePath)
% take the part of the address below docs/html and hang it under the docs
% root that this installation actually has; returns the address unchanged
% when it was not built from a docs/html folder in the first place
marker = [filesep 'docs' filesep 'html' filesep];
markerPosition = strfind(helpFilePath, marker);
if isempty(markerPosition)
    relocatedPath = helpFilePath;
    return;
end

pageRelativePath = helpFilePath(markerPosition(end)+numel(marker):end);
relocatedPath = fullfile(utils.getDocsPath(), pageRelativePath);
end
