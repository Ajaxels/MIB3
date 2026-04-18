classdef PoolWaitbar < handle
    % classdef PoolWaitbar < handle
    % Thread-safe progress dialog for parallel loops (parfor / spmd / parfeval).
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
    %|
    % @b Basic examples:
    % @code
    % % Simplest use: create, run parfor, delete
    % pwb = core.PoolWaitbar(100, 'Working...', mibGUI, 'My task');
    % parfor ii = 1:100
    %     pwb.increment();
    % end
    % pwb.deletePoolWaitbar();
    % @endcode
    %
    % @code
    % % Reuse an existing uiprogressdlg
    % wb = uiprogressdlg(mibGUI, 'Message', 'Phase 1', 'Title', 'Proc');
    % pwb = core.PoolWaitbar(n, 'Phase 2', wb);
    % parfor ii = 1:n
    %     pwb.increment();
    % end
    % pwb.deletePoolWaitbar(true);   % keep wb open for the next phase
    % wb.Value = 1;  delete(wb);
    % @endcode
    %
    % @code
    % % Cancelable dialog – poll getCancelState() between parfor batches
    % pwb = core.PoolWaitbar(n, 'Processing...', mibGUI, 'Job', true);
    % pwb.setIncrement(10);         % update every 10 steps
    % for batchStart = 1:10:n
    %     if pwb.getCancelState(); break; end
    %     batchEnd = min(batchStart+9, n);
    %     parfor ii = batchStart:batchEnd
    %         pwb.increment();
    %     end
    % end
    % pwb.deletePoolWaitbar();
    % @endcode

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
            % localIncrement  Advance Count and refresh the dialog.
            %   Called on the main thread via afterEach(Queue, ...) each
            %   time a worker calls increment().
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
        function obj = PoolWaitbar(N, message, parentOrHandle, WindowName, Cancelable)
            % function obj = PoolWaitbar(N, message, parentOrHandle, WindowName, Cancelable)
            % Construct a thread-safe progress dialog for parallel loops.
            %
            % Parameters:
            % N: double, total number of iterations expected
            % message: [@em optional] char, text shown inside the dialog;
            %   default 'Please wait...'
            % parentOrHandle: [@em optional] either
            %   @li matlab.ui.Figure — parent UIFigure; a new uiprogressdlg
            %       is created automatically
            %   @li matlab.ui.dialog.ProgressDialog — existing dialog to
            %       reuse (its Value is reset to 0 and Message/Title updated)
            %   @li [] — error; a parent is required in MIB3
            % WindowName: [@em optional] char, dialog title; default ''
            % Cancelable: [@em optional] logical, add Cancel button;
            %   default false.  Only used when parentOrHandle is a Figure.
            %
            % Return values:
            % obj: core.PoolWaitbar instance
            %
            %|
            % @b Examples:
            % @code
            % pwb = core.PoolWaitbar(200, 'Eroding...', obj.mibModel.mibGUI, 'Erode');
            % @endcode
            % @code
            % % Reuse an open dialog
            % pwb = core.PoolWaitbar(200, 'Phase 2', existingWb);
            % @endcode

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

            elseif isa(parentOrHandle, 'matlab.ui.Figure')
                % Create a new deterministic uiprogressdlg
                obj.ClientHandle = uiprogressdlg(parentOrHandle, ...
                    'Message',    message, ...
                    'Title',      WindowName, ...
                    'Value',      0, ...
                    'Cancelable', Cancelable);

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
            % function increment(obj)
            % Signal one step of progress from any thread (main or worker).
            %
            % This is the only method that is safe to call inside a parfor
            % body.  It uses send() on the immutable DataQueue; the actual
            % UI update happens asynchronously on the main thread.
            %
            % Parameters:
            %   (none)
            %
            % Return values:
            %   (none)
            %
            %|
            % @b Examples:
            % @code parfor ii = 1:n; pwb.increment(); end @endcode

            send(obj.Queue, true);
        end

        % ----------------------------------------------------------
        function setIncrement(obj, increment)
            % function setIncrement(obj, increment)
            % Set the step size added to Count on each increment() call.
            %
            % Use this when the caller wants to call increment() less
            % frequently (e.g., every 10 iterations to reduce overhead).
            %
            % Parameters:
            % increment: double, new step size; default 1
            %
            % Return values:
            %   (none)
            %
            %|
            % @b Examples:
            % @code pwb.setIncrement(10);  // advance bar by 10% each call @endcode

            obj.Increment = increment;
        end

        % ----------------------------------------------------------
        function setCurrentIteration(obj, count)
            % function setCurrentIteration(obj, count)
            % Manually set the completed-iteration counter.
            %
            % Useful when restarting progress tracking mid-run or when
            % stitching two sequential phases that share one dialog.
            %
            % Parameters:
            % count: double, new value for the internal counter
            %
            % Return values:
            %   (none)

            obj.Count = count;
        end

        % ----------------------------------------------------------
        function count = getCurrentIteration(obj)
            % function count = getCurrentIteration(obj)
            % Return the number of iterations completed so far.
            %
            % Parameters:
            %   (none)
            %
            % Return values:
            % count: double, current iteration counter

            count = obj.Count;
        end

        % ----------------------------------------------------------
        function updateMaxNumberOfIterations(obj, N)
            % function updateMaxNumberOfIterations(obj, N)
            % Replace the total iteration count with a new value.
            %
            % Parameters:
            % N: double, new total number of iterations
            %
            % Return values:
            %   (none)

            obj.N = N;
        end

        % ----------------------------------------------------------
        function increaseMaxNumberOfIterations(obj, N)
            % function increaseMaxNumberOfIterations(obj, N)
            % Increase the total iteration count by N.
            %
            % Parameters:
            % N: double, amount to add to the current maximum
            %
            % Return values:
            %   (none)

            obj.N = obj.N + N;
        end

        % ----------------------------------------------------------
        function result = getMaxNumberOfIterations(obj)
            % function result = getMaxNumberOfIterations(obj)
            % Return the total number of expected iterations.
            %
            % Parameters:
            %   (none)
            %
            % Return values:
            % result: double, the N value set at construction or updated

            result = obj.N;
        end

        % ----------------------------------------------------------
        function updateText(obj, newText)
            % function updateText(obj, newText)
            % Update the message shown in the uiprogressdlg.
            %
            % Only safe to call from the main thread (not inside parfor).
            %
            % Parameters:
            % newText: char, new message string
            %
            % Return values:
            %   (none)
            %
            %|
            % @b Examples:
            % @code pwb.updateText(sprintf('Processing slice %d/%d', z, zMax)); @endcode

            if isvalid(obj.ClientHandle)
                obj.ClientHandle.Message = newText;
            end
        end

        % ----------------------------------------------------------
        function text = getText(obj)
            % function text = getText(obj)
            % Return the current message string from the uiprogressdlg.
            %
            % Parameters:
            %   (none)
            %
            % Return values:
            % text: char, current dialog message

            if isvalid(obj.ClientHandle)
                text = obj.ClientHandle.Message;
            else
                text = '';
            end
        end

        % ----------------------------------------------------------
        function res = getCancelState(obj)
            % function res = getCancelState(obj)
            % Return true if the user pressed Cancel in the dialog.
            %
            % Only meaningful when the dialog was created with
            % Cancelable = true.  Poll this between parfor batches (on the
            % main thread) — do not call it from inside a parfor body.
            %
            % Parameters:
            %   (none)
            %
            % Return values:
            % res: logical, true when Cancel has been requested
            %
            %|
            % @b Examples:
            % @code if pwb.getCancelState(); break; end @endcode

            if isvalid(obj.ClientHandle)
                res = obj.ClientHandle.CancelRequested;
            else
                res = false;
            end
        end

        % ----------------------------------------------------------
        function wb = getWaitbarHandle(obj)
            % function wb = getWaitbarHandle(obj)
            % Return the underlying uiprogressdlg handle.
            %
            % Use this before calling deletePoolWaitbar(true) to retain a
            % reference to the dialog for subsequent updates.
            %
            % Parameters:
            %   (none)
            %
            % Return values:
            % wb: matlab.ui.dialog.ProgressDialog handle
            %
            %|
            % @b Examples:
            % @code wb = pwb.getWaitbarHandle(); pwb.deletePoolWaitbar(true); @endcode

            wb = obj.ClientHandle;
        end

        % ----------------------------------------------------------
        function deletePoolWaitbar(obj, keepDialog)
            % function deletePoolWaitbar(obj, keepDialog)
            % Tear down the PoolWaitbar, optionally keeping the uiprogressdlg.
            %
            % Parameters:
            % keepDialog: [@em optional] logical; when true the underlying
            %   uiprogressdlg is NOT deleted so the caller can continue
            %   using it directly.  Default false (dialog is deleted).
            %
            % Return values:
            %   (none)
            %
            %|
            % @b Examples:
            % @code pwb.deletePoolWaitbar();        // delete everything @endcode
            % @code pwb.deletePoolWaitbar(true);    // keep dialog open @endcode

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
            % function delete(obj)
            % Destructor: clean up the DataQueue, Listener, and dialog.

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
