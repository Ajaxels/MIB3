function [answer, selectedIndices, dontShowAgain] = mibInputUniversalDlg(mibPath, prompts, defAns, dlgTitle, options)
% [answer, selectedIndices, dontShowAgain] = mibInputUniversalDlg(mibPath, prompts, defAns, dlgTitle, options)
% uifigure + uigridlayout version of mibInputMultiDlg with extra widget types
%
% Parameters:
% mibPath: [optional] a char with a path to MIB installation, use
% MibContrller.mibPath or MibModel.mibPath to get it, or just an empty cell: [].
% prompts: a cell array {n x 1} with the prompts for each input field of the dialog.
% defaultAns: a cell array {n x 1} with default values for each entry.
% The following types are supported per element
% - '' or 'some text' or string scalar -> text box (uieditfield text).
% - numeric scalar or empty numeric -> numeric edit field (uieditfield numeric).
% - struct('Spinner', true, 'Value', v, 'Limits', [min max], 'Step', s, 'Round', true/false) -> spinner (uispinner).
% - cell array of strings or char -> combo box (uidropdown), with last element numeric as default index.
% - true/false -> checkbox (uicheckbox).
% - NaN (numeric NaN) -> placeholder row: only the prompt is shown without an input widget.
% - string starting with '<html>' -> uihtml component for rich text display.
%
% dlgTitle: dialog window title string.
%
% options: optional struct with fields:
% .WindowStyle  - 'normal' (default) or 'modal'.
% .PromptLines  - scalar or array (numel(prompts)) of integers specifying wrapped title line heights for prompts.
% .Header        - string, text displayed above widgets.
% .HeaderLines   - integer number of lines reserved for Header.
% .WindowWidth  - dialog width in pixels (default 560).
% .WindowHeight - dialog height in pixels (default: auto-calculated based on content, min 200, max 800).
% .Columns      - integer number of columns (default 1).
% .IconWidth    - width of icon column in pixels (default [], i.e. use the size of the image).
% .MainColumnWidths - cell array of main grid column widths, e.g., {'1x', '2x'} for 2 columns (default: equal '1x' for all).
% .SectionsColumnWidths - cell array specifying label/widget column proportions for each main column,
%                         e.g., for 2 main columns: {'1x', '2x', '1x', '2x'} means
%                         col1 has label:widget = 1x:2x, col2 has label:widget = 1x:2x (default: all 'fit' and '1x').
% .LastItemColumns - 1 to force last entry to span all columns, 0 otherwise (default 0).
% .Focus        - 1-based index of widget to focus on open (default 1).
% .OkBtnText    - text for OK button (default 'OK').
% .HelpBtnText  - text for Help button (default 'Help').
% .HelpUrl      - string URL or command; if provided, shows Help button.
% .MsgBoxOnly   - logical, show dialog as a message box with only OK button and single html content (default false).
% .Icon         - 'question' (default), 'celebrate', 'call4help', 'warning'.
% .DoNotShowAgain - logical, show "Do not show again" checkbox (default false).
% .DoNotShowAgainText    - text for the "Do not show again" checkbox (default 'Do not show again').
% .ParentFigure - handle to parent figure; if provided, dialog is centered on parent window (default: []).
% .DefaultKey  - which button to trigger on Enter/Return key: 'OK' (default) or 'Cancel'.
%
% Return values:
% answer: a cell array with entered values (or empty when canceled). For dropdowns, value is the selected string; numeric edit returns double; spinner returns double; checkbox returns logical.
% selectedIndices: a vector of selected indices for dropdowns; 1 for non-dropdown items; empty when canceled.
% dontShowAgain: logical state of the "Do not show again" checkbox (false when canceled).
%
% Example 1 (input dialog with all widget types):
%   prompts = {
%     'Enter a text:'
%     'Select an option'
%     'Are you sure?'
%     'placeholder, remove text to make empty'
%     'Long prompt that wraps and occupies multiple lines'
%     'Multi-line text input (3 lines):'  % <-- This will get a text area
%     'Numeric value'
%     'Iterations (spinner)'
%   };
%   defAns = {
%     'my test string'                                        % text edit
%     {'Option 1','Option 2','Option 3', 2}                   % dropdown, default index 2
%     true                                                     % checkbox
%     NaN                                                      % placeholder row
%     ''                                                       % text edit with long label
%     sprintf('Line 1\nLine 2\nLine 3')                        % multi-line text (3 lines)
%     3.14                                                     % numeric edit field
%     struct('Spinner', true, 'Value', 5, 'Limits', [1 100], 'Step', 1, 'Round', true) % spinner
%   };
%   options.PromptLines  = [1 1 1 1 2 3 1 1];  %
%   dlgTitle = 'multi line input dialog';
%   options.WindowStyle  = 'normal';
%   options.Header        = 'My test Input dialog';
%   options.HeaderLines   = 2;
%   options.WindowWidth  = 672;
%   options.WindowHeight = 350;
%   options.IconWidth    = [];
%   options.Columns      = 2;
%   options.MainColumnWidths = {'1x', '2x'};
%   options.SectionsColumnWidths = {'1x', '2x', '1x', '3x'};
%   options.Focus        = 1;
%   options.HelpUrl      = 'http://mib.helsinki.fi';
%   options.LastItemColumns = 1;
%   options.MsgBoxOnly   = false;
%   options.Icon         = 'question_48px';
%   options.OkBtnText    = 'Proceed';
%   options.HelpBtnText  = 'Help';
%   options.DoNotShowAgain = true;
%   options.DoNotShowAgainText    = 'Do not show again';
%   options.DefaultKey   = 'OK';
%   options.ParentFigure = obj.view.gui;
%   [answer, selIndex, dontShow] = utils.dlgs.mibInputUniversalDlg(obj.mibPath, prompts, defAns, dlgTitle, options);
%   if isempty(answer); return; end
%
% Example 2 (message box with HTML content):
%   htmlContent = '<html><body><h3>Important Message</h3><p>This is a message box with <b>rich text</b> formatting.</p><ul><li>Item 1</li><li>Item 2</li></ul></body></html>';
%   dlgTitle = 'Information';
%   options.MsgBoxOnly = true;
%   options.Header = 'Please Read';
%   options.OkBtnText = 'OK';
%   options.Icon = 'question_48px';
%   options.DoNotShowAgain = true;
%   options.DoNotShowAgainText = 'Do not show this again';
%   options.ParentFigure = obj.view.gui;
%   [answer, selIndex, dontShow] = utils.dlgs.mibInputUniversalDlg(obj.mibPath, {}, {htmlContent}, dlgTitle, options);

