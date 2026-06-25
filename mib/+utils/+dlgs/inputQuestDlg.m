function [selection, dontShowAgain] = inputQuestDlg(ParentFigure, question, varargin)
% INPUTQUESTDLG - Custom MIB question dialog compatible with MATLAB ``questdlg``,
% extended with an optional ``options`` structure as the last argument.
%
% Syntax:
%   .. code-block:: matlab
%
%      % questdlg-compatible forms:
%      selection = inputQuestDlg(ParentFigure, question)
%      selection = inputQuestDlg(ParentFigure, question, dlgTitle)
%      selection = inputQuestDlg(ParentFigure, question, dlgTitle, btn1, btn2)
%      selection = inputQuestDlg(ParentFigure, question, dlgTitle, btn1, btn2, btn3)
%      selection = inputQuestDlg(ParentFigure, question, dlgTitle, btn1, btn2, defaultBtn)
%      selection = inputQuestDlg(ParentFigure, question, dlgTitle, btn1, btn2, btn3, defaultBtn)
%      % extended form — options struct as last argument:
%      [selection, dontShowAgain] = inputQuestDlg(..., options)
%
% Input Arguments:
%   - **ParentFigure** — handle to the parent window (AppContainer, uifigure, or ``[]``);
%     used to center the dialog. Pass ``[]`` to use the cached handle from a prior call.
%     In MIB pass ``obj.mibModel.getProgressBarParent()`` so the dialog follows the
%     active dataset window when it is undocked.
%     To supply the MIB installation path use ``options.mibPath``.
%   - **question** — [char|string|cell] question text; when cell, lines are joined with ``\n``.
%   - **options** *(optional)* — structure with the following fields:
%
%     - ``.mibPath`` — [char] path to MIB installation folder (default: ``''``)
%     - ``.WindowWidth`` — [numeric] dialog width in pixels (default: 420)
%     - ``.WindowHeight`` — [numeric] dialog height in pixels (default: 160)
%     - ``.WindowStyle`` — [char] ``'normal'`` or ``'modal'`` (default: ``'modal'``)
%     - ``.Icon`` — [char]
%     ``'puffin_question'`` (default), ``'puffin_warning'``,
%           ``'puffin_info'``, ``'question_48px'``, ``'warning_48px'``, ``'celebrate'``, ``'call4help'``
%     - ``.IconWidth`` — [numeric] icon column width in pixels (default: 48)
%     - ``.ParentFigure`` — [handle] parent window used to centre the dialog (default: ``[]``)
%     - ``.DefaultKey`` — [char] ``'default'`` or ``'cancel'``; controls which action the Enter key triggers (default: ``'default'``)
%     - ``.FontSize`` — [numeric] question text font size (default: 14)
%     - ``.ButtonFontSize`` — [numeric] button font size (default: 12)
%     - ``.DoNotShowAgain`` — [logical] show a "Do not show again" checkbox (default: ``false``)
%     - ``.DoNotShowAgainText`` — [char] checkbox label (default: ``'Do not show again'``)
%     - ``.HelpUrl`` — [char] URL/.html (opened in the browser) or a base-workspace command;
%           when provided a Help button is shown at the bottom-left (default: ``[]``)
%     - ``.HelpBtnText`` — [char] Help button label (default: ``'Help'``)
%
% Output Arguments:
%   - **selection** — [char] label of the pressed button; ``''`` when the dialog is
%     closed or cancelled and no Cancel button exists.
%   - **dontShowAgain** — [logical] state of the "Do not show again" checkbox
%     (``false`` when the checkbox is disabled or the dialog is cancelled).
%
% Usage example:
%
%   .. code-block:: matlab
%
%      opt = struct();
%      opt.WindowStyle = 'modal';
%      opt.Icon = 'warning_48px';
%      opt.DoNotShowAgain = true;
%      opt.WindowHeight = 250;
%      [answer, dontShow] = utils.dlgs.inputQuestDlg(obj.view.gui, ...
%          'Overwrite existing file?', 'Overwrite', 'Yes', 'No', 'No', opt);
%      if strcmp(answer, 'Yes')
%          % overwrite the file
%      end
%

% ---------- Parse optional options struct (last arg) ----------
options = struct();
if ~isempty(varargin) && isstruct(varargin{end})
    options = varargin{end};
    varargin(end) = [];
