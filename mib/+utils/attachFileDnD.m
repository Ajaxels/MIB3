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
% - browser-renderable file types (JPEG, PNG, …) cannot trigger Chromium's
%   native JPEG decoder, which has a heap-corruption bug in some MATLAB
%   releases when a dropped file is decoded concurrently with MATLAB's own
%   imread; ``webwin.allowNavigation(false/true)`` brackets each drag
%   operation to block the CEF-level navigation before it starts
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
%   See ``development/guides/drag-and-drop.md`` for a full explanation of the pattern.
%

arguments (Input)
    webwin                       handle   % matlab.internal.webwindow or matlab.internal.cef.webwindow
    parentFigure                 matlab.ui.Figure
    callback        (1,1)        function_handle
end

persistent idCounter
if isempty(idCounter); idCounter = 0; end
idCounter = idCounter + 1;
bridgeId  = sprintf('mibDnDBridge_%d',       idCounter);
cancelId  = sprintf('mibDnDBridgeCancel_%d', idCounter);

% hidden bridge button: state lives in UserData so the helper is stateless
% webwin is stored so cancelBridge can reach it without relying on pendingFiles
bridgeButton = uibutton(parentFigure, ...
    'Position', [-100 -100 10 10], ...
    'Text',     bridgeId, ...
    'Tag',      bridgeId, ...
    'UserData', struct('pendingFiles', {{}}, 'callback', callback, 'webwin', webwin));
bridgeButton.ButtonPushedFcn = @(s,e) fireBridge(s);

% hidden cancel button: clicked by ondragleave when drag leaves without drop,
% restores allowNavigation(true).  Kept alive by parentFigure — no need to
% store the handle separately.
cancelButton = uibutton(parentFigure, ...  %#ok<NASGU>
    'Position', [-200 -200 10 10], ...
    'Text',     cancelId, ...
    'Tag',      cancelId);
cancelButton.ButtonPushedFcn = @(s,e) cancelBridge(bridgeButton);

% MATLAB native side: capture filenames on drag-enter, cancel downloads
webwin.enableDragAndDropAll;
webwin.FileDragDropCallback = @(w, f) storePendingFiles(bridgeButton, w, f);
webwin.DownloadCallback     = @(s, e) safeStopDownload(webwin);

% DOM side: suppress defaults; click bridge button on drop; click cancel
% button when drag leaves the window without a drop.
%
% _mibDragCount tracks how many dragenter events are outstanding.  Moving
% the cursor from one child element to another fires both a dragleave and a
% dragenter, so the counter stays > 0 while the drag stays inside the
% document.  A setTimeout(0) in ondragleave defers the zero-check until
% after any paired dragenter has incremented the counter, preventing false
% "drag-left-window" signals during intra-document moves.
webwin.executeJS(sprintf([ ...
    'let _mibDragCount = 0;' ...
    'document.ondragenter = (e) => { _mibDragCount++; e.preventDefault();' ...
    '  if (e.dataTransfer) e.dataTransfer.dropEffect = ''copy''; return false; };' ...
    'document.ondragover  = (e) => { e.preventDefault();' ...
    '  if (e.dataTransfer) e.dataTransfer.dropEffect = ''copy''; return false; };' ...
    'document.ondrop      = (e) => { _mibDragCount = 0; e.preventDefault();' ...
    '  const bd = [...document.querySelectorAll(''button, [role="button"]'')]' ...
    '    .find(x => (x.textContent || '''').trim() === ''%s'');' ...
    '  if (bd) { bd.click(); } return false; };' ...
    'document.ondragleave = (e) => { _mibDragCount--;' ...
    '  setTimeout(() => { if (_mibDragCount <= 0) { _mibDragCount = 0;' ...
    '    const bc = [...document.querySelectorAll(''button, [role="button"]'')]' ...
    '      .find(x => (x.textContent || '''').trim() === ''%s'');' ...
    '    if (bc) { bc.click(); }' ...
    '  } }, 0); return false; };' ...
    ], bridgeId, cancelId));

end

% ---------- helpers (local to this file, state held in button UserData) ----------

function storePendingFiles(btn, webwin, filenames)
    if ~isvalid(btn); return; end
    data = btn.UserData;
    % Block CEF from navigating to the dropped file.  Browser-renderable
    % formats (JPEG, PNG, …) trigger Chromium's native image decoder even
    % when JS preventDefault() is in place; in some MATLAB/CEF versions this
    % decoder corrupts the heap (ntdll.dll STATUS_HEAP_CORRUPTION crash).
    % allowNavigation(false) cancels the navigation at the CEF level before
    % the decoder can run.  Restored in fireBridge (on drop) or cancelBridge
    % (when drag leaves without a drop).
    try; webwin.allowNavigation(false); catch; end
    data.pendingFiles = {webwin, filenames};
    btn.UserData = data;
end

function cancelBridge(btn)
    % Called when drag leaves the window without a drop — restore navigation.
    if ~isvalid(btn); return; end
    data = btn.UserData;
    data.pendingFiles = {};
    btn.UserData = data;
    try; data.webwin.allowNavigation(true); catch; end
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
    % Restore navigation after the callback finishes loading the file.
    % Keeping it disabled during loadImages ensures no concurrent CEF decode.
    try; params{1}.allowNavigation(true); catch; end
end

function safeStopDownload(webwin)
    try
        webwin.stopDownload();
    catch
    end
end