arguments
    mibPath char = ''
    prompts cell = {'Enter a text:'}
    defAns cell = {[]}
    dlgTitle char = 'Universal Input Dialog'
    options struct = struct
end

persistent mibDir
% Initialize persistent variable on first call or update it with input
if isempty(mibDir) && ~isempty(mibPath)
    if isdeployed
        [~, result] = system('path');
        toks = regexp(result, 'Path=(.*?);', 'tokens', 'once');
        if ~isempty(toks); mibDir = char(toks{1}); else; mibDir = pwd; end
    else
        mibDir = fileparts(which('mib'));
        if isempty(mibDir); mibDir = pwd; end
    end
elseif ~isempty(mibPath)
    mibDir = mibPath;
end

% Defaults
if ~isfield(options, 'Icon'); options.Icon = 'question'; end
if ~isfield(options, 'WindowStyle'); options.WindowStyle = 'normal'; end
if ~isfield(options, 'Columns'); options.Columns = 1; end
if ~isfield(options, 'IconWidth'); options.IconWidth = []; end
if ~isfield(options, 'MainColumnWidths'); options.MainColumnWidths = repmat({'1x'}, 1, options.Columns); end
if ~isfield(options, 'SectionsColumnWidths'); options.SectionsColumnWidths = repmat({'fit', '1x'}, 1, options.Columns); end
if ~isfield(options, 'Focus'); options.Focus = 1; end
if ~isfield(options, 'LastItemColumns'); options.LastItemColumns = 0; end
if ~isfield(options, 'OkBtnText'); options.OkBtnText = 'OK'; end
if ~isfield(options, 'HelpBtnText'); options.HelpBtnText = 'Help'; end
if ~isfield(options, 'HelpUrl'); options.HelpUrl = []; end
if ~isfield(options, 'MsgBoxOnly'); options.MsgBoxOnly = false; end
if ~isfield(options, 'PromptLines'); options.PromptLines = ones(numel(prompts),1); end
if ~isfield(options, 'HeaderLines'); options.HeaderLines = 1; end
if ~isfield(options, 'WindowWidth'); options.WindowWidth = 560; end
if ~isfield(options, 'WindowHeight'); options.WindowHeight = []; end
if ~isfield(options, 'DoNotShowAgain'); options.DoNotShowAgain = false; end
if ~isfield(options, 'DoNotShowAgainText'); options.DoNotShowAgainText = 'Do not show again'; end
if ~isfield(options, 'ParentFigure'); options.ParentFigure = []; end
if ~isfield(options, 'DefaultKey'); options.DefaultKey = 'OK'; end

