classdef DownloadProgressMonitor < matlab.net.http.ProgressMonitor
    % DOWNLOADPROGRESSMONITOR - Cancelable HTTP download that reports to a uiprogressdlg.
    %
    % Use it instead of ``webread``, ``websave`` and ``unzip(url)`` whenever a
    % download can take more than a few seconds. Those functions block until the
    % whole file has arrived, so the progress bar cannot move and a Cancel button
    % can only act after the transfer is over. ``core.DownloadProgressMonitor.download``
    % shows the received / total MB and the speed in the dialog and stops the
    % transfer as soon as the user presses Cancel.
    %
    % **What the caller gets back**
    %
    % - ``[data, cancelled] = download(...)``
    % - success: ``cancelled = false``; ``data`` holds the bytes (in-memory mode)
    %   or the file exists (file mode)
    % - user pressed Cancel: ``cancelled = true``, **no error**; ``data = []`` and
    %   a partly written file has already been deleted
    % - the download failed (no connection, HTTP 404, ...): an **error** is
    %   thrown, as ``webread`` would; a partly written file has already been
    %   deleted. With several addresses, the error comes from the last one.
    %
    % **How it works**
    %
    % 1. ``download`` sends the request with ``matlab.net.http`` and passes
    %    ``HTTPOptions.ProgressMonitorFcn``, so MATLAB creates one instance of
    %    this class for the transfer.
    % 2. MATLAB sets the ``Value`` property (bytes received so far) on every
    %    received network chunk, about 100 times per second; ``set.Value`` calls
    %    ``update``.
    % 3. ``update`` checks ``CancelRequested`` of the dialog on every call. When
    %    set, it raises an ordinary error, which stops the transfer inside
    %    ``send()``; ``download`` catches it and returns ``cancelled = true``.
    % 4. Otherwise, at most twice per second, ``update`` writes the size and the
    %    speed (averaged over the last 3 s) into the dialog.
    % 5. With a list of addresses, ``download`` tries them in order: it moves on
    %    to the next address only after an error. A cancel returns at once and
    %    never starts the next address.
    %
    % Usage:
    %   **Example 1** - download a file to disk, with a mirror address and full
    %   handling of all three outcomes (this is the pattern to copy)
    %
    %   .. code-block:: matlab
    %
    %      % 1. the dialog must be cancelable, otherwise the user cannot stop the download
    %      wb = uiprogressdlg(obj.mibModel.getProgressBarParent(), ...
    %          'Title', 'Downloading checkpoint', 'Message', 'Connecting...', ...
    %          'Indeterminate', 'on', 'Cancelable', 'on');
    %      links = {'https://main.server/sam_vit_b.pth', ...   % tried first
    %               'http://mirror.server/sam_vit_b.pth'};     % tried only if the first fails
    %      targetFilename = fullfile(destinationDir, 'sam_vit_b.pth');
    %      try
    %          [~, cancelled] = core.DownloadProgressMonitor.download(links, wb, ...
    %              'Downloading SAM checkpoint (1/2)', targetFilename);
    %      catch err
    %          % 2. every address failed; nothing is left at targetFilename
    %          delete(wb);
    %          utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), err, 'Download failed');
    %          return;
    %      end
    %      if cancelled
    %          % 3. the user pressed Cancel; nothing is left at targetFilename
    %          delete(wb);
    %          return;
    %      end
    %      % 4. success: targetFilename is complete
    %      delete(wb);
    %
    %   **Example 2** - download a zip and unzip it, so a cancel leaves nothing
    %   in the destination
    %
    %   .. code-block:: matlab
    %
    %      zipFilename = [tempname '.zip'];     % temporary file, not the destination
    %      [~, cancelled] = core.DownloadProgressMonitor.download(url, wb, 'Downloading project...', zipFilename);
    %      if cancelled; delete(wb); return; end
    %      wb.Cancelable = 'off';               % unzip cannot be interrupted
    %      wb.Indeterminate = 'on';             % and reports no progress
    %      wb.Message = 'Unzipping...';
    %      unzip(zipFilename, destinationDir);
    %      delete(zipFilename);
    %
    %   **Example 3** - download raw bytes into memory (replaces
    %   ``webread(url, weboptions('ContentType', 'raw'))``)
    %
    %   .. code-block:: matlab
    %
    %      [bytes, cancelled] = core.DownloadProgressMonitor.download(url, wb, 'Downloading image...');
    %      if cancelled; delete(wb); return; end
    %      vol = reshape(bytes, [height, width, depth]);    % bytes is a uint8 column
    %
    %   **Example 4** - no dialog (batch mode): no progress and no cancel, the
    %   rest behaves the same
    %
    %   .. code-block:: matlab
    %
    %      core.DownloadProgressMonitor.download(url, [], '', targetFilename);
    %
    % .. note::
    %    Three behaviours of ``matlab.net.http`` that this class works around,
    %    each found the hard way (details: ``development/notes/matlab_http_downloads.md``):
    %
    %    - ``ProgressMonitor.CancelFcn`` acts as Ctrl+C: an interrupt that
    %      ``try/catch`` cannot intercept and that unwinds the whole GUI callback.
    %      An ordinary error is raised instead.
    %    - ``Interval`` only delays the first ``Value`` update; later updates come
    %      on every network chunk. The dialog is therefore refreshed on a timer of
    %      its own and the speed is averaged over a window.
    %    - ``HTTPOptions.ConvertResponse = false`` makes ``send()`` bypass a
    %      ``FileConsumer``: no file is written. It is set only for in-memory
    %      downloads.

    % Updates
    % 11.10.2026, IB created to make the Example datasets import cancelable

    properties
        % [matlab.net.http.MessageType] direction of the transfer being reported; set by MATLAB
        Direction matlab.net.http.MessageType
        % [uint64] number of bytes transferred so far; set by MATLAB on every received chunk
        Value uint64
    end

    properties (Access = private)
        % handle to the uiprogressdlg that shows the progress, may be empty
        progressDialog
        % [char] first line of the dialog message, followed by the transferred size
        messagePrefix
        % tic taken at the first update of the response body; empty before
        transferTic
        % [double] seconds since transferTic of the last dialog refresh
        lastRefreshTime = -Inf
        % [double vectors] time (s) and bytes received at the refreshes of the last
        % speedWindow seconds; the speed is measured across this window
        historyTime = []
        historyBytes = []
    end

    properties (Constant, Access = private)
        % [double] seconds between dialog refreshes. MATLAB calls the monitor on every
        % received network chunk (Interval only delays the first call): measured ~100
        % calls per second in bursts of a few ms, too fast to read and costly to redraw
        refreshPeriod = 0.5
        % [double] seconds of history the speed is averaged over; the speed is shown
        % once at least 1 s of history exists
        speedWindow = 3
    end

    methods
        function obj = DownloadProgressMonitor(progressDialog, messagePrefix)
            % DOWNLOADPROGRESSMONITOR - constructor, called by MATLAB through HTTPOptions.ProgressMonitorFcn.
            %
            % Input Arguments:
            %   - **progressDialog** - handle to a ``uiprogressdlg``
            %   - **messagePrefix** - [char] first line of the dialog message
            %
            obj.progressDialog = progressDialog;
            obj.messagePrefix = messagePrefix;
            obj.Interval = 0.2;     % seconds before the first Value update; later updates are not paced by it
        end

        function set.Value(obj, value)
            obj.Value = value;
            obj.update();
        end

        function done(~)
            % DONE - called by MATLAB when the transfer has finished; the dialog belongs to the caller
        end
    end

    methods (Access = private)
        function update(obj)
            % UPDATE - report the progress of the response body and abort when Cancel was pressed
            if isempty(obj.progressDialog) || ~isvalid(obj.progressDialog); return; end
            % let the dialog process a pending Cancel click before it is read
            drawnow limitrate;
            if obj.progressDialog.CancelRequested
                % Abort with an ordinary error: send() passes it on to download(), which
                % catches it. The documented obj.CancelFcn() is NOT used - MATLAB turns it
                % into a Ctrl+C interrupt ("Operation terminated by user") that try/catch
                % cannot intercept, so it would unwind the whole GUI callback.
                error('MIB:DownloadProgressMonitor:cancelled', 'Download cancelled by user');
            end
            % MATLAB may set Value to empty when a transfer ends
            if obj.Direction ~= matlab.net.http.MessageType.Response || isempty(obj.Value); return; end

            receivedBytes = double(obj.Value);
            if isempty(obj.transferTic)
                % first call for the response body: its byte count is the speed baseline
                obj.transferTic = tic;
                obj.historyTime = 0;
                obj.historyBytes = receivedBytes;
            end
            isComplete = ~isempty(obj.Max) && obj.Max > 0 && receivedBytes >= double(obj.Max);
            timeNow = toc(obj.transferTic);
            if timeNow - obj.lastRefreshTime < obj.refreshPeriod && ~isComplete; return; end
            obj.lastRefreshTime = timeNow;

            % speed across a sliding window of refreshes: per-chunk rates are meaningless
            % because chunks arrive in bursts a few ms apart
            obj.historyTime(end+1) = timeNow;
            obj.historyBytes(end+1) = receivedBytes;
            keep = obj.historyTime >= timeNow - obj.speedWindow;
            firstKept = find(keep, 1);  % never empty: the sample just added is kept
            if firstKept > 1; keep(firstKept - 1) = true; end   % one older sample, so the window is fully spanned
            obj.historyTime = obj.historyTime(keep);
            obj.historyBytes = obj.historyBytes(keep);
            span = timeNow - obj.historyTime(1);
            speedText = '';
            if span >= 1
                bytesPerSecond = (receivedBytes - obj.historyBytes(1)) / span;
                if bytesPerSecond >= 2^20
                    speedText = sprintf(', %.1f MB/s', bytesPerSecond / 2^20);
                else
                    speedText = sprintf(', %.0f KB/s', bytesPerSecond / 2^10);
                end
            end

            receivedMB = receivedBytes / 2^20;
            if isempty(obj.Max) || obj.Max == 0
                % the server sent no Content-Length: the fraction is unknown
                obj.progressDialog.Message = sprintf('%s\n%.1f MB%s', obj.messagePrefix, receivedMB, speedText);
            else
                obj.progressDialog.Indeterminate = 'off';
                obj.progressDialog.Value = min(receivedBytes / double(obj.Max), 1);
                obj.progressDialog.Message = sprintf('%s\n%.1f / %.1f MB%s', obj.messagePrefix, ...
                    receivedMB, double(obj.Max) / 2^20, speedText);
            end
        end
    end

    methods (Static)
        function [data, cancelled] = download(url, progressDialog, messagePrefix, filename)
            % DOWNLOAD - download a URL into memory or to a file, cancelable from the progress dialog.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       [data, cancelled] = core.DownloadProgressMonitor.download(url, progressDialog)
            %       [data, cancelled] = core.DownloadProgressMonitor.download(url, progressDialog, messagePrefix)
            %       [~, cancelled] = core.DownloadProgressMonitor.download(url, progressDialog, messagePrefix, filename)
            %       [~, cancelled] = core.DownloadProgressMonitor.download({url, mirrorUrl}, progressDialog, messagePrefix, filename)
            %
            % Input Arguments:
            %   - **url** - [char | string | cell array of char] address of the file, or
            %     several addresses of the same file in the order to try them
            %     (main server first, then mirrors)
            %   - **progressDialog** - handle to a ``uiprogressdlg`` created with
            %     ``'Cancelable', 'on'``; ``[]`` downloads without progress or cancel
            %   - **messagePrefix** - *(optional)* [char] first line of the dialog message;
            %     default ``'Downloading...'``. When a later address is tried,
            %     ``(address N of M)`` is appended to it.
            %   - **filename** - *(optional)* [char] full path of the file to write; when
            %     omitted or empty, the bytes are returned in ``data``
            %
            % Output Arguments:
            %   - **data** - [uint8 column] downloaded bytes, the same as
            %     ``webread(url, weboptions('ContentType', 'raw'))``; ``[]`` when saved
            %     to ``filename`` or when cancelled
            %   - **cancelled** - [logical] true when the user pressed Cancel. No error is
            %     thrown, nothing is returned and a partly written ``filename`` is deleted.
            %
            % .. note::
            %    A transfer error other than a cancel (no connection, HTTP error status,
            %    timeout) is thrown, as ``webread`` would. With several addresses, the
            %    next one is tried after an error and only the error of the last one is
            %    thrown; a cancel returns at once and never starts the next address.
            %    On any failure or cancel a partly written ``filename`` is deleted, so
            %    writing straight to the final name is safe for callers that only test
            %    ``isfile`` before reuse.

            if nargin < 3 || isempty(messagePrefix); messagePrefix = 'Downloading...'; end
            if nargin < 4; filename = ''; end
            urls = cellstr(url);
            for urlIndex = 1:numel(urls)
                prefix = messagePrefix;
                if urlIndex > 1; prefix = sprintf('%s (address %d of %d)', messagePrefix, urlIndex, numel(urls)); end
                try
                    [data, cancelled] = core.DownloadProgressMonitor.downloadOneUrl(urls{urlIndex}, ...
                        progressDialog, prefix, filename);
                    return;     % success or cancel: either way the next address is not tried
                catch err
                    % this address failed and its partial file is already deleted;
                    % try the next one, or report the failure when none is left
                    if urlIndex == numel(urls); rethrow(err); end
                end
            end
        end
    end

    methods (Static, Access = private)
        function [data, cancelled] = downloadOneUrl(url, progressDialog, messagePrefix, filename)
            % DOWNLOADONEURL - download a single address; see download for the arguments and contract.
            data = [];
            cancelled = false;

            httpOptions = matlab.net.http.HTTPOptions('ConnectTimeout', 30);
            if ~isempty(progressDialog)
                % name the file at once: the first progress update comes only after the
                % connection is made; the bar stays indeterminate until the size is known
                progressDialog.Message = messagePrefix;
                progressDialog.Indeterminate = 'on';
                httpOptions.ProgressMonitorFcn = @() core.DownloadProgressMonitor(progressDialog, messagePrefix);
                httpOptions.UseProgressMonitor = true;
            end
            if isempty(filename)
                % keep the body as raw uint8 bytes whatever Content-Type the server reports
                % (mib.helsinki.fi sends none for .raw files)
                httpOptions.ConvertResponse = false;
                consumerArgs = {};
            else
                % ConvertResponse must stay true here: false makes send() bypass the
                % consumer, so the bytes come back in memory and no file is written
                consumerArgs = {matlab.net.http.io.FileConsumer(filename)};
            end

            try
                response = matlab.net.http.RequestMessage().send(url, httpOptions, consumerArgs{:});
            catch err
                % never leave a truncated file: callers often test only isfile() before reuse
                if ~isempty(filename) && isfile(filename); delete(filename); end
                if ~isempty(progressDialog) && isvalid(progressDialog) && progressDialog.CancelRequested
                    cancelled = true;
                    return;
                end
                rethrow(err);
            end
            % a cancel can also end the transfer without an exception
            if ~isempty(progressDialog) && isvalid(progressDialog) && progressDialog.CancelRequested
                cancelled = true;
                if ~isempty(filename) && isfile(filename); delete(filename); end
                return;
            end
            if response.StatusCode ~= matlab.net.http.StatusCode.OK
                if ~isempty(filename) && isfile(filename); delete(filename); end
                error('MIB:DownloadProgressMonitor:httpStatus', 'Download of %s failed: %s (%d)', ...
                    url, char(response.StatusLine.ReasonPhrase), double(response.StatusCode));
            end
            if isempty(filename)
                data = response.Body.Data;
            elseif ~isfile(filename)
                error('MIB:DownloadProgressMonitor:noFile', 'Download of %s reported success but %s was not written', ...
                    url, filename);
            end
        end
    end
end
