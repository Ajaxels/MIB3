function bridgeButton = attachFileDnD(webwin, parentFigure, callback)
% ATTACHFILEDND - Attach OS-level file drag-and-drop to a MATLAB webwindow.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      bridgeButton = attachFileDnD(webwin, parentFigure, callback)
%
% Wraps MATLAB's native ``FileDragDropCallback`` in a JS bridge so that:
%
% - file opening is deferred until the actual DOM drop (mouse release),
%   not the native drag-enter event
% - Chromium's default navigate / Save-As / red-no-parking-cursor
%   behaviours are all suppressed
%
% Input Arguments:
%   - **webwin** — handle to ``matlab.internal.webwindow`` (AppContainer) or
%     ``matlab.internal.cef.webwindow`` (standalone mlapp) hosting the app
%   - **parentFigure** — a ``uifigure`` rendered inside webwin's Chromium document
%     (the hidden bridge uibutton becomes its child)
%   - **callback** — function handle invoked on drop as ``callback(params)``
%     where ``params = {webwin, filenames}`` — the same shape the native
%     ``FileDragDropCallback`` produces.  Wrap method calls in an explicit
%     anonymous function, e.g. ``@(params) obj.myController.dragNdrop_Callback(params)``
%
% Output Arguments:
%   - **bridgeButton** — handle to the hidden uibutton; deleting it detaches the
%     MATLAB side of the bridge (the JS handlers remain until the webwindow is
%     reloaded, but they become no-ops)
%
% Usage:
%
%   **Example 1** — attach drag-and-drop to the selection panel
%
%   .. code-block:: matlab
%
%      obj.controller.dndBridgeButton = utils.attachFileDnD( ...
%          obj.controller.mibWebWindow, ...
%          obj.handles.panels.selectionPanel.Figure, ...
%          @(params) obj.controller.dragNdrop_Callback(params));
%
%   See ``development/drag-and-drop.md`` for a full explanation of the pattern.
%

arguments (Input)
    webwin                       handle   % matlab.internal.webwindow or matlab.internal.cef.webwindow
    parentFigure                 matlab.ui.Figure
    callback        (1,1)        function_handle
end

persistent idCounter
if isempty(idCounter); idCounter = 0; end
idCounter = idCounter + 1;
bridgeId = sprintf('mibDnDBridge_%d', idCounter);

% hidden bridge button: state lives in UserData so the helper is stateless
bridgeButton = uibutton(parentFigure, ...
    'Position', [-100 -100 10 10], ...
    'Text',     bridgeId, ...
    'Tag',      bridgeId, ...
    'UserData', struct('pendingFiles', {{}}, 'callback', callback));
bridgeButton.ButtonPushedFcn = @(s,e) fireBridge(s);

% MATLAB native side: capture filenames on drag-enter, cancel downloads
webwin.enableDragAndDropAll;
webwin.FileDragDropCallback = @(w, f) storePendingFiles(bridgeButton, w, f);
webwin.DownloadCallback     = @(s, e) safeStopDownload(webwin);

% DOM side: suppress defaults, click the bridge button on real drop
webwin.executeJS(sprintf([ ...
    'document.ondragenter = (e) => { e.preventDefault();' ...
    '  if (e.dataTransfer) e.dataTransfer.dropEffect = ''copy''; return false; };' ...
    'document.ondragover  = (e) => { e.preventDefault();' ...
    '  if (e.dataTransfer) e.dataTransfer.dropEffect = ''copy''; return false; };' ...
    'document.ondrop      = (e) => { e.preventDefault();' ...
    '  const b = [...document.querySelectorAll(''button, [role="button"]'')]' ...
    '    .find(x => (x.textContent || '''').trim() === ''%s'');' ...
    '  if (b) { b.click(); }' ...
    '  return false; };'], bridgeId));

end

% ---------- helpers (local to this file, state held in button UserData) ----------

function storePendingFiles(btn, webwin, filenames)
    if ~isvalid(btn); return; end
    data = btn.UserData;
    data.pendingFiles = {webwin, filenames};
    btn.UserData = data;
end

function fireBridge(btn)
    if ~isvalid(btn); return; end
    data = btn.UserData;
    if isempty(data.pendingFiles); return; end
    params = data.pendingFiles;
    data.pendingFiles = {};
    btn.UserData = data;
    try
        data.callback(params);
    catch err
        fprintf(2, 'utils.attachFileDnD: callback failed: %s\n', err.message);
    end
end

function safeStopDownload(webwin)
    try
        webwin.stopDownload();
    catch
    end
end