% Normalize PromptLines
if numel(options.PromptLines) == 1 %#ok<ISCL>
    PromptLines = repmat(options.PromptLines, numel(prompts), 1);
else
    PromptLines = options.PromptLines(:);
end

% Normalize MainColumnWidths
if numel(options.MainColumnWidths) ~= options.Columns
    options.MainColumnWidths = repmat({'1x'}, 1, options.Columns);
end

% Normalize SectionsColumnWidths (should be 2 * Columns entries: label, widget for each column)
if numel(options.SectionsColumnWidths) ~= 2 * options.Columns
    options.SectionsColumnWidths = repmat({'fit', '1x'}, 1, options.Columns);
end

% Build figure (before icon loading to get background color)
fig = uifigure('Name', dlgTitle, 'Visible', 'off');
fig.Icon = fullfile(mibDir, 'assets', 'icons', 'mib_icon_16px.png');
fig.Tag = 'mibInputUniversalDlg';
if strcmpi(options.WindowStyle,'modal'); fig.WindowStyle='modal'; else; fig.WindowStyle='normal'; end
fig.Position(3) = max(420, round(options.WindowWidth));

% Calculate or set height
if isempty(options.WindowHeight)
    numRegular = numel(prompts) - (options.LastItemColumns == 1 && ~options.MsgBoxOnly);
    if options.MsgBoxOnly
        itemsPerCol = 1;  % Only one row for message box
    else
        itemsPerCol = max(1, ceil(numRegular / options.Columns));
    end
    options.WindowHeight = 100 + (itemsPerCol * 35) + 50;
    fig.Position(4) = max(100, min(800, options.WindowHeight));
else
    fig.Position(4) = max(100, options.WindowHeight);
end

% Center dialog on parent figure if provided
if ~isempty(options.ParentFigure) && isvalid(options.ParentFigure)
    try
        if isa(options.ParentFigure, 'matlab.ui.container.internal.AppContainer')
            parentPos = options.ParentFigure.WindowBounds;  % [x y w h]
        elseif isa(options.ParentFigure, 'matlab.ui.Figure')
            parentPos = options.ParentFigure.Position;      % [x y w h]
        end

        % Center in parent's coordinates (bottom-left origin)
        x1 = parentPos(1) + (parentPos(3) - options.WindowWidth)  / 2;
        y1 = parentPos(2) + (parentPos(4) - options.WindowHeight) / 2;

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

% Icon selection and loading
switch options.Icon
    case 'warning_48px',   iconFilename = 'warning_48px.png';        
    case 'question_48px',  iconFilename = 'question_48px.png';
    case 'celebrate', iconFilename = 'celebrate.jpg';
    case 'call4help', iconFilename = 'call4help.jpg';
    otherwise,        iconFilename = 'question_48px.png';
end
iconPath = fullfile(mibDir, 'assets', 'images', iconFilename);

% Determine if we have a header
hasHeader = isfield(options,'Header') && ~isempty(options.Header);

% Main grid structure: icon column + content columns
totalCols = 1 + options.Columns;
if isempty(options.IconWidth)
    mainColWidths = ['fit', options.MainColumnWidths]; % Icon column with specified width (numeric)
else    
    mainColWidths = [{options.IconWidth}, options.MainColumnWidths]; % Icon column with specified width (numeric)
end

