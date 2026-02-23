function [selection, dontShowAgain] = mibQuestDlg(mibPath, question, varargin)
% function [selection, dontShowAgain] = mibQuestDlg(mibPath, question, varargin)
%
% Custom MIB question dialog with the same call syntax as MATLAB questdlg,
% extended with an optional options structure as the last argument.
%
% Parameters:
% mibPath: [char] path to MIB installation folder (use obj.mibPath); may be '' to auto-detect. 
% question: [char|string|cell] question text; when cell, lines are joined with '\n'. 
%
% Questdlg-compatible syntax:
% selection = mibQuestDlg(mibPath, question)
% selection = mibQuestDlg(mibPath, question, dlgTitle)
% selection = mibQuestDlg(mibPath, question, dlgTitle, btn1, btn2)
% selection = mibQuestDlg(mibPath, question, dlgTitle, btn1, btn2, btn3)
% selection = mibQuestDlg(mibPath, question, dlgTitle, btn1, btn2, defaultBtn)              % 2-button form (NO Cancel button)
% selection = mibQuestDlg(mibPath, question, dlgTitle, btn1, btn2, btn3, defaultBtn)        % 3-button form
%
% Extended syntax (optional last argument):
% [selection, dontShowAgain] = mibQuestDlg(..., options)
%
% options: structure with fields (aligned with mibInputSingleDlg/mibInputUniversalDlg style):
% .WindowWidth         - [numeric] width in pixels (default 420)
% .WindowHeight        - [numeric] height in pixels (default 180)
% .WindowStyle         - [char] 'normal' or 'modal' (default 'modal') 
% .Icon                - [char] 'puffin_question' (default), 'puffin_warning', 'question_48px', 'warning_48px', 'celebrate', 'call4help', 
% .IconWidth           - [numeric] icon column width (default 48)
% .ParentFigure        - [handle] parent window to center dialog (default []) 
% .DefaultKey          - [char] 'default' (default) or 'cancel'; Enter triggers default/cancel
% .ButtonFontSize      - [numeric] button font size (default 13)
% .DoNotShowAgain      - [logical] show "Do not show again" checkbox (default false) 
% .DoNotShowAgainText  - [char] checkbox label (default 'Do not show again') 
%
% Return values:
% selection: [char] pressed button label; '' when closed/canceled (and no Cancel button exists). 
% dontShowAgain: [logical] state of "Do not show again" checkbox (false when disabled/canceled). 
%
% Usage example:
% opt = struct();
% opt.WindowStyle = 'modal';
% opt.Icon = 'warning_48px';
% opt.DoNotShowAgain = true;
% opt.ParentFigure = obj.mibGUI;
% opt.WindowHeight = 250;
% [answer, dontShow] = utils.dlgs.mibQuestDlg(obj.mibPath, ...
%     'Overwrite existing file?', 'Overwrite', 'Yes', 'No', 'No', opt);
% if strcmp(answer, 'Yes')
%     % overwrite
% end

% ---------- Parse optional options struct (last arg) ----------
options = struct();
if ~isempty(varargin) && isstruct(varargin{end})
    options = varargin{end};
    varargin(end) = [];
end

% Defaults
if ~isfield(options, 'WindowWidth'); options.WindowWidth = 420; end
if ~isfield(options, 'WindowHeight'); options.WindowHeight = 180; end
if ~isfield(options, 'WindowStyle'); options.WindowStyle = 'modal'; end
if ~isfield(options, 'Icon'); options.Icon = 'puffin_question'; end
if ~isfield(options, 'IconWidth'); options.IconWidth = 48; end
if ~isfield(options, 'ParentFigure'); options.ParentFigure = []; end
if ~isfield(options, 'DefaultKey'); options.DefaultKey = 'default'; end
if ~isfield(options, 'ButtonFontSize'); options.ButtonFontSize = 10; end
if ~isfield(options, 'DoNotShowAgain'); options.DoNotShowAgain = false; end
if ~isfield(options, 'DoNotShowAgainText'); options.DoNotShowAgainText = 'Do not show again'; end

% ---------- Resolve mibDir ----------
persistent mibDir
if isempty(mibDir) && isempty(mibPath)
    if isdeployed
        [~, result] = system('path');
        toks = regexp(result, 'Path=(.*?);', 'tokens', 'once');
        if ~isempty(toks); mibDir = char(toks{1}); else; mibDir = pwd; end
    else
        mibDir = fileparts(which('mib3'));
        if isempty(mibDir); mibDir = pwd; end
    end
elseif ~isempty(mibPath)
    mibDir = mibPath;
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
    error('mibQuestDlg:TooManyInputs', 'Too many input arguments.');
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
    case 'celebrate',     iconFilename = 'celebrate.jpg';
    case 'call4help',     iconFilename = 'call4help.jpg';
    case 'puffin_warning'
        % get random icon
        iconFilename = sprintf('puffin_warning_%d_96px.png', randi(3));
        options.IconWidth = 96;
    otherwise  % 'puffin_question
        % get random icon
        iconFilename = sprintf('puffin_quest_%d_96px.png', randi(6));
        options.IconWidth = 96;
end
iconPath = fullfile(mibDir, 'assets', 'images', iconFilename);

% ---------- Create classic figure ----------
selection = '';
dontShowAgain = false;

fig = figure( ...
    'Name', dlgTitle, ...
    'NumberTitle', 'off', ...
    'MenuBar', 'none', ...
    'ToolBar', 'none', ...
    'Resize', 'off', ...
    'Visible', 'off', ...
    'WindowStyle', options.WindowStyle, ...
    'WindowKeyPressFcn', @onKey, ...      % IMPORTANT: Esc works even when focus is on uicontrols
    'CloseRequestFcn', @onClose);

