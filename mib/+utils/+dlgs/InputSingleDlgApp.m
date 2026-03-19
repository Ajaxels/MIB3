classdef InputSingleDlgApp < handle
    % InputSingleDlgApp  AppDesigner-based single-input dialog
    %
    % Displays a modal dialog with either a text editfield or a numeric
    % spinner, using the class + .mlapp pattern (InputSingleDlgAppGUI)
    % for reliable modal behaviour and keyboard focus handling.
    % Drop-in replacement for inputSingleDlg.
    %
    % Usage:
    %   dlg = utils.dlgs.InputSingleDlgApp(parentFig, prompt, defAns, dlgTitle, options);
    %   answer = dlg.run();
    %   if isempty(answer); return; end
    %
    % Parameters:
    % ParentFigure: handle to the parent window (AppContainer, uifigure, or []);
    %   used to center the dialog. Pass [] to use the cached handle from a prior call.
    %   To supply the MIB installation path use options.mibPath.
    % prompt: string with the prompt text for the input field
    % defAns: default value - string for editfield or struct for spinner
    %   For spinner: struct('Value', v, 'Limits', [min max], 'Step', s, 'Round', false/true, 'ValueDisplayFormat', '%.0f MS/s')
    % dlgTitle: dialog window title string
    % options: struct with fields:
    %   .mibPath     - char with path to MIB installation (default: '')
    %   .Type        - 'editfield' (default) or 'spinner'
    %   .WindowWidth       - dialog width in pixels (default 400)
    %   .WindowHeight      - dialog height in pixels (default 112)
    %   .Icon        - 'puffin_question' (default), 'puffin_warning', 'puffin_error',
    %                  'puffin_measure', 'puffin_info', 'puffin_waiting',
    %                  'question_48px', 'celebrate', 'call4help', 'warning_48px'
    %   .IconWidth   - width of icon column in pixels (default 96 for puffin icons, 48 otherwise)
    %   .ParentFigure - handle to the parent window to have the dialog centered
    %
    % Return values:
    % answer: entered value (string for editfield, double for spinner), empty when canceled
    %
    %|
    % @b Examples:
    % @code
    % % editfield mode
    % options.mibPath = obj.mibModel.mibPath;
    % dlg = utils.dlgs.InputSingleDlgApp(obj.view.gui, 'Enter name:', 'default', 'Input', options);
    % answer = dlg.run();
    % if isempty(answer); return; end
    % @endcode
    % @code
    % % spinner mode
    % options.Type = 'spinner';
    % options.mibPath = obj.mibModel.mibPath;
    % defAns = struct('Value', 10, 'Limits', [1 100], 'Step', 1, 'Round', false, 'ValueDisplayFormat', '%.3f units');
    % dlg = utils.dlgs.InputSingleDlgApp(obj.view.gui, 'Enter count:', defAns, 'Count', options);
    % answer = dlg.run();
    % if isempty(answer); return; end
    % @endcode

    properties 
        view            % views.InputSingleDlgAppGUI App Designer app
        options         % full options struct
        inputType       % 'editfield' or 'spinner'
        answer = []     % output; [] = cancelled
        mibDir          % resolved MIB installation path
    end

    methods
        function obj = InputSingleDlgApp(ParentFigure, prompt, defAns, dlgTitle, options)
            % InputSingleDlgApp  Constructor
            %
            % Parameters:
            % ParentFigure: handle to the parent GUI window or []
            % prompt: char, prompt text
            % defAns: default answer (char or struct)
            % dlgTitle: char, dialog title
            % options: struct with configuration fields

            if nargin < 5; options = struct(); end
            if nargin < 4; dlgTitle = 'Input'; end
            if nargin < 3; defAns = ''; end
            if nargin < 2; prompt = 'Enter value:'; end
            if nargin < 1; ParentFigure = []; end

            persistent mibDirCache
            persistent parentFigureCache

            if ~isfield(options, 'mibPath'); options.mibPath = ''; end

            % ParentFigure param takes priority; update cache
            if ~isempty(ParentFigure) && isvalid(ParentFigure)
                parentFigureCache = ParentFigure;
            end

            % Resolve mibDir — update cache when options.mibPath is supplied
            if ~isempty(options.mibPath)
                mibDirCache = options.mibPath;
            elseif isempty(mibDirCache)
                if isdeployed
                    [~, result] = system('path');
                    toks = regexp(result, 'Path=(.*?);', 'tokens', 'once');
                    if ~isempty(toks); mibDirCache = char(toks{1}); else; mibDirCache = pwd; end
                else
                    mibDirCache = fileparts(which('mib3'));
                    if isempty(mibDirCache); mibDirCache = pwd; end
                end
            end
            obj.mibDir = mibDirCache;

            % Resolve ParentFigure: param first, then options, then cache
            if ~isempty(ParentFigure) && isvalid(ParentFigure)
                resolvedParent = ParentFigure;
            elseif isfield(options, 'ParentFigure') && ~isempty(options.ParentFigure) && isvalid(options.ParentFigure)
                resolvedParent = options.ParentFigure;
                parentFigureCache = resolvedParent;
            elseif ~isempty(parentFigureCache) && isvalid(parentFigureCache)
                resolvedParent = parentFigureCache;
            else
                resolvedParent = [];
            end

            % Apply defaults
            if ~isfield(options, 'Type'); options.Type = 'editfield'; end
            if ~isfield(options, 'WindowWidth'); options.WindowWidth = 400; end
            if ~isfield(options, 'WindowHeight'); options.WindowHeight = 112; end
            if ~isfield(options, 'Icon'); options.Icon = 'puffin_question'; end
            if ~isfield(options, 'IconWidth')
                if ismember(options.Icon, {'puffin_question', 'puffin_warning', 'puffin_error', 'puffin_measure', 'puffin_info', 'puffin_waiting'})
                    options.IconWidth = 96;
                else
                    options.IconWidth = 48;
                end
            end
            obj.options = options;
            obj.inputType = lower(options.Type);

            % Instantiate the App Designer view.
            % The .mlapp createComponents ends with Visible='on', so move
            % the figure off-screen immediately to prevent a visible flash
            % of the unconfigured dialog.
            obj.view = views.InputSingleDlgAppGUI;
            obj.view.Figure.Position(1:2) = [-10000, -10000];

            % Configure the view while it is off-screen
            obj.initView(resolvedParent, prompt, defAns, dlgTitle);

            % Set window icon
            iconFile = fullfile(obj.mibDir, 'assets', 'icons', 'mib_icon_16px.png');
            if exist(iconFile, 'file'); obj.view.Figure.Icon = iconFile; end

            % Now hide; run() will show it at the correct position
            obj.view.Figure.Visible = 'off';

        end

        function result = run(obj)
            % run  Show dialog modally and return the entered value
            %
            % Return values:
            % result: char or double; [] if cancelled

            obj.view.Figure.WindowStyle = 'modal';
            obj.view.Figure.Visible = 'on';
            drawnow;

            % Defer focus to the input widget — the modal figure needs a
            % moment to fully claim window-level focus before a child
            % widget can receive it.
            if strcmp(obj.inputType, 'spinner')
                widget = obj.view.spinner;
            else
                widget = obj.view.editField;
            end
            t = timer('StartDelay', 0.15, 'ExecutionMode', 'singleShot', ...
                'TimerFcn', @(th,~) obj.deferredFocus(th, widget));
            start(t);

            uiwait(obj.view.Figure);

            % Handle abrupt window close
            if ~isvalid(obj.view)
                result = [];
                return;
            end

            result = obj.answer;
            delete(obj.view);
        end
    end

    methods (Access = private)
        function initView(obj, ParentFigure, prompt, defAns, dlgTitle)
            % initView  Configure the view before it becomes visible

            fig = obj.view.Figure;
            fig.Name = dlgTitle;
            fig.Resize = 'off';
            fig.Position = [fig.Position(1), fig.Position(2), ...
                obj.options.WindowWidth, obj.options.WindowHeight];

            % Set icon image
            iconPath = obj.resolveIconPath();
            if ~isempty(iconPath) && exist(iconPath, 'file')
                obj.view.iconImage.ImageSource = iconPath;
            end

            % Set icon column width
            obj.view.mainGrid.ColumnWidth{1} = obj.options.IconWidth;

            % Set prompt text
            obj.view.promptLabel.Text = prompt;

            % Configure input widget — show one, hide the other
            if strcmp(obj.inputType, 'spinner')
                obj.view.editField.Visible = 'off';
                obj.view.spinner.Visible = 'on';
                if isstruct(defAns)
                    if isfield(defAns, 'Limits')
                        obj.view.spinner.Limits = defAns.Limits;
                    end
                    if isfield(defAns, 'Value')
                        obj.view.spinner.Value = defAns.Value;
                    end
                    if isfield(defAns, 'Step')
                        obj.view.spinner.Step = defAns.Step;
                    end
                    if isfield(defAns, 'Round')
                        obj.view.spinner.RoundFractionalValues = defAns.Round;
                    end
                    if isfield(defAns, 'ValueDisplayFormat')
                        obj.view.spinner.ValueDisplayFormat = defAns.ValueDisplayFormat;
                    end
                end
            else
                obj.view.spinner.Visible = 'off';
                obj.view.editField.Visible = 'on';
                if isempty(defAns); defAns = ''; end
                obj.view.editField.Value = char(defAns);
            end

            % Center on parent
            if ~isempty(ParentFigure) && isvalid(ParentFigure)
                utils.moveWindowOutside(fig, ParentFigure, 'center', 'center');
            end

            % Wire callbacks
            obj.view.okBtn.ButtonPushedFcn     = @(~, ~) obj.onOK();
            obj.view.cancelBtn.ButtonPushedFcn = @(~, ~) obj.onCancel();
            fig.WindowKeyPressFcn              = @(~, evt) obj.onKeyPress(evt);
            fig.CloseRequestFcn                = @(~, ~) obj.onCancel();
        end

        function iconPath = resolveIconPath(obj)
            % resolveIconPath  Select and return the full path to the icon image

            switch obj.options.Icon
                case 'warning_48px';     iconFilename = 'warning_48px.png';
                case 'question_48px';    iconFilename = 'question_48px.png';
                case 'celebrate';        iconFilename = sprintf('puffin_cheering_%d_220px.png', randi(2));
                case 'call4help';        iconFilename = 'call4help.jpg';
                case 'puffin_error';     iconFilename = sprintf('puffin_error_%d_96px.png', randi(4));
                case 'puffin_warning';   iconFilename = sprintf('puffin_warning_%d_96px.png', randi(3));
                case 'puffin_question';  iconFilename = sprintf('puffin_quest_%d_96px.png', randi(7));
                case 'puffin_measure';   iconFilename = sprintf('puffin_measure_%d_96px.png', randi(5));
                case 'puffin_info';      iconFilename = sprintf('puffin_info_%d_96px.png', randi(5));
                case 'puffin_waiting';   iconFilename = sprintf('puffin_waiting_%d_96px.png', randi(3));
                otherwise
                    iconFilename = sprintf('puffin_quest_%d_96px.png', randi(6));
            end
            iconPath = fullfile(obj.mibDir, 'assets', 'images', iconFilename);
        end

        function onOK(obj)
            % onOK  Read value from the active widget and close

            if strcmp(obj.inputType, 'spinner')
                obj.answer = double(obj.view.spinner.Value);
            else
                obj.answer = char(obj.view.editField.Value);
            end
            uiresume(obj.view.Figure);
        end

        function onCancel(obj)
            % onCancel  Cancel the dialog

            obj.answer = [];
            uiresume(obj.view.Figure);
        end

        function onKeyPress(obj, event)
            % onKeyPress  Handle Enter and Escape keys

            switch event.Key
                case 'escape'
                    obj.onCancel();
                case 'return'
                    if strcmp(obj.inputType, 'editfield')
                        % Move focus to OK button to force editfield value commit
                        focus(obj.view.okBtn);
                        drawnow;
                    end
                    obj.onOK();
            end
        end

        function deferredFocus(obj, th, widget)
            % deferredFocus  Timer callback — simulate a click on the
            % dialog to force OS-level focus, then focus the input widget.

            try; stop(th); delete(th); catch; end
            try
                if ~isvalid(obj.view); return; end

                % Compute click position: center of the figure in screen
                % coordinates.  uifigure Position is [x y w h] from the
                % bottom-left of the screen, but java.awt.Robot uses
                % top-left origin.
                figPos     = obj.view.Figure.Position;  % [x y w h]
                screenSize = get(0, 'ScreenSize');       % [1 1 w h]
                % X: figure left + half width
                clickX = round(figPos(1) + figPos(3) / 2);
                % Y: convert from bottom-left to top-left origin
                clickY = round(screenSize(4) - figPos(2) - figPos(4) + figPos(4) / 2);

                robot = java.awt.Robot();
                robot.mouseMove(clickX, clickY);
                robot.mousePress(java.awt.event.InputEvent.BUTTON1_DOWN_MASK);
                robot.mouseRelease(java.awt.event.InputEvent.BUTTON1_DOWN_MASK);

                % Now set focus on the input widget and select all text
                if isvalid(widget)
                    focus(widget);
                    % Simulate Ctrl+A to select all text in the editfield
                    robot.keyPress(java.awt.event.KeyEvent.VK_CONTROL);
                    robot.keyPress(java.awt.event.KeyEvent.VK_A);
                    robot.keyRelease(java.awt.event.KeyEvent.VK_A);
                    robot.keyRelease(java.awt.event.KeyEvent.VK_CONTROL);
                end
            catch
            end
        end
    end
end