if hasHeader
    % 3 rows: Header row, content row, button row
    mainGrid = uigridlayout(fig, [3, totalCols], ...
        'RowHeight', {'fit', '1x', 24}, ...
        'ColumnWidth', mainColWidths,...
        'Padding', [10 10 10 10], 'RowSpacing', 10, 'ColumnSpacing', 12);
    titleRow = 1;
    contentRow = 2;
    buttonRow = 3;
else
    % 2 rows: icon&content row, button row
    mainGrid = uigridlayout(fig, [2, totalCols], ...
        'RowHeight', {'1x', 24}, ...
        'ColumnWidth', mainColWidths, ...
        'Padding', [10 10 10 10], 'RowSpacing', 10, 'ColumnSpacing', 12);
    titleRow = 1;
    contentRow = 1;
    buttonRow = 2;
end

% Row 1, Column 1: Icon
if exist(iconPath, 'file')
    iconUI = uiimage(mainGrid, 'ImageSource', iconPath, 'ScaleMethod', 'fit');
    if hasHeader
        % Span icon from header row to content row
        iconUI.Layout.Row = [titleRow contentRow];
    else
        iconUI.Layout.Row = titleRow;
    end
    iconUI.Layout.Column = 1;
    iconUI.VerticalAlignment = 'top';
    iconUI.HorizontalAlignment = 'left';
else
    emptyIconLbl = uilabel(mainGrid, 'Text', '');
    if hasHeader
        emptyIconLbl.Layout.Row = [titleRow contentRow];
    else
        emptyIconLbl.Layout.Row = titleRow;
    end
    emptyIconLbl.Layout.Column = 1;
end

% Add Header text if specified
if hasHeader
    headerLabel = uilabel(mainGrid, 'Text', options.Header, ...
        'FontSize', 12, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'left', ...
        'VerticalAlignment', 'top', ...
        'WordWrap', 'on');
    headerLabel.Layout.Row = titleRow;
    headerLabel.Layout.Column = 2:totalCols;  % Span all content columns
end

% Prepare outputs
n = numel(prompts);
answer = defAns;
selectedIndices = ones(n,1);
widgets = gobjects(n,1);
isPlaceholder = false(n,1);
isCheckbox = false(n,1);
isDropdown = false(n,1);
isNumericEdit = false(n,1);
isSpinner = false(n,1);
isHtml = false(n,1);

% Message box mode: single row with HTML content
if options.MsgBoxOnly
    % Create single content grid spanning all content columns
    htmlGrid = uigridlayout(mainGrid, [1 1], 'RowHeight', {'1x'}, ...
        'ColumnWidth', {'1x'}, 'RowSpacing', 6, 'ColumnSpacing', 8, 'Padding', [0 0 0 0]);
    htmlGrid.Scrollable = 'on';
    htmlGrid.Layout.Row = contentRow;
    % Span properly whether single or multiple content columns
    if totalCols > 2
        htmlGrid.Layout.Column = [2 totalCols];
    else
        htmlGrid.Layout.Column = 2;
    end

    % Add HTML content
    if ~isempty(defAns) && ~isempty(defAns{1})
        htmlContent = defAns{1};
        if ischar(htmlContent) || isstring(htmlContent)
            htmlContent = char(htmlContent);
            % Check if content starts with <html> tag
            if contains(lower(strtrim(htmlContent)), '<html')
                % Wrap with proper HTML structure if not already complete
                if ~contains(lower(htmlContent), '<!doctype')
                    % Add DOCTYPE and style with sans-serif font
                    htmlContent = ['<!DOCTYPE html><html><head><style>body{font-family: sans-serif;}</style></head>' ...
                        regexprep(htmlContent, '<html[^>]*>', '') '</html>'];
                elseif ~contains(lower(htmlContent), 'font-family')
                    % Add sans-serif font style if DOCTYPE exists but no font specified
                    htmlContent = strrep(htmlContent, '<html>', '<html><head><style>body{font-family: sans-serif;}</style></head>');
                end
                html = uihtml(htmlGrid, 'HTMLSource', htmlContent);
                isHtml(1) = true;
                widgets(1) = html;
            else
                % Plain text in label
                lbl = uilabel(htmlGrid, 'Text', htmlContent, 'WordWrap', 'on');
                widgets(1) = lbl;
            end
        end
    end
