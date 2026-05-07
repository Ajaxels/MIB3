function answer = inputSingleDlg(ParentFigure, prompt, defAns, dlgTitle, options)
% INPUTSINGLEDLG - Single-input dialog for one text (``uieditfield``) or numeric (``uispinner``) value.
%
% Uses direct ``focus()`` for immediate keyboard focus — no ``java.awt.Robot`` dependency.
% The dialog blocks the caller via ``waitfor()`` until accepted or cancelled.
%
% Keyboard shortcuts:
%
% - **Enter** — accept (equivalent to clicking OK)
% - **Escape** — cancel (equivalent to clicking Cancel)
%
% Syntax:
%   .. code-block:: matlab
%
%      answer = inputSingleDlg(ParentFigure, prompt, defAns, dlgTitle)
%      answer = inputSingleDlg(ParentFigure, prompt, defAns, dlgTitle, options)
%
% Input Arguments:
%   - **ParentFigure** — handle to the parent window (AppContainer, uifigure, or ``[]``);
%     used to centre the dialog. Pass ``[]`` to reuse the cached handle from a prior call.
%   - **prompt** — [char|string] prompt text displayed above the input field.
%     Supports newlines, e.g. ``sprintf('Line 1\nLine 2')``.
%   - **defAns** — default value for the input widget:
%
%     - For editfield (default): [char|string] default text.
%     - For spinner: struct with the following fields:
%
%       - ``.Value`` — [numeric] initial value (default: ``0``)
%       - ``.Limits`` — ``[min max]`` spinner range (default: ``[-Inf Inf]``)
%       - ``.Step`` — [numeric] increment/decrement step (default: ``1``)
%       - ``.Round`` — [logical] round fractional values (default: ``true``)
%       - ``.ValueDisplayFormat`` — [char] format string, e.g. ``'%.0f'`` (default: ``'%.d'``)
%
%   - **dlgTitle** — [char|string] dialog window title.
%   - **options** *(optional)* — struct with configuration fields:
%
%     - ``.mibPath`` — [char] path to MIB installation for icon resolution
%       (default: auto-detected via ``which('mib3')``)
%     - ``.Type`` — [char] input widget type (default: ``'editfield'``):
%
%       - ``'editfield'`` — text input
%       - ``'spinner'`` — numeric spinner (auto-set when ``defAns`` is a struct)
%
%     - ``.WindowWidth`` — [numeric] dialog width in pixels (default: 400)
%     - ``.WindowHeight`` — [numeric] dialog height in pixels (default: 112)
%     - ``.WindowStyle`` — [char] ``'normal'`` (default) or ``'modal'``
%     - ``.Icon`` — [char] icon identifier (default: ``'puffin_question'``):
%
%       - ``'puffin_question'``, ``'puffin_warning'``, ``'puffin_error'``,
%         ``'puffin_measure'``, ``'puffin_info'``, ``'puffin_waiting'`` — puffin icons (96 px)
%       - ``'question_48px'``, ``'warning_48px'`` — standard icons (48 px)
%       - ``'celebrate'``, ``'call4help'`` — special icons
%
%     - ``.IconWidth`` — [numeric] icon column width in pixels
%       (default: 96 for puffin icons, 48 for standard icons)
%     - ``.ParentFigure`` — [handle] alternative parent for centering
%       (overrides the ``ParentFigure`` parameter)
%
% Output Arguments:
%   - **answer** — entered value; ``[]`` when cancelled:
%     - [char] for editfield mode
%     - [double] for spinner mode
%
% Usage:
%
%   **Example 1** — Basic editfield: add new material name
%
%   .. code-block:: matlab
%
%      answer = utils.dlgs.inputSingleDlg(obj.view.gui, ...
%          'Please enter a name for the new material:', ...
%          sprintf('m%.3d', 5), 'Add material');
%      if isempty(answer); return; end
%
%   **Example 2** — Editfield with all options specified
%
%   .. code-block:: matlab
%
%      options.Type = 'editfield';
%      options.WindowWidth = 400;
%      options.WindowHeight = 100;
%      options.WindowStyle = 'modal';
%      options.Icon = 'question_48px';
%      options.IconWidth = 48;
%      options.mibPath = obj.mibModel.mibPath;
%      answer = utils.dlgs.inputSingleDlg(obj.view.gui, ...
%          'Enter file name:', 'myfile.txt', 'File Name', options);
%      if isempty(answer); return; end
%
%   **Example 3** — Spinner with full struct configuration
%
%   .. code-block:: matlab
%
%      options.Type = 'spinner';
%      options.WindowWidth = 400;
%      options.WindowHeight = 100;
%      options.WindowStyle = 'modal';
%      options.Icon = 'question_48px';
%      options.IconWidth = 48;
%      options.mibPath = obj.mibModel.mibPath;
%      defAns = struct('Value', 10, 'Limits', [1 100], 'Step', 1, ...
%          'Round', false, 'ValueDisplayFormat', '%.3f units');
%      answer = utils.dlgs.inputSingleDlg(obj.view.gui, ...
%          'Enter iteration count:', defAns, 'Iterations', options);
%      if isempty(answer); return; end
%
%   **Example 4** — Minimalistic spinner with multiline prompt
%
%   .. code-block:: matlab
%
%      options.Type = 'spinner';
%      options.WindowWidth = 320;
%      defAns = struct('Value', 5, 'Limits', [1 Inf], 'Step', 1, ...
%          'Round', true, 'ValueDisplayFormat', '%d units');
%      answer = utils.dlgs.inputSingleDlg(obj.view.gui, ...
%          sprintf('Please enter number of colors\n(max. value is %d)', 255), ...
%          defAns, 'Define number of colors', options);
%      if isempty(answer); return; end
%
%   **Example 5** — No parent figure (standalone call)
%
%   .. code-block:: matlab
%
%      answer = utils.dlgs.inputSingleDlg([], 'Enter value:', 'hello', 'Test');
%      if isempty(answer); return; end
%
%   **Example 6** — Editfield with puffin warning icon
%
%   .. code-block:: matlab
%
%      options.Icon = 'puffin_warning';
%      options.WindowWidth = 450;
%      options.WindowHeight = 130;
%      options.mibPath = obj.mibModel.mibPath;
%      answer = utils.dlgs.inputSingleDlg(obj.view.gui, ...
%          'Enter new filename:', 'myfile.tif', 'Rename File', options);
%      if isempty(answer); return; end
%

