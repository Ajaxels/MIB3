function answer = inputSingleDlg(ParentFigure, prompt, defAns, dlgTitle, options)
% INPUTSINGLEDLG - Single-input dialog for one text (``uieditfield``) or numeric (``uispinner``) value.
%
% Uses direct ``focus()`` for immediate keyboard focus — no ``java.awt.Robot`` dependency.
% The dialog blocks the caller via ``uiwait()`` until accepted or cancelled.
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
%     In MIB pass ``obj.mibModel.getProgressBarParent()`` so the dialog follows the
%     active dataset window when it is undocked.
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

if ~isfield(options, 'mibPath'); options.mibPath = ''; end

% MIB path resolution for icons — the helper caches it; options.mibPath refreshes the cache
mibDir = dlgResolveMibDir(options.mibPath);

% Defaults
if ~isfield(options, 'Type'); options.Type = 'editfield'; end
if ~isfield(options, 'WindowWidth'); options.WindowWidth = 400; end
if ~isfield(options, 'WindowHeight'); options.WindowHeight = 150; end
if ~isfield(options, 'WindowStyle'); options.WindowStyle = 'normal'; end
if ~isfield(options, 'Icon'); options.Icon = 'puffin_question'; end

% Auto-detect spinner when defAns is a struct
if isstruct(defAns) && strcmp(options.Type, 'editfield')
    options.Type = 'spinner';
end
if ~isfield(options, 'IconWidth'); options.IconWidth = dlgIconDefaultWidth(options.Icon); end
if ~isfield(options, 'ParentFigure'); options.ParentFigure = []; end
% ParentFigure first-param takes priority over options.ParentFigure and the cached handle
options.ParentFigure = dlgResolveParent(ParentFigure, options.ParentFigure);

% Reuse a cached hidden figure when available; a temporary (non-cached) shell
% must be deleted on close instead of hidden
[fig, isCachedFigure] = dlgAcquireFigure('inputSingleDlg', dlgTitle, mibDir);
fig.WindowStyle = lower(options.WindowStyle);

% Font-aware height of a single widget row (22 px at the factory 12 px font)
rowHeight = dlgRowHeight(fig);

% Center on the parent and apply the geometry in a single Position write
xy = dlgCenterOnParent(options.ParentFigure, options.WindowWidth, options.WindowHeight);
newPosition = fig.Position;
if ~isempty(xy); newPosition(1:2) = xy; end
newPosition(3:4) = [options.WindowWidth, options.WindowHeight];
fig.Position = newPosition;

% Icon loading: composited against the figure background and cached by the helper
[iconImg, iconImgWidth] = dlgLoadIcon(options.Icon, options.IconWidth, fig.Color, mibDir);

mainGrid = uigridlayout(fig, [3 2], ...
    'RowHeight', {'1x', rowHeight, rowHeight}, ...
    'ColumnWidth', {iconImgWidth, '1x'}, ...
    'Padding', [10 10 10 10], 'RowSpacing', 10, 'ColumnSpacing', 12);

% Column 1: Icon (all rows)
if ~isempty(iconImg)
    iconUI = uiimage(mainGrid, 'ImageSource', iconImg);
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
fig.CloseRequestFcn = @(~,~) onCancel();

% Initialize output
answer = [];

fig.Visible = 'on';
drawnow;   % realize the figure before re-applying WindowStyle

% Re-apply WindowStyle on the realized (visible) figure — setting it while a
% cached figure is hidden does not take effect (notably in the deployed web
% engine), so the dialog would otherwise come up non-modal on reuse.
fig.WindowStyle = lower(options.WindowStyle);

% Direct focus on input widget — no java.awt.Robot, no timer
focus(inputCtrl);

% Block caller until dialog is closed
uiwait(fig);

% Callbacks
    function onOK()
        if strcmpi(options.Type, 'spinner')
            answer = double(inputCtrl.Value);
        else
            answer = char(inputCtrl.Value);
        end
        closeDialog();
    end

    function onCancel()
        answer = [];
        closeDialog();
    end

    function closeDialog()
        % Reset WindowStyle first: a hidden but still-modal figure keeps its
        % input grab on the parent and would freeze the main GUI.
        fig.WindowStyle = 'normal';
        if isCachedFigure
            % Hide and unblock instead of deleting so the figure can be reused
            fig.Visible = 'off';
            uiresume(fig);
        else
            % Temporary second instance (the cached shell was busy) —
            % deleting the figure also releases uiwait
            delete(fig);
        end
    end

    function onKey(evt)
        if isequal(evt.Key, 'escape')
            onCancel();
        elseif isequal(evt.Key, 'return')
            focus(okBtn);  % Move focus to button to commit the editfield value
            drawnow;       % dispatch the focus change to the renderer
            pause(0.1);    % allow the editfield value round-trip to commit before reading
                           % (drawnow alone is too fast: the typed value commits via an
                           %  async browser round-trip that one drawnow misses)
            onOK();
        end
    end
end