else
    % Normal mode: create column grids for content
    colGrids = cell(options.Columns, 1);
    colRowCounters = zeros(options.Columns, 1);
    for c = 1:options.Columns
        % Get label and widget column widths for this column
        labelWidth = options.SectionsColumnWidths{2*c - 1};
        widgetWidth = options.SectionsColumnWidths{2*c};

        % Create scrollable content grid for this column
        colGrids{c} = uigridlayout(mainGrid, [1 2], 'RowHeight', {'fit'}, ...
            'ColumnWidth', {labelWidth, widgetWidth}, 'RowSpacing', 6, 'ColumnSpacing', 8, 'Padding', [0 0 0 0]);
        colGrids{c}.Scrollable = 'on';
        colGrids{c}.Layout.Row = contentRow;
        colGrids{c}.Layout.Column = c + 1;
        colRowCounters(c) = 1;
    end

    % Distribute items into columns
    numRegular = n - (options.LastItemColumns == 1);
    itemsPerCol = max(1, ceil(numRegular / options.Columns));

    % Build widgets
    regIdx = 0;
    for i = 1:n
        isLastSpanning = (options.LastItemColumns == 1 && i == n);

        % Select parent grid
        if isLastSpanning
            regIdx = regIdx + 1;
            colIdx = 1;
            par = colGrids{colIdx};
            currentRow = colRowCounters(colIdx);
            if currentRow > numel(par.RowHeight)
                par.RowHeight{end+1} = 'fit';
            end
            colRowCounters(colIdx) = colRowCounters(colIdx) + 1;
        else
            regIdx = regIdx + 1;
            colIdx = min(options.Columns, ceil(regIdx / itemsPerCol));
            par = colGrids{colIdx};

            currentRow = colRowCounters(colIdx);
            if currentRow > numel(par.RowHeight)
                par.RowHeight{end+1} = 'fit';
            end
            colRowCounters(colIdx) = colRowCounters(colIdx) + 1;
        end

        % Detect placeholder (NaN)
        if isnumeric(defAns{i}) && isscalar(defAns{i}) && isnan(defAns{i})
            isPlaceholder(i) = true;
        end

        % Placeholder: spans both columns
        if isPlaceholder(i)
            lab = uilabel(par, 'Text', prompts{i}, 'HorizontalAlignment', 'left', 'WordWrap', 'on');
            lab.Layout.Row = currentRow;
            lab.Layout.Column = [1 2];
            continue;
        end

        % Checkbox entry: label in left column, checkbox without text in right column
        if islogical(defAns{i}) && isscalar(defAns{i})
            isCheckbox(i) = true;

            % Label in column 1
            lab = uilabel(par, 'Text', prompts{i}, 'HorizontalAlignment', 'right', ...
                'VerticalAlignment', 'top', 'WordWrap', 'on');
            lab.Layout.Row = currentRow;
            lab.Layout.Column = 1;

            % Wrapper grid for checkbox with fixed height
            wrapperGrid = uigridlayout(par, [1 1], 'RowHeight', {22}, 'ColumnWidth', {'1x'}, 'Padding', [0 0 0 0]);
            wrapperGrid.Layout.Row = currentRow;
            wrapperGrid.Layout.Column = 2;

            cb = uicheckbox(wrapperGrid, 'Text', '', 'Value', defAns{i});
            widgets(i) = cb;
            continue;
        end

        % Label in column 1
        lab = uilabel(par, 'Text', prompts{i}, 'HorizontalAlignment', 'right', ...
            'VerticalAlignment', 'top', 'WordWrap', 'on');
        lab.Layout.Row = currentRow;
        lab.Layout.Column = 1;

        % Create wrapper grid for widget with fixed or variable height based on PromptLines
        if PromptLines(i) > 1
            % Multi-line text input: use textarea with height based on PromptLines
            widgetHeight = 22 * PromptLines(i);  % 22 pixels per line
            wrapperGrid = uigridlayout(par, [1 1], 'RowHeight', {widgetHeight}, 'ColumnWidth', {'1x'}, 'Padding', [0 0 0 0]);
        else
            % Single-line input: fixed 22 pixel height
            wrapperGrid = uigridlayout(par, [1 1], 'RowHeight', {22}, 'ColumnWidth', {'1x'}, 'Padding', [0 0 0 0]);
        end
        wrapperGrid.Layout.Row = currentRow;
        wrapperGrid.Layout.Column = 2;

        % Determine control type and create widget
        ctrl = [];
        val = defAns{i};

        if iscell(val)
            isDropdown(i) = true;
            entries = val;
            selIdx = 1;
            if ~isempty(val) && isnumeric(val{end}) && isscalar(val{end})
                selIdx = max(1, min(numel(val)-1, val{end}));
                entries = val(1:end-1);
            end
            ctrl = uidropdown(wrapperGrid, 'Items', entries, 'Value', entries{selIdx});
            selectedIndices(i) = selIdx;

        elseif isstruct(val) && isfield(val,'Spinner') && val.Spinner
            isSpinner(i) = true;
            v = 0; lo = -inf; hi = inf; step = 1; roundVals = false;
            if isfield(val,'Value'); v = val.Value; end
            if isfield(val,'Limits'); lo = val.Limits(1); hi = val.Limits(2); end
            if isfield(val,'Step'); step = val.Step; end
            if isfield(val,'Round'); roundVals = val.Round; end
            ctrl = uispinner(wrapperGrid, 'Limits', [lo hi], 'Value', v, 'Step', step, 'RoundFractionalValues', roundVals);
        else
            % Check if it's numeric ONLY if non-empty or explicitly a number
            if isnumeric(val) && isscalar(val) && ~isempty(val)
                isNumericEdit(i) = true;
                ctrl = uieditfield(wrapperGrid, 'numeric', 'Value', double(val), 'ValueDisplayFormat','%.3f');
            else
                % Everything else is text input: use textarea for multi-line, uieditfield for single-line
                if isempty(val); val = ''; end
                if PromptLines(i) > 1
                    % Multi-line textarea
                    ctrl = uitextarea(wrapperGrid, 'Value', char(val));
                else
                    % Single-line edit field
                    ctrl = uieditfield(wrapperGrid, 'text', 'Value', char(val));
                end
            end
        end

        widgets(i) = ctrl;
    end
