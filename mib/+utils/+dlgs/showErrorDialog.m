function showErrorDialog(ParentFigure, err, winTitle, optionalPrefix, optionalSuffix, options)
% SHOWERRORDIALOG - Show an error dialog generated in try/catch blocks or any other occasion.
%
% Syntax:
%   .. code-block:: matlab
%
%       function showErrorDialog(ParentFigure, err, winTitle, optionalPrefix, optionalSuffix, options)
%
% Supports custom icons, HTML formatting, scrollable error text, clipboard
% copy button, and is resizable.
%
% Input Arguments:
%   - **ParentFigure** — handle to the parent window (AppContainer, uifigure, or [])
%     When empty or a legacy GUIDE figure, falls back to errordlg()
%   - **err** — error source, one of:
%
%     - [char|string] plain error message text
%     - [MException] struct with fields:
%
%       - ``.identifier`` — error identifier string
%       - ``.message`` — error message
%       - ``.cause`` — nested ``MException`` cell array
%
%     - empty struct: shows only prefix/suffix
%
%   - **winTitle** — [optional] string with dialog window title (default: ``'Error'``)
%   - **optionalPrefix** — [optional] text shown in bold above the error body (default: ``''``)
%   - **optionalSuffix** — [optional] text shown in italics below the error body (default: ``''``)
%   - **options** *(optional)* — struct with fields:
%
%     - ``.mibPath`` — [char] path to MIB installation for icon loading (default: ``''``)
%     - ``.Icon`` — [char] icon name (default: ``'puffin_error'``):
%       ``'puffin_error'``, ``'puffin_warning'``, ``'puffin_question'``,
%       ``'warning_48px'``, ``'error_48px'``, ``'question_48px'``,
%       ``'celebrate'``, ``'call4help'``
%     - ``.IconWidth`` — [numeric] icon column width in pixels (default: 48, puffins: 96)
%     - ``.WindowWidth`` — [numeric] dialog width in pixels (default: 420)
%     - ``.WindowHeight`` — [numeric] dialog height in pixels (default: 220)
%     - ``.WindowStyle`` — [char] ``'modal'`` (default) or ``'normal'``
%     - ``.PrefixHeight`` — row height for the prefix label (default: ``'fit'``)
%     - ``.ErrorHeight`` — row height for the error text area (default: ``'1x'``)
%     - ``.SuffixHeight`` — row height for the suffix label (default: ``'fit'``)
%
% Output Arguments:
%   (none)
%
% Usage:
%   **Example 1** — Basic usage in try/catch
%
%   .. code-block:: matlab
%
%      try
%          % some code
%      catch err
%          utils.dlgs.showErrorDialog(obj.view.gui, err, 'Processing Error', 'prefix');
%          return;
%      end
%
%   **Example 2** — Plain text with bold prefix and italic suffix
%
%   .. code-block:: matlab
%
%      utils.dlgs.showErrorDialog(obj.view.gui, 'Something went wrong!', 'Error', ...
%          'Operation failed:', 'Please check your input.');
%
%   **Example 3** — Custom icon, size, and row heights
%
%   .. code-block:: matlab
%
%      opts.mibPath      = obj.mibModel.mibPath;
%      opts.Icon         = 'puffin_warning';
%      opts.WindowWidth  = 500;
%      opts.WindowHeight = 300;
%      opts.PrefixHeight = 'fit';
%      opts.ErrorHeight  = '1x';
%      opts.SuffixHeight = 'fit';
%      utils.dlgs.showErrorDialog(obj.view.gui, err, 'Import Error', ...
%          'Failed to load file:', 'Please contact support.', opts);
%
if nargin < 6; options        = struct(); end
if nargin < 5; optionalSuffix = ''; end
if nargin < 4; optionalPrefix = ''; end
if nargin < 3; winTitle       = 'Error'; end

% --- options defaults ---
if ~isfield(options, 'mibPath'); options.mibPath = ''; end
if ~isfield(options, 'Icon');    options.Icon = 'puffin_error'; end
if ~isfield(options, 'IconWidth')
    if ismember(options.Icon, {'puffin_question', 'puffin_warning', 'puffin_error'})
        options.IconWidth = 96;
    else
        options.IconWidth = 48;
    end
end
if ~isfield(options, 'WindowWidth');  options.WindowWidth  = 500; end
if ~isfield(options, 'WindowHeight'); options.WindowHeight = 220; end
if ~isfield(options, 'WindowStyle');  options.WindowStyle  = 'modal'; end
if ~isfield(options, 'PrefixHeight'); options.PrefixHeight = 'fit'; end
if ~isfield(options, 'ErrorHeight');  options.ErrorHeight  = '1x'; end
if ~isfield(options, 'SuffixHeight'); options.SuffixHeight = 'fit'; end

