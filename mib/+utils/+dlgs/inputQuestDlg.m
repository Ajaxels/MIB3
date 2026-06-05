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
if ~isfield(options, 'IconWidth'); options.IconWidth = 48; end
if ~isfield(options, 'ParentFigure'); options.ParentFigure = []; end
if ~isfield(options, 'DefaultKey'); options.DefaultKey = 'default'; end
if ~isfield(options, 'FontSize'); options.FontSize = 14; end
if ~isfield(options, 'ButtonFontSize'); options.ButtonFontSize = 12; end
if ~isfield(options, 'DoNotShowAgain'); options.DoNotShowAgain = false; end
if ~isfield(options, 'DoNotShowAgainText'); options.DoNotShowAgainText = 'Do not show again'; end

% ---------- Resolve mibDir ----------
persistent mibDir
persistent parentFigureHandle   % cached handle to the main GUI window
persistent cachedFigure         % reusable hidden uifigure shell
persistent iconCompositeCache   % dictionary: cacheKey -> composited uint8 image
persistent iconCacheBgColor     % RGB triplet used for compositing

% ParentFigure param takes priority; update cache
% Use isvalid() not ishandle() — AppContainer satisfies isvalid but not ishandle.
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

% Resolve options.ParentFigure from param or cache
if ~isempty(ParentFigure) && isvalid(ParentFigure)
    options.ParentFigure = ParentFigure;
elseif isempty(options.ParentFigure) && ~isempty(parentFigureHandle) && isvalid(parentFigureHandle)
    options.ParentFigure = parentFigureHandle;
elseif ~isempty(options.ParentFigure) && isvalid(options.ParentFigure)
    parentFigureHandle = options.ParentFigure;
end

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

% ---------- Icon path ----------
switch options.Icon
    case 'warning_48px',  iconFilename = 'warning_48px.png';
    case 'question_48px', iconFilename = 'question_48px.png';
    case 'celebrate',     iconFilename =  sprintf('puffin_cheering_%d_220px.png', randi(2));
    case 'call4help',     iconFilename =  sprintf('puffin_call4help_%d_220px.png', randi(3));
    case 'puffin_info'
        iconFilename = sprintf('puffin_info_%d_96px.png', randi(5));
        options.IconWidth = 96;
    case 'puffin_warning'         
        iconFilename = sprintf('puffin_warning_%d_96px.png', randi(3));
        options.IconWidth = 96;
    otherwise  % 'puffin_question
        % get random icon
        iconFilename = sprintf('puffin_quest_%d_96px.png', randi(6));
        options.IconWidth = 96;
end
iconPath = fullfile(mibDir, 'assets', 'images', iconFilename);

% ---------- Create uifigure ----------
selection = '';
dontShowAgain = false;

% Reuse a cached hidden figure when available
if ~isempty(cachedFigure) && isvalid(cachedFigure) && strcmp(cachedFigure.Visible, 'off')
    fig = cachedFigure;
    delete(fig.Children);
    fig.Name = dlgTitle;
    fig.WindowKeyPressFcn = '';
    fig.CloseRequestFcn = 'closereq';
else
    fig = uifigure('Name', dlgTitle, 'Visible', 'off');
    fig.AutoResizeChildren = 'off';
    fig.Tag = 'inputQuestDlg';
    cachedFigure = fig;
end
if strcmpi(options.WindowStyle, 'modal')
    fig.WindowStyle = 'modal';
else
    fig.WindowStyle = 'normal';
end
fig.Position(3) = options.WindowWidth;
fig.Position(4) = options.WindowHeight;

% Center on parent — AppContainer uses WindowBounds (top-left origin);
% uifigure/figure use Position (bottom-left origin).
if ~isempty(options.ParentFigure) && isvalid(options.ParentFigure)
    try
        if isa(options.ParentFigure, 'matlab.ui.container.internal.AppContainer')
            parentPos  = options.ParentFigure.WindowBounds;
            screenSize = get(0, 'ScreenSize');
            x1 = parentPos(1) + (parentPos(3) - options.WindowWidth)  / 2;
            y1 = screenSize(4) - parentPos(2) - parentPos(4) + (parentPos(4) - options.WindowHeight) / 2;
        else
            parentPos = options.ParentFigure.Position;
            x1 = parentPos(1) + (parentPos(3) - options.WindowWidth)  / 2;
            y1 = parentPos(2) + (parentPos(4) - options.WindowHeight) / 2;
        end
        fig.Position(1) = x1;
        fig.Position(2) = y1;
    catch
    end
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