% Updates
% 

arguments
    ParentFigure = []
    prompt char = 'Enter value:'
    defAns = ''
    dlgTitle char = 'Input'
    options struct = struct()
end

persistent mibDir
persistent parentFigureHandle  % cached handle to the main GUI window

if ~isfield(options, 'mibPath'); options.mibPath = ''; end

% ParentFigure param takes priority; update cache
if ~isempty(ParentFigure) && isvalid(ParentFigure)
    parentFigureHandle = ParentFigure;
end

% Resolve mibDir — update cache when options.mibPath is supplied
if ~isempty(options.mibPath)
    mibDir = options.mibPath;
elseif isempty(mibDir)
    if isdeployed
        [~, result] = system('path');
        toks = regexp(result, 'Path=(.*?);', 'tokens', 'once');
        if ~isempty(toks); mibDir = char(toks{1}); else; mibDir = pwd; end
    else
        mibDir = fileparts(which('mib3'));
        if isempty(mibDir); mibDir = pwd; end
    end
end

% Defaults
if ~isfield(options, 'Type'); options.Type = 'editfield'; end
if ~isfield(options, 'WindowWidth'); options.WindowWidth = 400; end
if ~isfield(options, 'WindowHeight'); options.WindowHeight = 112; end
if ~isfield(options, 'WindowStyle'); options.WindowStyle = 'normal'; end
if ~isfield(options, 'Icon'); options.Icon = 'puffin_question'; end

% Auto-detect spinner when defAns is a struct
if isstruct(defAns) && strcmp(options.Type, 'editfield')
    options.Type = 'spinner';