% --- resolve mibDir ---
persistent mibDir
if isempty(mibDir) && isempty(options.mibPath)
    if isdeployed
        [~, result] = system('path');
        toks = regexp(result, 'Path=(.*?);', 'tokens', 'once');
        if ~isempty(toks); mibDir = char(toks{1}); else; mibDir = pwd; end
    else
        mibDir = fileparts(which('mib3'));
        if isempty(mibDir); mibDir = pwd; end
    end
elseif ~isempty(options.mibPath)
    mibDir = options.mibPath;
end

% --- build plain error body (for clipboard and fallback) ---
if ischar(err) || isstring(err)
    errBody = strtrim(char(err));
elseif isempty(err) || isempty(fieldnames(err))
    errBody = '';
else
    if ~isempty(err.cause)
        errBody = sprintf('%s\n\n%s\n\n%s', ...
            err.identifier, err.message, err.cause{1}.message);
    else
        errBody = sprintf('%s\n\n%s', err.identifier, err.message);
    end
    % Append formatted stack trace
    if ~isempty(err.stack)
        stackLines = cell(numel(err.stack), 1);
        for stackIdx = 1:numel(err.stack)
            [~, stackFilename, stackExt] = fileparts(err.stack(stackIdx).file);
            stackLines{stackIdx} = sprintf('  [%d] %s  (%s%s, line %d)', ...
                stackIdx, err.stack(stackIdx).name, stackFilename, stackExt, err.stack(stackIdx).line);
        end
        errBody = sprintf('%s\n\nStack trace:\n%s', errBody, strjoin(stackLines, newline));
    end
end
errBody = strtrim(errBody);

% full plain text for clipboard (includes title, prefix, body, suffix)
clipboardText = strjoin(cellfun(@strtrim, ...
    {winTitle, optionalPrefix, errBody, optionalSuffix}, 'UniformOutput', false), newline);
clipboardText = strtrim(clipboardText);

% --- fallback for empty ParentFigure ---
if isempty(ParentFigure) 
    errordlg(clipboardText, winTitle);
    return;
end

% --- icon selection ---
switch options.Icon
    case 'warning_48px';     iconFilename = 'warning_48px.png';
    case 'question_48px';    iconFilename = 'question_48px.png';
    case 'celebrate';        iconFilename =  sprintf('puffin_cheering_%d_220px.png', randi(2));
    case 'call4help',        iconFilename =  sprintf('puffin_call4help_%d_220px.png', randi(3));
    case 'puffin_error';     iconFilename = sprintf('puffin_error_%d_96px.png', randi(4));
    case 'puffin_warning';   iconFilename = sprintf('puffin_warning_%d_96px.png', randi(3));
    case 'puffin_question';  iconFilename = sprintf('puffin_quest_%d_96px.png', randi(7));
    otherwise % 'error_48px'
        iconFilename = 'error_48px.png';
end
iconPath = fullfile(mibDir, 'assets', 'images', iconFilename);

% --- determine which optional rows are needed ---
hasPrefix = ~isempty(strtrim(optionalPrefix));
hasSuffix = ~isempty(strtrim(optionalSuffix));
hasError  = ~isempty(errBody);  % NEW: skip textarea when errBody is empty

% build row heights dynamically — only include prefix/error/suffix rows if needed
rowHeights = {};
rowMap     = struct();   % maps logical sections to row indices
currentRow = 1;

if hasPrefix
    rowHeights{end+1}  = options.PrefixHeight;
    rowMap.prefix      = currentRow;
    currentRow         = currentRow + 1;
end

if hasError
    rowHeights{end+1} = options.ErrorHeight;
    rowMap.errBody    = currentRow;
    currentRow        = currentRow + 1;
end

if hasSuffix
    rowHeights{end+1} = options.SuffixHeight;
    rowMap.suffix     = currentRow;
    currentRow        = currentRow + 1;
end

rowHeights{end+1} = 26;                    % button row
rowMap.buttons    = currentRow;

% --- build dialog ---
fig = uifigure(...
    'Name',        winTitle, ...
    'Visible',     'off', ...
    'WindowStyle', lower(options.WindowStyle), ...
    'Resize',      'on');
fig.Icon     = fullfile(mibDir, 'assets', 'icons', 'mib_icon_16px.png');
fig.Position(3:4) = [options.WindowWidth, options.WindowHeight];

mainGrid = uigridlayout(fig, [numel(rowHeights), 2], ...
    'RowHeight',    rowHeights, ...
    'ColumnWidth',  {options.IconWidth, '1x'}, ...
    'Padding',      [12 12 12 12], ...
    'RowSpacing',   8, ...
    'ColumnSpacing', 14);