% Size and position
pos = get(fig, 'Position');
pos(3) = options.WindowWidth;
pos(4) = options.WindowHeight;
set(fig, 'Position', pos);

% Center on parent
if ~isempty(options.ParentFigure) && ishandle(options.ParentFigure)
    try
        parentPos = get(options.ParentFigure, 'Position');
        x1 = parentPos(1) + (parentPos(3) - options.WindowWidth) / 2;
        y1 = parentPos(2) + (parentPos(4) - options.WindowHeight) / 2;
        set(fig, 'Position', [x1 y1 options.WindowWidth options.WindowHeight]);
    catch
    end
end

% Layout constants
pad = 10;
iconW = options.IconWidth;

btnH = 26;
chkH = 18;
gapRow = 6;
bottomH = btnH + (options.DoNotShowAgain * (gapRow + chkH));

textX = pad + iconW + pad;
textW = options.WindowWidth - textX - pad;
textY = pad + bottomH + pad;
textH = options.WindowHeight - textY - pad;

% ---------- Icon: top aligned + alpha ----------
% Place icon at the TOP of the content area; size uses iconW x iconW.
iconH = min(iconW, textH);
iconY = textY + textH - iconH;   % top aligned within the text area

if exist(iconPath, 'file')
    try
        ax = axes('Parent', fig, 'Units', 'pixels', ...
            'Position', [pad, iconY, iconW, iconH], ...
            'XTick', [], 'YTick', [], 'Box', 'off', 'Color', 'none');
        [img, ~, alpha] = imread(iconPath);
        hImg = image(img, 'Parent', ax);
        if ~isempty(alpha)
            set(hImg, 'AlphaData', double(alpha)/255);
        end
        axis(ax, 'image');
        axis(ax, 'off');
    catch
    end
end

% Question text
uicontrol('Parent', fig, 'Style', 'text', ...
    'Units', 'pixels', ...
    'Position', [textX, textY, textW, textH], ...
    'String', qLines, ...
    'HorizontalAlignment', 'left', ...
    'FontSize', 11);

% Buttons row (bottom-right)
btnW = 90;
gap = 8;
nBtn = numel(buttons);
btnTotalW = nBtn*btnW + (nBtn-1)*gap;
btnX0 = options.WindowWidth - pad - btnTotalW;
btnY0 = pad + (options.DoNotShowAgain * (gapRow + chkH));

btnHandles = gobjects(nBtn,1);
for i = 1:nBtn
    x = btnX0 + (i-1)*(btnW+gap);
    btnHandles(i) = uicontrol('Parent', fig, 'Style', 'pushbutton', ...
        'Units', 'pixels', ...
        'Position', [x, btnY0, btnW, btnH], ...
        'String', buttons{i}, ...
        'FontSize', options.ButtonFontSize, ...
        'Callback', @onButton);
    if strcmp(buttons{i}, defaultBtn)
        set(btnHandles(i), 'FontWeight', 'bold');
    end
end

% Do not show again (below buttons, right-aligned to dialog edge)
chk = [];
if options.DoNotShowAgain
    chk = uicontrol('Parent', fig, 'Style', 'checkbox', ...
        'Units', 'pixels', ...
        'Position', [textX, pad, 10, chkH], ...    % temp width; will be corrected using Extent
        'String', options.DoNotShowAgainText, ...
        'Value', 0, ...
        'HorizontalAlignment', 'left', ...
        'FontSize', 10);
    drawnow;
    ext = get(chk, 'Extent');      % [x y w h] in pixels
    chkW = ext(3) + 24;             % a small padding
    chkX = options.WindowWidth - pad - chkW;
    set(chk, 'Position', [chkX, pad, chkW, chkH]);
end

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

        % Optionally clamp to screen
        % screenSize = get(0, 'ScreenSize');
        % x1 = max(0, min(x1, screenSize(3) - options.WindowWidth));
        % y1 = max(0, min(y1, screenSize(4) - options.WindowHeight));

        fig.Position(1) = x1;
        fig.Position(2) = y1;
    catch
        % If centering fails, MATLAB will use default position
    end
end

% Show and focus default
drawnow;
set(fig, 'Visible', 'on');

idx = find(strcmp(buttons, defaultBtn), 1, 'first');
if ~isempty(idx)
    try, uicontrol(btnHandles(idx)); catch, end
end

uiwait(fig);

% ---------- callbacks ----------
    function storeDontShow()
        if ~isempty(chk) && ishandle(chk)
            dontShowAgain = logical(get(chk, 'Value'));
        else
            dontShowAgain = false;
        end
    end

    function onButton(src, ~)
        selection = get(src, 'String');
        storeDontShow();
        uiresume(fig);
        delete(fig);
    end

    function doCancel()
        % Esc equals Cancel option when Cancel exists, otherwise close with ''
        if ~isempty(cancelLabel)
            selection = cancelLabel;
        else
            selection = '';
        end
        storeDontShow();
        uiresume(fig);
        delete(fig);
    end

    function onClose(~, ~)
        doCancel();
    end

    function onKey(~, evt)
        if isprop(evt, 'Key') && strcmp(evt.Key, 'escape')
            doCancel();
            return;
        end
        if isfield(evt, 'Key') && (strcmp(evt.Key, 'return') || strcmp(evt.Key, 'enter'))
            if strcmpi(options.DefaultKey, 'cancel')
                doCancel();
            else
                id = find(strcmp(buttons, defaultBtn), 1, 'first');
                if isempty(id), id = 1; end
                onButton(btnHandles(id), []);
            end
        end
    end
end