end
if ~isfield(options, 'IconWidth')
    if ismember(options.Icon, {'puffin_question', 'puffin_warning', 'puffin_error', 'puffin_measure', 'puffin_info', 'puffin_waiting'})
        options.IconWidth = 96;
    else
        options.IconWidth = 48;
    end
end
if ~isfield(options, 'ParentFigure'); options.ParentFigure = []; end
% use ParentFigure param first, then options.ParentFigure, then cached handle
if ~isempty(ParentFigure) && isvalid(ParentFigure)
    options.ParentFigure = ParentFigure;
elseif isempty(options.ParentFigure) && ~isempty(parentFigureHandle) && isvalid(parentFigureHandle)
    options.ParentFigure = parentFigureHandle;
elseif ~isempty(options.ParentFigure) && isvalid(options.ParentFigure)
    parentFigureHandle = options.ParentFigure;
end

% Icon selection and loading
switch options.Icon
    case 'warning_48px',     iconFilename = 'warning_48px.png';
    case 'question_48px',    iconFilename = 'question_48px.png';
    case 'celebrate',        iconFilename =  sprintf('puffin_cheering_%d_220px.png', randi(2));
    case 'call4help',        iconFilename =  sprintf('puffin_call4help_%d_220px.png', randi(3));
    case 'puffin_error';     iconFilename = sprintf('puffin_error_%d_96px.png', randi(4));
    case 'puffin_warning';   iconFilename = sprintf('puffin_warning_%d_96px.png', randi(3));
    case 'puffin_question';  iconFilename = sprintf('puffin_quest_%d_96px.png', randi(7));
    case 'puffin_measure';   iconFilename = sprintf('puffin_measure_%d_96px.png', randi(5));
    case 'puffin_info';      iconFilename = sprintf('puffin_info_%d_96px.png', randi(5));
    case 'puffin_waiting';   iconFilename = sprintf('puffin_waiting_%d_96px.png', randi(3));
    otherwise
        % puffin_question
        iconFilename = sprintf('puffin_quest_%d_96px.png', randi(6));
end

iconPath = fullfile(mibDir, 'assets', 'images', iconFilename);

fig = uifigure('Name', dlgTitle, 'WindowStyle', lower(options.WindowStyle), Visible='off');
fig.Icon = fullfile(mibDir, 'assets', 'icons', 'mib_icon_16px.png');
fig.Position = [fig.Position(1), fig.Position(2), options.WindowWidth, options.WindowHeight];
fig.Tag = 'inputSingleDlg';

mainGrid = uigridlayout(fig, [3 2], ...
    'RowHeight', {'1x', 22, 22}, ...
    'ColumnWidth', {options.IconWidth, '1x'}, ...
    'Padding', [10 10 10 10], 'RowSpacing', 10, 'ColumnSpacing', 12);

% Column 1: Icon (all rows)
if exist(iconPath, 'file')
    iconUI = uiimage(mainGrid, 'ImageSource', iconPath, 'ScaleMethod', 'fit');
    iconUI.Layout.Row = [1 3];  % Span all rows
    iconUI.Layout.Column = 1;
    iconUI.VerticalAlignment = 'top';
    iconUI.HorizontalAlignment = 'left';
else
    emptyIconLbl = uilabel(mainGrid, 'Text', '');
    emptyIconLbl.Layout.Row = [1 3];
    emptyIconLbl.Layout.Column = 1;
end

% Column 2, Row 1: Prompt label (fills available space)
promptLbl = uilabel(mainGrid, 'Text', prompt, 'WordWrap', 'on', 'FontWeight', 'bold');
promptLbl.Layout.Row = 1;
promptLbl.Layout.Column = 2;