end

% Defaults
if ~isfield(options, 'mibPath'); options.mibPath = ''; end
if ~isfield(options, 'WindowWidth'); options.WindowWidth = 420; end
if ~isfield(options, 'WindowHeight'); options.WindowHeight = 160; end
if ~isfield(options, 'WindowStyle'); options.WindowStyle = 'modal'; end
if ~isfield(options, 'Icon'); options.Icon = 'puffin_question'; end
if ~isfield(options, 'IconWidth'); options.IconWidth = dlgIconDefaultWidth(options.Icon); end
if ~isfield(options, 'ParentFigure'); options.ParentFigure = []; end
if ~isfield(options, 'DefaultKey'); options.DefaultKey = 'default'; end
if ~isfield(options, 'FontSize'); options.FontSize = 14; end
if ~isfield(options, 'ButtonFontSize'); options.ButtonFontSize = 12; end
if ~isfield(options, 'DoNotShowAgain'); options.DoNotShowAgain = false; end
if ~isfield(options, 'DoNotShowAgainText'); options.DoNotShowAgainText = 'Do not show again'; end
if ~isfield(options, 'HelpUrl'); options.HelpUrl = []; end             % when set, a Help button is shown (bottom-left)
if ~isfield(options, 'HelpBtnText'); options.HelpBtnText = 'Help'; end % Help button label

% ---------- Resolve mibDir and the parent window (shared helper caches) ----------
mibDir = dlgResolveMibDir(options.mibPath);

% ParentFigure first-param takes priority over options.ParentFigure and the cached handle
options.ParentFigure = dlgResolveParent(ParentFigure, options.ParentFigure);

% ---------- Normalize question ----------
if iscell(question)
    try
        qStr = char(strjoin(string(question(:)), newline));
    catch
        qStr = strjoin(question(:), sprintf('\n'));
    end
else
    qStr = char(string(question));
end
qLines = regexp(qStr, '\n', 'split');

% ---------- Parse questdlg-like positional args ----------
dlgTitle = 'Question';
btn1 = []; btn2 = []; btn3 = [];
defaultBtn = '';
twoButtonForm = false;

n = numel(varargin);
if n >= 1
    dlgTitle = varargin{1};
end

if n == 0
    % default: Yes/No/Cancel
elseif n == 1
    % only title
elseif n == 3
    % title, btn1, btn2   -> 2 buttons (no default specified here)
    btn1 = varargin{2}; btn2 = varargin{3};
    twoButtonForm = true;
elseif n == 4
    % title, btn1, btn2, defaultBtn  -> 2 buttons + default (this is your main use case)
    btn1 = varargin{2}; btn2 = varargin{3}; defaultBtn = varargin{4};
    twoButtonForm = true;
elseif n == 5
    % title, btn1, btn2, btn3, defaultBtn -> 3 buttons + default
    btn1 = varargin{2}; btn2 = varargin{3}; btn3 = varargin{4}; defaultBtn = varargin{5};
else
    error('inputQuestDlg:TooManyInputs', 'Too many input arguments.');
end

dlgTitle = char(string(dlgTitle));

% Determine buttons
if isempty(btn1) && isempty(btn2) && isempty(btn3)
    buttons = {'Yes','No','Cancel'};
elseif twoButtonForm
    buttons = {char(btn1), char(btn2)};   % IMPORTANT: no Cancel button in 2-button form
elseif ~isempty(btn1) && ~isempty(btn2) && ~isempty(btn3)
    buttons = {char(btn1), char(btn2), char(btn3)};
else
    buttons = {'Yes','No','Cancel'};
end

% Determine default button
if isempty(defaultBtn)
    defaultBtn = buttons{1};
else
    defaultBtn = char(defaultBtn);
    if ~any(strcmp(buttons, defaultBtn))
        defaultBtn = buttons{1};
    end
end

% Cancel label: only if there is a Cancel button
cancelLabel = '';
if any(strcmp(buttons, 'Cancel'))
    cancelLabel = 'Cancel';
end

% ---------- Create uifigure ----------
selection = '';
dontShowAgain = false;

% Reuse a cached hidden figure when available; a temporary (non-cached) shell
% must be deleted on close instead of hidden
[fig, isCachedFigure] = dlgAcquireFigure('inputQuestDlg', dlgTitle, mibDir);
if strcmpi(options.WindowStyle, 'modal')
    fig.WindowStyle = 'modal';
