classdef PoolWaitbar < handle
    % POOLWAITBAR - Thread-safe progress dialog for parallel loops (parfor / spmd / parfeval).
    %
    % Uses parallel.pool.DataQueue + afterEach to route increment signals
    % from worker threads back to the client (main) thread, where the
    % uiprogressdlg lives.  This makes UI updates safe inside parfor loops
    % without any explicit locking.
    %
    % MIB3 note:  Only uiprogressdlg is supported (the classic figure-based
    % waitbar is not used in MIB3).  Always supply either a UIFigure parent
    % handle or an already-open uiprogressdlg handle.
    %
    % Requires: Parallel Computing Toolbox (parallel.pool.DataQueue).
    %
    % Usage:
    %   **Basic** examples:
    %   **Example 1** — PoolWaitbar in an additional MIB child window
    %
    %   .. code-block:: matlab
    %
    %
    %     % Use with a child window controller; parent = obj.view.gui (AppDesigner dialog)
    %     pwb = core.PoolWaitbar(maxValue, 'Please wait...', obj.view.gui, 'waitbar title', true);
    %     for i = 1:maxValue
    %         % ... process something ...
    %           if ~isempty(pwb)
    %               if pwb.getCancelState(); pwb.deletePoolWaitbar(); return; end
    %               pwb.increment();
    %           end
    %     end
    %     pwb.deletePoolWaitbar();
    %
    %
    %   **Example 2** — PoolWaitbar in a docked panel of MIB
    %
    %   .. code-block:: matlab
    %
    %
    %     % Use with docked panels in the main MIB window; parent = obj.gui.Parent (container)
    %     pwb = core.PoolWaitbar(nItems, 'Processing...', obj.view.gui, 'My Task', true);
    %     for ii = 1:nItems
    %         % ... process item ...
    %           if ~isempty(pwb)
    %               if pwb.getCancelState(); pwb.deletePoolWaitbar(); return; end
    %               pwb.increment();
    %           end
    %     end
    %     pwb.deletePoolWaitbar();
    %
    %
    %   **Example 3** — Parallel loop with batch cancel polling
    %
    %   .. code-block:: matlab
    %
    %
    %     % Cancelable parfor with batching (cancel polling between batches only)
    %     pwb = core.PoolWaitbar(n, 'Processing...', obj.view.gui, 'Job', true);
    %     pwb.setIncrement(10);         % update every 10 steps
    %     for batchStart = 1:10:n
    %         if pwb.getCancelState(); pwb.deletePoolWaitbar(); return; end
    %         batchEnd = min(batchStart+9, n);
    %         parfor ii = batchStart:batchEnd
    %             pwb.increment();
    %         end
    %     end
    %     pwb.deletePoolWaitbar();
    %

    % Updates
    % 24.03.2026 - created for MIB3; removed classic waitbar support,
    %              always uses uiprogressdlg

    %% ----------------------------------------------------------------
    %  Immutable DataQueue – accessible from worker threads
    %% ----------------------------------------------------------------
    properties (SetAccess = immutable, GetAccess = private)
        Queue       % parallel.pool.DataQueue for thread-safe send/receive
    end

    %% ----------------------------------------------------------------
    %  Transient state – only touched on the main thread
    %% ----------------------------------------------------------------
    properties (Access = private, Transient)
        N           % double, total number of expected iterations
        ClientHandle    % matlab.ui.dialog.ProgressDialog, the uiprogressdlg
        Count = 0   % double, iterations completed so far
        Increment = 1   % double, step size added per increment() call
    end

    properties (SetAccess = immutable, GetAccess = private, Transient)
        Listener = []   % event.listener returned by afterEach()
    end

    %% ----------------------------------------------------------------
    %  Private helpers
    %% ----------------------------------------------------------------
    methods (Access = private)
        function localIncrement(obj)
            % LOCALINCREMENT - Advance Count and refresh the dialog.
            %
            % Syntax:
            %   function localIncrement(obj)
            %
            % Called on the main thread via afterEach(Queue, ...) each
            % time a worker calls increment().
            obj.Count = obj.Count + obj.Increment;
            if isvalid(obj.ClientHandle)
                obj.ClientHandle.Value = min(obj.Count / obj.N, 1);
            end
        end
    end

    %% ----------------------------------------------------------------
    %  Public API
    %% ----------------------------------------------------------------
    methods
        function obj = PoolWaitbar(N, message, parentOrHandle, WindowName, Cancelable, Indeterminate)
            % POOLWAITBAR - Construct a thread-safe progress dialog for parallel loops.
            %
            % Syntax:
            %   function obj = PoolWaitbar(N, message, parentOrHandle, WindowName, Cancelable)
            %
            % Input Arguments:
            %   - **N** — double, total number of iterations expected
            %   - **message** — *(optional)* char, text shown inside the dialog;
            %     default 'Please wait...'
            %   - **parentOrHandle** — *(optional)* either:
            %
            %     - ``matlab.ui.Figure`` — parent UIFigure; a new ``uiprogressdlg``
            %       is created automatically
            %     - ``matlab.ui.dialog.ProgressDialog`` — existing dialog to
            %       reuse (its Value is reset to 0 and Message/Title updated)
            %     - ``[]`` — error; a parent is required in MIB3
            %   - **WindowName** — *(optional)* char, dialog title; default ''
            %   - **Cancelable** — *(optional)* logical, add Cancel button;
            %     default false.  Only used when parentOrHandle is a Figure.
            %   - **Indeterminate** - *(optional)* logical, default=false; use the Indeterminate mode
            %
            % Output Arguments:
            %   - **obj** — core.PoolWaitbar instance
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     pwb = core.PoolWaitbar(200, 'Eroding...', obj.mibModel.mibGUI, 'Erode');
            %
            %   **Example 2** — Reuse an open dialog
            %
            %   .. code-block:: matlab
            %
            %
            %     % Reuse an open dialog
            %     pwb = core.PoolWaitbar(200, 'Phase 2', existingWb);
            %

            if nargin < 6; Indeterminate = false; end
            if nargin < 5; Cancelable = false; end
            if nargin < 4; WindowName = ''; end
            if nargin < 3; parentOrHandle = []; end
            if nargin < 2; message = 'Please wait...'; end

            obj.N = N;

            if isa(parentOrHandle, 'matlab.ui.dialog.ProgressDialog')
                % Reuse an existing uiprogressdlg
                obj.ClientHandle = parentOrHandle;
                if ~isempty(message);    obj.ClientHandle.Message = message; end
                if ~isempty(WindowName); obj.ClientHandle.Title   = WindowName; end
                obj.ClientHandle.Value = 0;

            elseif isa(parentOrHandle, 'matlab.ui.Figure') || isa(parentOrHandle, 'matlab.ui.container.internal.AppContainer')
                % Create a new deterministic uiprogressdlg
                obj.ClientHandle = uiprogressdlg(parentOrHandle, ...
                    'Message',    message, ...
                    'Title',      WindowName, ...
                    'Value',      0, ...
                    'Cancelable', Cancelable, ...
                    'Indeterminate', Indeterminate);

            else
                error('core:PoolWaitbar:noParent', ...
                    ['PoolWaitbar requires either a UIFigure parent handle or ' ...
                    'an existing uiprogressdlg handle as the third argument.']);
            end

            obj.Queue    = parallel.pool.DataQueue;
            obj.Listener = afterEach(obj.Queue, @(~) localIncrement(obj));
        end

        % ----------------------------------------------------------
        function increment(obj)
            % INCREMENT - Signal one step of progress from any thread (main or worker).
            %
            % Syntax:
            %   function increment(obj)
            %
            % This is the only method that is safe to call inside a parfor
            % body.  It uses send() on the immutable DataQueue; the actual
            % UI update happens asynchronously on the main thread.
            %
            % Input Arguments:
            %   (none)
            %
            % Output Arguments:
            %   (none)
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     parfor ii = 1:n; pwb.increment(); end
            %

            send(obj.Queue, true);
        end

        % ----------------------------------------------------------
        function setIncrement(obj, increment)
            % SETINCREMENT - Set the step size added to Count on each increment() call.
            %
            % Syntax:
            %   function setIncrement(obj, increment)
            %
            % Use this when the caller wants to call increment() less
            % frequently (e.g., every 10 iterations to reduce overhead).
            %
            % Input Arguments:
            %   - **increment** — double, new step size; default 1
            %
            % Output Arguments:
            %   (none)
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     pwb.setIncrement(10);% advance bar by 10% each call
            %

            obj.Increment = increment;
        end

        % ----------------------------------------------------------
        function setCurrentIteration(obj, count)
            % SETCURRENTITERATION - Manually set the completed-iteration counter.
            %
            % Syntax:
            %   function setCurrentIteration(obj, count)
            %
            % Useful when restarting progress tracking mid-run or when
            % stitching two sequential phases that share one dialog.
            %
            % Input Arguments:
            %   - **count** — double, new value for the internal counter
            %
            % Output Arguments:
            %   (none)
            %

            obj.Count = count;
        end

        % ----------------------------------------------------------
        function count = getCurrentIteration(obj)
            % GETCURRENTITERATION - Return the number of iterations completed so far.
            %
            % Syntax:
            %   function count = getCurrentIteration(obj)
            %
            % Input Arguments:
            %   (none)
            %
            % Output Arguments:
            %   - **count** — double, current iteration counter
            %

            count = obj.Count;
        end

        % ----------------------------------------------------------
        function updateMaxNumberOfIterations(obj, N)
            % UPDATEMAXNUMBEROFITERATIONS - Replace the total iteration count with a new value.
            %
            % Syntax:
            %   function updateMaxNumberOfIterations(obj, N)
            %
            % Input Arguments:
            %   - **N** — double, new total number of iterations
            %
            % Output Arguments:
            %   (none)
            %

            obj.N = N;
        end

        % ----------------------------------------------------------
        function increaseMaxNumberOfIterations(obj, N)
            % INCREASEMAXNUMBEROFITERATIONS - Increase the total iteration count by N.
            %
            % Syntax:
            %   function increaseMaxNumberOfIterations(obj, N)
            %
            % Input Arguments:
            %   - **N** — double, amount to add to the current maximum
            %
            % Output Arguments:
            %   (none)
            %

            obj.N = obj.N + N;
        end

        % ----------------------------------------------------------
        function result = getMaxNumberOfIterations(obj)
            % GETMAXNUMBEROFITERATIONS - Return the total number of expected iterations.
            %
            % Syntax:
            %   function result = getMaxNumberOfIterations(obj)
            %
            % Input Arguments:
            %   (none)
            %
            % Output Arguments:
            %   - **result** — double, the N value set at construction or updated
            %

            result = obj.N;
        end

        % ----------------------------------------------------------
        function updateText(obj, newText)
            % UPDATETEXT - Update the message shown in the uiprogressdlg.
            %
            % Syntax:
            %   function updateText(obj, newText)
            %
            % Only safe to call from the main thread (not inside parfor).
            %
            % Input Arguments:
            %   - **newText** — char, new message string
            %
            % Output Arguments:
            %   (none)
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     pwb.updateText(sprintf('Processing slice %d/%d', z, zMax));
            %

            if isvalid(obj.ClientHandle)
                obj.ClientHandle.Message = newText;
            end
        end

        % ----------------------------------------------------------
        function text = getText(obj)
            % GETTEXT - Return the current message string from the uiprogressdlg.
            %
            % Syntax:
            %   function text = getText(obj)
            %
            % Input Arguments:
            %   (none)
            %
            % Output Arguments:
            %   - **text** — char, current dialog message
            %

            if isvalid(obj.ClientHandle)
                text = obj.ClientHandle.Message;
            else
                text = '';
            end
        end

        % ----------------------------------------------------------
        function res = getCancelState(obj)
            % GETCANCELSTATE - Return true if the user pressed Cancel in the dialog.
            %
            % Syntax:
            %   function res = getCancelState(obj)
            %
            % Only meaningful when the dialog was created with
            % Cancelable = true.  Poll this between parfor batches (on the
            % main thread) — do not call it from inside a parfor body.
            %
            % Input Arguments:
            %   (none)
            %
            % Output Arguments:
            %   - **res** — logical, true when Cancel has been requested
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     if pwb.getCancelState(); break; end
            %

            if isvalid(obj.ClientHandle)
                res = obj.ClientHandle.CancelRequested;
            else
                res = false;
            end
        end

        % ----------------------------------------------------------
        function wb = getWaitbarHandle(obj)
            % GETWAITBARHANDLE - Return the underlying uiprogressdlg handle.
            %
            % Syntax:
            %   function wb = getWaitbarHandle(obj)
            %
            % Use this before calling deletePoolWaitbar(true) to retain a
            % reference to the dialog for subsequent updates.
            %
            % Input Arguments:
            %   (none)
            %
            % Output Arguments:
            %   - **wb** — matlab.ui.dialog.ProgressDialog handle
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     wb = pwb.getWaitbarHandle(); pwb.deletePoolWaitbar(true);
            %

            wb = obj.ClientHandle;
        end

        % ----------------------------------------------------------
        function deletePoolWaitbar(obj, keepDialog)
            % DELETEPOOLWAITBAR - Tear down the PoolWaitbar, optionally keeping the uiprogressdlg.
            %
            % Syntax:
            %   function deletePoolWaitbar(obj, keepDialog)
            %
            % Input Arguments:
            %   - **keepDialog** — *(optional)* logical; when true the underlying
            %     uiprogressdlg is NOT deleted so the caller can continue
            %     using it directly.  Default false (dialog is deleted).
            %
            % Output Arguments:
            %   (none)
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     pwb.deletePoolWaitbar();% delete everything
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     pwb.deletePoolWaitbar(true);% keep dialog open
            %

            if nargin < 2; keepDialog = false; end

            if keepDialog
                % Stop listening without closing the dialog
                if ~isempty(obj.Listener) && isvalid(obj.Listener)
                    delete(obj.Listener);
                end
                if ~isempty(obj.Queue) && isvalid(obj.Queue)
                    delete(obj.Queue);
                end
            else
                delete(obj);   % triggers the destructor below
            end
        end

        % ----------------------------------------------------------
        function delete(obj)
            % DELETE - Destructor: clean up the DataQueue, Listener, and dialog.
            %
            % Syntax:
            %   function delete(obj)
            %

            if ~isempty(obj.Listener) && isvalid(obj.Listener)
                delete(obj.Listener);
            end
            if ~isempty(obj.Queue) && isvalid(obj.Queue)
                delete(obj.Queue);
            end
            if ~isempty(obj.ClientHandle) && isvalid(obj.ClientHandle)
                delete(obj.ClientHandle);
            end
        end
    end
end