% Column 2, Row 2: Input widget
if strcmpi(options.Type, 'spinner')
    % Spinner widget
    if isstruct(defAns)
        v = 0; lo = -Inf; hi = Inf; step = 1; roundVals = true; valueDisplayFormat = '%.d';
        if isfield(defAns, 'Value'); v = defAns.Value; end
        if isfield(defAns, 'Limits'); lo = defAns.Limits(1); hi = defAns.Limits(2); end
        if isfield(defAns, 'Step'); step = defAns.Step; end
        if isfield(defAns,'Round'); roundVals = defAns.Round; end
        if isfield(defAns,'ValueDisplayFormat'); valueDisplayFormat = defAns.ValueDisplayFormat; end
        inputCtrl = uispinner(mainGrid, 'Limits', [lo hi], 'Value', v, 'Step', step, ...
            'RoundFractionalValues', roundVals, 'ValueDisplayFormat', valueDisplayFormat);
    else
        inputCtrl = uispinner(mainGrid, 'Limits', [-Inf Inf], 'Value', 1, 'Step', 1);
    end
else
    % Text editfield widget
    if isempty(defAns); defAns = ''; end
    inputCtrl = uieditfield(mainGrid, 'text', 'Value', char(defAns));
end
inputCtrl.Layout.Row = 2;
inputCtrl.Layout.Column = 2;

% Column 2, Row 3: Buttons (OK and Cancel)
btnGrid = uigridlayout(mainGrid, [1 3], ...
    'ColumnWidth', {'1x', 80, 80}, ...
    'ColumnSpacing', 8, 'Padding', [0 0 0 0]);
btnGrid.Layout.Row = 3;
btnGrid.Layout.Column = 2;

% Spacer
uilabel(btnGrid, 'Text', '');

% OK button
okBtn = uibutton(btnGrid, 'Text', 'OK', 'ButtonPushedFcn', @(~,~) onOK());
okBtn.Layout.Column = 2;

% Cancel button
cancelBtn = uibutton(btnGrid, 'Text', 'Cancel', 'ButtonPushedFcn', @(~,~) onCancel());
cancelBtn.Layout.Column = 3;

% Key handling (Esc for Cancel, Enter for OK)
fig.WindowKeyPressFcn = @(~, evt) onKey(evt);

% Center dialog on parent figure if provided
if ~isempty(options.ParentFigure) && isvalid(options.ParentFigure)
    try
        if isa(options.ParentFigure, 'matlab.ui.container.internal.AppContainer')
            parentPos = options.ParentFigure.WindowBounds;  % [x y w h]

            % Get screen size to convert from top-left to bottom-left origin
            screenSize = get(0, 'ScreenSize'); % [left bottom width height]

            % Center in parent's coordinates (bottom-left origin)
            x1 = parentPos(1) + (parentPos(3) - options.WindowWidth)  / 2;
            % Convert Y from top-left to bottom-left origin
            % parentPos(2) is distance from top of screen
            % Need to convert to distance from bottom of screen
            y1 = screenSize(4) - parentPos(2) - parentPos(4) + (parentPos(4) - options.WindowHeight) / 2;
        elseif isa(options.ParentFigure, 'matlab.ui.Figure')
            parentPos = options.ParentFigure.Position;      % [x y w h]

            % Center in parent's coordinates (bottom-left origin)
            x1 = parentPos(1) + (parentPos(3) - options.WindowWidth)  / 2;
            y1 = parentPos(2) + (parentPos(4) - options.WindowHeight) / 2;
        end

        fig.Position(1) = x1;
        fig.Position(2) = y1;
    catch
        % If centering fails, MATLAB will use default position
    end
end

% Initialize output
answer = [];

drawnow;
fig.Visible = 'on';

% Direct focus on input widget — no java.awt.Robot, no timer
focus(inputCtrl);

% Block caller until dialog is closed
waitfor(fig);

% Callbacks
    function onOK()
        if strcmpi(options.Type, 'spinner')
            answer = double(inputCtrl.Value);
        else
            answer = char(inputCtrl.Value);
        end
        delete(fig);
    end

    function onCancel()
        answer = [];
        delete(fig);
    end

    function onKey(evt)
        if isequal(evt.Key, 'escape')
            onCancel();
        elseif isequal(evt.Key, 'return')
            focus(okBtn);  % Move focus to button, commits editfield value
            pause(0.1);
            onOK();
        end
    end
end