else
    fig.WindowStyle = 'normal';
end

% ---- Layout constants ----
btnGap  = 8;
btnH    = 24;
nBtn    = numel(buttons);

% Auto-size each button to its own label so long text isn't clipped.
% Rough estimate: ~0.65 px per character per font-size point, plus button
% frame padding. Floor at 100 px so short labels keep the original look.
charWidthEst = options.ButtonFontSize * 0.65;
btnPaddingPx = 6;
btnWidths = zeros(1, nBtn);
for iBtn = 1:nBtn
    btnWidths(iBtn) = max(100, ceil(numel(char(buttons{iBtn})) * charWidthEst + btnPaddingPx));
end
btnsTotalW = sum(btnWidths) + (nBtn - 1) * btnGap;

% optional Help button (bottom-left); width 0 when not requested
helpBtnW = 0;
if ~isempty(options.HelpUrl)
    helpBtnW = max(80, ceil(numel(char(options.HelpBtnText)) * charWidthEst + btnPaddingPx));
end

iconW = options.IconWidth;

% Grow the dialog width when buttons would otherwise crowd the question
% text. Required width = buttons + icon column + outer/inner paddings.
neededWidth = btnsTotalW + helpBtnW + iconW + 48;
if options.WindowWidth < neededWidth
    options.WindowWidth = neededWidth;
end

% Center on the parent and apply the geometry in a single Position write
% (after the width grow above, so the grown width actually takes effect)
xy = dlgCenterOnParent(options.ParentFigure, options.WindowWidth, options.WindowHeight);
newPosition = fig.Position;
if ~isempty(xy); newPosition(1:2) = xy; end
newPosition(3:4) = [options.WindowWidth, options.WindowHeight];
fig.Position = newPosition;

% Bottom row height: single row with checkbox and buttons side by side
bottomRowH = btnH + 8;

% ---- Outer grid: content row (flex) + bottom row (fixed) ----
outerGrid = uigridlayout(fig, [2, 1]);
outerGrid.RowHeight   = {'1x', bottomRowH};
outerGrid.ColumnWidth = {'1x'};
outerGrid.Padding     = [8, 8, 8, 8];
outerGrid.RowSpacing  = 8;
outerGrid.ColumnSpacing  = 8;

% ---- Content area: icon column (fixed) + text column (flex) ----
% Icon loading: composited against the figure background and cached by the
% shared helper, so the uiimage receives a pre-blended uint8 array.
[iconImg, iconW] = dlgLoadIcon(options.Icon, iconW, fig.Color, mibDir);

contentGrid = uigridlayout(outerGrid, [1, 2]);
contentGrid.Layout.Row    = 1;
contentGrid.Layout.Column = 1;
contentGrid.ColumnWidth   = {iconW, '1x'};
contentGrid.RowHeight     = {'1x'};
contentGrid.Padding       = [0, 0, 0, 0];
contentGrid.ColumnSpacing = 18;

% Icon (uiimage with pre-composited alpha — no axes toolbar artifacts)
if ~isempty(iconImg)
    iconUI = uiimage(contentGrid, 'ImageSource', iconImg);
    iconUI.Layout.Row         = 1;
    iconUI.Layout.Column      = 1;
    iconUI.VerticalAlignment   = 'top';
    iconUI.HorizontalAlignment = 'left';
end

% Question text label
txtLabel = uilabel(contentGrid);
txtLabel.Layout.Row        = 1;
txtLabel.Layout.Column     = 2;
txtLabel.Text              = strjoin(qLines, newline);
txtLabel.WordWrap          = 'on';
txtLabel.FontSize          = options.FontSize;
txtLabel.VerticalAlignment = 'top';

% ---- Bottom area: Help button (left) + checkbox (flex) + action buttons (right) ----
bottomGrid = uigridlayout(outerGrid, [1, 3]);
bottomGrid.RowHeight    = {btnH};
bottomGrid.Layout.Row    = 2;
bottomGrid.Layout.Column = 1;
bottomGrid.ColumnWidth   = {helpBtnW, '1x', btnsTotalW};
bottomGrid.Padding       = [0, 0, 0, 0];
bottomGrid.ColumnSpacing = 8;