% --- icon — spans all rows ---
if exist(iconPath, 'file')
    iconUI = uiimage(mainGrid, ...
        'ImageSource',         iconPath, ...
        'ScaleMethod',         'fit', ...
        'VerticalAlignment',   'top', ...
        'HorizontalAlignment', 'left');
    iconUI.Layout.Row    = [1, numel(rowHeights)];
    iconUI.Layout.Column = 1;
else
    ph = uilabel(mainGrid, 'Text', '');
    ph.Layout.Row    = [1, numel(rowHeights)];
    ph.Layout.Column = 1;
end

% --- prefix label (bold) ---
if hasPrefix
    prefixLbl = uilabel(mainGrid, ...
        'Text',                sprintf('<b>%s</b>', strtrim(optionalPrefix)), ...
        'Interpreter',         'html', ...
        'WordWrap',            'on', ...
        'FontName',            'Arial', ...
        'FontSize',            12, ...
        'VerticalAlignment',   'top', ...
        'HorizontalAlignment', 'left');
    prefixLbl.Layout.Row    = rowMap.prefix;
    prefixLbl.Layout.Column = 2;
end

% --- scrollable error textarea (only when errBody is non-empty) ---
if hasError
    errArea = uitextarea(mainGrid, ...
        'Value',    errBody, ...
        'FontName', 'Courier New', ...
        'FontSize', 12, ...
        'Editable', 'off', ...
        'BackgroundColor', [1 1 1]);
    errArea.Layout.Row    = rowMap.errBody;
    errArea.Layout.Column = 2;
end

% --- suffix label (italic/normal) ---
if hasSuffix
    suffixLbl = uilabel(mainGrid, ...
        'Text',                sprintf('%s', strtrim(optionalSuffix)), ...
        'Interpreter',         'html', ...
        'WordWrap',            'on', ...
        'FontName',            'Arial', ...
        'FontSize',            12, ...
        'FontColor',           [0.4 0.4 0.4], ...
        'VerticalAlignment',   'top', ...
        'HorizontalAlignment', 'left');
    suffixLbl.Layout.Row    = rowMap.suffix;
    suffixLbl.Layout.Column = 2;
end

% --- button row: [spacer] [Copy] [OK] ---
btnGrid = uigridlayout(mainGrid, [1 3], ...
    'ColumnWidth',  {'1x', 110, 80}, ...
    'ColumnSpacing', 8, ...
    'Padding',      [0 0 0 0]);
btnGrid.Layout.Row    = rowMap.buttons;
btnGrid.Layout.Column = 2;

uilabel(btnGrid, 'Text', '');    % spacer

copyBtn = uibutton(btnGrid, 'Text', 'Copy to Clipboard', ...
    'ButtonPushedFcn', @(~,~) onCopy());
copyBtn.Layout.Column = 2;

okBtn = uibutton(btnGrid, 'Text', 'OK', ...
    'ButtonPushedFcn', @(~,~) onClose());
okBtn.Layout.Column = 3;

% key handling
fig.WindowKeyPressFcn = @(~, evt) onKey(evt);

% --- center on parent ---
try
    if isa(ParentFigure, 'matlab.ui.container.internal.AppContainer')
        parentPos  = ParentFigure.WindowBounds;
        screenSize = get(0, 'ScreenSize');
        x1 = parentPos(1) + (parentPos(3) - options.WindowWidth)  / 2;
        y1 = screenSize(4) - parentPos(2) - parentPos(4) + (parentPos(4) - options.WindowHeight) / 2;
    elseif isa(ParentFigure, 'matlab.ui.Figure')
        parentPos = ParentFigure.Position;
        x1 = parentPos(1) + (parentPos(3) - options.WindowWidth)  / 2;
        y1 = parentPos(2) + (parentPos(4) - options.WindowHeight) / 2;
    end
    fig.Position(1) = x1;
    fig.Position(2) = y1;
catch
    % use MATLAB default position on failure
end

drawnow;
fig.Visible = 'on';
focus(okBtn);
uiwait(fig);

% --- nested callbacks ---
    function onClose()
        uiresume(fig);
        delete(fig);
    end

    function onCopy()
        clipboard('copy', clipboardText);
        copyBtn.Text = '✓ Copied!';
        pause(0.8);
        if isvalid(copyBtn)
            copyBtn.Text = 'Copy to Clipboard';
        end
    end

    function onKey(evt)
        if ismember(evt.Key, {'return', 'escape', 'space'})
            onClose();
        end
    end

end