end

% Button row spanning all columns
btnRow = uigridlayout(mainGrid, [1 4], 'ColumnWidth', {'fit','fit','1x','fit'}, ...
    'ColumnSpacing', 8, 'Padding', [0 0 0 0], 'RowHeight', {24});
btnRow.Layout.Row = buttonRow;
btnRow.Layout.Column = [1 totalCols];

% Button components
helpBtn = [];
if ~isempty(options.HelpUrl)
    helpBtn = uibutton(btnRow, 'Text', options.HelpBtnText, 'ButtonPushedFcn', @(~,~) onHelp());
    helpBtn.Layout.Row = 1;
    helpBtn.Layout.Column = 1;
else
    emptyLbl1 = uilabel(btnRow, 'Text', '');
    emptyLbl1.Layout.Row = 1;
    emptyLbl1.Layout.Column = 1;
end

% Do not show again checkbox (only if enabled)
if options.DoNotShowAgain
    chkDontShow = uicheckbox(btnRow, 'Text', options.DoNotShowAgainText, 'Value', false);
    chkDontShow.Layout.Row = 1;
    chkDontShow.Layout.Column = 2;
else
    emptyLbl1_5 = uilabel(btnRow, 'Text', '');
    emptyLbl1_5.Layout.Row = 1;
    emptyLbl1_5.Layout.Column = 2;
    chkDontShow = [];
end

% Spacer
emptyLbl2 = uilabel(btnRow, 'Text', '');
emptyLbl2.Layout.Row = 1;
emptyLbl2.Layout.Column = 3;

% OK and Cancel in a sub-grid (only OK for message box mode)
if options.MsgBoxOnly
    btnBox = uigridlayout(btnRow, [1 1], 'ColumnWidth', {50}, 'ColumnSpacing', 8, 'Padding', [0 0 0 0]);
    btnBox.Layout.Row = 1;
    btnBox.Layout.Column = 4;
    okBtn = uibutton(btnBox, 'Text', options.OkBtnText, 'ButtonPushedFcn', @(~,~) onOK());
    cancelBtn = [];