% Help button (row 1, col 1) — shown only when options.HelpUrl is set
if ~isempty(options.HelpUrl)
    helpBtn = uibutton(bottomGrid, 'push');
    helpBtn.Layout.Row      = 1;
    helpBtn.Layout.Column   = 1;
    helpBtn.Text            = options.HelpBtnText;
    helpBtn.FontSize        = options.ButtonFontSize;
    helpBtn.ButtonPushedFcn = @(~,~) onHelp();
end

% "Do not show again" checkbox (row 1, col 2)
chk = [];
if options.DoNotShowAgain
    chk = uicheckbox(bottomGrid);
    chk.Layout.Row    = 1;
    chk.Layout.Column = 2;
    chk.Text          = options.DoNotShowAgainText;
    chk.Value         = false;
    chk.FontSize      = 10;
end

% Buttons sub-grid (row 1, col 3)
btnGrid = uigridlayout(bottomGrid, [1, nBtn]);
btnGrid.Layout.Row    = 1;
btnGrid.Layout.Column = 3;
btnGrid.ColumnWidth   = num2cell(btnWidths);
btnGrid.RowHeight     = {btnH};
btnGrid.Padding       = [0, 0, 0, 0];
btnGrid.ColumnSpacing = btnGap;

btnHandles = gobjects(nBtn, 1);
for i = 1:nBtn
    btnHandles(i) = uibutton(btnGrid, 'push');
    btnHandles(i).Layout.Row      = 1;
    btnHandles(i).Layout.Column   = i;
    btnHandles(i).Text            = buttons{i};
    btnHandles(i).Tooltip         = buttons{i};
    btnHandles(i).FontSize        = options.ButtonFontSize;
    btnHandles(i).ButtonPushedFcn = @onButton;
    if strcmp(buttons{i}, defaultBtn)
        btnHandles(i).FontWeight = 'bold';
    end
end

% Wire callbacks after layout is built
fig.WindowKeyPressFcn = @onKey;
fig.CloseRequestFcn   = @onClose;

% Show figure after layout is fully built
fig.Visible = 'on';
drawnow;   % realize the figure before re-applying WindowStyle

% Re-apply WindowStyle on the realized (visible) figure — setting it while a
% cached figure is hidden does not take effect (notably in the deployed web
% engine), so the dialog would otherwise come up non-modal on reuse.
if strcmpi(options.WindowStyle, 'modal'); fig.WindowStyle = 'modal'; else; fig.WindowStyle = 'normal'; end

% Focus the default button
idx = find(strcmp(buttons, defaultBtn), 1, 'first');
if ~isempty(idx)
    try; focus(btnHandles(idx)); catch; end
end

% Block caller until dialog is closed
uiwait(fig);

% ---------- Nested callbacks ----------
    function storeDontShow()
        if ~isempty(chk) && isvalid(chk)
            dontShowAgain = chk.Value;
        else
            dontShowAgain = false;
        end
    end

    function onButton(src, ~)
        selection = src.Text;
        storeDontShow();
        closeDialog();
    end

    function onHelp()
        % open options.HelpUrl: a web URL/.html in the browser, otherwise run it
        % as a base-workspace command (mirrors utils.dlgs.inputUniversalDlg).
        H = options.HelpUrl;
        if ischar(H) || isstring(H)
            H = char(H);
            if strncmpi(H, 'http', 4) || contains(H, '.html')
                web(H, '-browser');
            else
                try
                    evalin('base', H);
                catch err
                    utils.dlgs.showErrorDialog(options.ParentFigure, err);
                end
            end
        end
    end

    function doCancel()
        if ~isempty(cancelLabel)
            selection = cancelLabel;
        else
            selection = '';
        end
        storeDontShow();
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

    function onClose(~, ~)
        doCancel();
    end

    function onKey(~, evt)
        if strcmp(evt.Key, 'escape')
            doCancel();
            return;
        end
        if strcmp(evt.Key, 'return') || strcmp(evt.Key, 'enter')
            if strcmpi(options.DefaultKey, 'cancel')
                doCancel();
            else
                id = find(strcmp(buttons, defaultBtn), 1, 'first');
                if isempty(id); id = 1; end
                onButton(btnHandles(id), []);
            end
        end
    end
end