chkH  = 24;
iconW = options.IconWidth;

% Grow the dialog width when buttons would otherwise crowd the question
% text. Required width = buttons + icon column + outer/inner paddings.
neededWidth = btnsTotalW + iconW + 40;
if options.WindowWidth < neededWidth
    options.WindowWidth = neededWidth;
end

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
% Pre-load and alpha-composite the icon before building UI (same pattern
% as inputUniversalDlg, so the uiimage receives a pre-blended uint8 array).
figBgColor = fig.Color;
iconImg = [];
if exist(iconPath, 'file')
    try
        % Initialize icon composite cache
        if isempty(iconCompositeCache)
            iconCompositeCache = configureDictionary("string", "cell");
            iconCacheBgColor = figBgColor;
        end
        % Invalidate cache on background color change (theme switch)
        if ~isequal(iconCacheBgColor, figBgColor)
            iconCompositeCache = configureDictionary("string", "cell");
            iconCacheBgColor = figBgColor;
        end

        cacheKey = string(sprintf('%s_%d', iconFilename, iconW));
        if isKey(iconCompositeCache, cacheKey)
            iconImg = iconCompositeCache{cacheKey};
        else
            [img, ~, alpha] = imread(iconPath);
            if ~isempty(alpha)
                img    = im2double(img);
                alpha  = im2double(alpha);
                for k = 1:3
                    img(:,:,k) = img(:,:,k) .* alpha + figBgColor(k) .* (1 - alpha);
                end
                iconImg = im2uint8(img);
            else
                iconImg = img;
            end
            if ~isempty(iconImg)
                iconImg = imresize(iconImg, [NaN iconW]);
                iconCompositeCache(cacheKey) = {iconImg};
            end
        end
    catch
        iconImg = [];
    end
end

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

% ---- Bottom area: single row with checkbox (left) + buttons (right) ----
bottomGrid = uigridlayout(outerGrid, [1, 2]);
bottomGrid.RowHeight    = {btnH};
bottomGrid.Layout.Row    = 2;
bottomGrid.Layout.Column = 1;
bottomGrid.ColumnWidth   = {'1x', btnsTotalW};
bottomGrid.Padding       = [0, 0, 0, 0];
bottomGrid.ColumnSpacing = 8;

% "Do not show again" checkbox (row 1, col 1)
chk = [];
if options.DoNotShowAgain
    chk = uicheckbox(bottomGrid);
    chk.Layout.Row    = 1;
    chk.Layout.Column = 1;
    chk.Text          = options.DoNotShowAgainText;
    chk.Value         = false;
    chk.FontSize      = 10;
end

% Buttons sub-grid (row 1, col 2)
btnGrid = uigridlayout(bottomGrid, [1, nBtn]);
btnGrid.Layout.Row    = 1;
btnGrid.Layout.Column = 2;
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
drawnow;

% Re-apply WindowStyle on the realized (visible) figure — setting it while a
% cached figure is hidden does not take effect (notably in the deployed web
% engine), so the dialog would otherwise come up non-modal on reuse.
if strcmpi(options.WindowStyle, 'modal'); fig.WindowStyle = 'modal'; else; fig.WindowStyle = 'normal'; end
drawnow;

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
        fig.WindowStyle = 'normal';   % release modal grab before hiding (else parent stays blocked)
        fig.Visible = 'off';
        uiresume(fig);
    end

    function doCancel()
        if ~isempty(cancelLabel)
            selection = cancelLabel;
        else
            selection = '';
        end
        storeDontShow();
        fig.WindowStyle = 'normal';   % release modal grab before hiding
        fig.Visible = 'off';
        uiresume(fig);
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