else
    btnBox = uigridlayout(btnRow, [1 2], 'ColumnWidth', {'fit','fit'}, 'ColumnSpacing', 8, 'Padding', [0 0 0 0]);
    btnBox.Layout.Row = 1;
    btnBox.Layout.Column = 4;
    okBtn = uibutton(btnBox, 'Text', options.OkBtnText, 'ButtonPushedFcn', @(~,~) onOK());
    cancelBtn = uibutton(btnBox, 'Text', 'Cancel', 'ButtonPushedFcn', @(~,~) onCancel());
end

% Key handling (Esc for Cancel, Enter for OK)
fig.WindowKeyPressFcn = @(~, evt) onKey(evt);

% Show figure
drawnow;
fig.Visible = 'on';

% Set focus after figure is visible
if options.MsgBoxOnly
    % In message box mode, focus on OK button to enable Enter key
    try
        focus(okBtn);
    catch
    end
else
    % In normal mode, focus on specified widget
    if numel(widgets) >= options.Focus
        tgt = widgets(options.Focus);
        if ~isempty(tgt) && isvalid(tgt) && tgt ~= 0
            try
                focus(tgt);
            catch
            end
        end
    end
end

% Initialize outputs
answer = {};
selectedIndices = [];
dontShowAgain = false;

% Wait for user
uiwait(fig);

% ---------------- end of the main function ----------------

% Callbacks
    function onHelp()
        H = options.HelpUrl;
        if ischar(H) || isstring(H)
            H = char(H);
            if strncmpi(H,'http',4) || contains(H,'.html')
                web(H,'-browser');
            else
                try, evalin('base', H); catch, try, eval(H); catch, end, end
            end
        end
    end

    function onOK()
        out = cell(n,1);
        sel = ones(n,1);
        for k = 1:n
            if isPlaceholder(k)
                out{k} = [];
                continue;
            end
            w = widgets(k);
            % Check if widget is valid and not a placeholder
            if ~isvalid(w) || isequal(w,0) || isa(w, 'matlab.graphics.GraphicsPlaceholder')
                out{k} = [];
                continue;
            end
            % Handle different widget types
            if isHtml(k) || isa(w, 'matlab.ui.control.HTML')
                % uihtml doesn't have a value to extract
                out{k} = [];
            elseif isa(w, 'matlab.ui.control.Label')
                % Label widget - no value to extract
                out{k} = [];
            elseif isa(w, 'matlab.ui.control.TextArea')
                % TextArea widget - returns cell array, convert to char
                out{k} = strjoin(w.Value, newline);
            elseif isDropdown(k)
                items = w.Items;
                out{k} = w.Value;
                idx = find(strcmp(items, w.Value), 1, 'first');
                if isempty(idx); idx = 1; end
                sel(k) = idx;
            elseif isCheckbox(k)
                out{k} = logical(w.Value);
            elseif isSpinner(k)
                out{k} = double(w.Value);
            elseif isNumericEdit(k)
                out{k} = double(w.Value);
            elseif isprop(w, 'Value')
                % Generic widget with Value property
                out{k} = char(w.Value);
            else
                out{k} = [];
            end
        end
        answer = out;
        selectedIndices = sel;
        if options.DoNotShowAgain && ~isempty(chkDontShow) && isvalid(chkDontShow)
            dontShowAgain = logical(chkDontShow.Value);
        end
        uiresume(fig);
        delete(fig);
    end

    function onCancel()
        answer = {};
        selectedIndices = [];
        if options.DoNotShowAgain && ~isempty(chkDontShow)
            dontShowAgain = logical(chkDontShow.Value);
        end
        uiresume(fig);
        delete(fig);
    end

    function onKey(evt)
        CurrentKey = evt.Key;
        if isequal(CurrentKey, 'escape')
            if ~isempty(cancelBtn) && isvalid(cancelBtn)
                onCancel();
            else
                % In MsgBoxOnly mode, Escape closes like OK
                onOK();
            end
        end
        if isequal(CurrentKey, 'return')
            % Check which button to trigger based on DefaultKey option
            if strcmpi(options.DefaultKey, 'Cancel') && ~isempty(cancelBtn) && isvalid(cancelBtn)
                onCancel();
            else
                focus(okBtn);  % Move focus to button, commits editfield value
                pause(0.1);
                onOK();  % Default to OK
            end
        end
    end

end
