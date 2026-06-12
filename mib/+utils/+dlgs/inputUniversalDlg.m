function [answer, selectedIndices, dontShowAgain] = inputUniversalDlg(ParentFigure, header, prompts, defAns, dlgTitle, options)
% INPUTUNIVERSALDLG - Multi-widget input dialog built on ``uifigure`` + ``uigridlayout``.
%
% Supports text fields, numeric fields, spinners, dropdowns, checkboxes,
% placeholders, and HTML display widgets. Replaces ``mibInputMultiDlg``.
%
% Syntax:
%   .. code-block:: matlab
%
%       [answer, selectedIndices, dontShowAgain] = ...
%           inputUniversalDlg(ParentFigure, header, prompts, defAns, dlgTitle)
%       [answer, selectedIndices, dontShowAgain] = ...
%           inputUniversalDlg(ParentFigure, header, prompts, defAns, dlgTitle, options)
%
% Input Arguments:
%   - **ParentFigure** — handle to the parent window (AppContainer, uifigure, or ``[]``);
%     used to centre the dialog. Pass ``[]`` to use the cached handle from a prior call.
%     In MIB controllers / model methods pass ``obj.mibModel.getProgressBarParent()``
%     (or ``obj.getProgressBarParent()`` inside MibModel) so the dialog follows the
%     active dataset window when it is undocked.
%   - **header** *(optional)* — [char] bold label shown above all widgets.
%     Supersedes ``options.Header`` when non-empty.
%   - **prompts** — ``{n x 1}`` cell array of prompt strings, one per widget row.
%   - **defAns** — ``{n x 1}`` cell array of default values; supported types per element:
%
%     - ``''``, ``'text'``, or string scalar → text edit (``uieditfield``)
%     - numeric scalar or ``[]`` → numeric edit field (``uieditfield``)
%     - ``struct('Spinner',true,'Value',v,'Limits',[lo hi],'Step',s,'Round',tf)``
%       → spinner (``uispinner``)
%     - cell array of strings with a numeric last element (default index)
%       → dropdown (``uidropdown``)
%     - ``true`` / ``false`` → checkbox (``uicheckbox``)
%     - ``NaN`` → placeholder row (prompt only, no widget)
%     - string starting with ``'<html>'`` → rich-text display (``uihtml``)
%
%   - **dlgTitle** — [char|string] dialog window title.
%   - **options** *(optional)* — struct with configuration fields:
%
%     - ``.Columns`` — [integer] number of widget columns (default: ``1``)
%     - ``.DefaultKey`` — [char] button triggered by Enter: ``'OK'`` (default) or ``'Cancel'``
%     - ``.DoNotShowAgain`` — [logical] show "Do not show again" checkbox (default: ``false``)
%     - ``.DoNotShowAgainText`` — [char] checkbox label (default: ``'Do not show again'``)
%     - ``.Focus`` — [integer] 1-based index of widget to focus on open;
%       ``0`` = focus the OK button (default: ``0``)
%     - ``.Header`` — [char] text above widgets; superseded by the ``header`` parameter
%     - ``.HeaderLines`` — [integer] number of lines reserved for the header
%     - ``.HelpBtnText`` — [char] Help button label (default: ``'Help'``)
%     - ``.HelpUrl`` — [char] URL or command; when provided, the Help button is shown
%     - ``.Icon`` — [char] icon identifier (default: ``'puffin_question'``):
%       ``'puffin_question'``, ``'puffin_warning'``, ``'puffin_info'``,
%       ``'puffin_error'``, ``'puffin_measure'``, ``'puffin_waiting'``,
%       ``'question'``, ``'celebrate'``, ``'call4help'``, ``'warning'``
%     - ``.IconWidth`` — [numeric] icon column width in pixels (default: ``[]``, i.e. use the image's natural width)
%     - ``.LabelPosition`` — [char] ``'left'`` (default, label beside widget) or ``'top'`` (label above widget)
%     - ``.LastItemColumns`` — [integer] ``1`` to force the last widget to span all columns, ``0`` otherwise (default: ``0``)
%     - ``.MainColumnWidths`` — cell array of main-grid column widths, e.g. ``{'1x', '2x'}`` for 2 columns (default: ``'1x'`` for all)
%     - ``.mibPath`` — [char] path to MIB installation
%     - ``.MsgBoxOnly`` — [logical] show as a message-box with a single OK button and one HTML content widget (default: ``false``)
%     - ``.OkBtnText`` — [char] OK button label (default: ``'OK'``)
%     - ``.ParentFigure`` — [handle] parent figure for centering (default: ``[]``)
%     - ``.PromptLines`` — scalar or array of integers specifying wrapped prompt label line heights (one value per prompt)
%     - ``.SectionsColumnWidths`` — cell array of label/widget column proportions for
%       each main column when ``LabelPosition='left'``;
%       e.g. ``{'1x','2x','1x','2x'}`` gives ``label:widget = 1x:2x`` for both columns
%       (default: ``'fit'`` for labels and ``'1x'`` for widgets)
%     - ``.WindowHeight`` — [numeric] dialog height in pixels (default: auto-calculated, min 200, max 800)
%     - ``.WindowStyle`` — [char] ``'normal'`` (default) or ``'modal'``
%     - ``.WindowWidth`` — [numeric] dialog width in pixels (default: 450)
%
% Output Arguments:
%   - **answer** — ``{n x 1}`` cell array of entered values; ``[]`` when cancelled.
%     Dropdowns return the selected string; numeric edits return ``double``;
%     spinners return ``double``; checkboxes return ``logical``.
%   - **selectedIndices** — vector of selected indices for dropdowns;
%     ``1`` for non-dropdown items; ``[]`` when cancelled.
%   - **dontShowAgain** — [logical] state of the "Do not show again" checkbox
%     (``false`` when cancelled).
%
% **Example 1** — Horizontal layout (label on the left, 2 columns, all widget types)
%
% .. code-block:: matlab
%
%    prompts = {'Enter a text:'; 'Select an option'; 'Are you sure?'; ...
%               'placeholder row'; 'Long prompt wrapping over two lines'; ...
%               'Multi-line text (3 lines):'; 'Numeric value'; 'Iterations (spinner)'};
%    defAns  = {'my test string'; ...
%               {'Option 1','Option 2','Option 3', 2}; ...  % dropdown, default index 2
%               true; NaN; ''; ...                          % checkbox, placeholder, editfield
%               sprintf('Line 1\nLine 2\nLine 3'); ...      % multi-line text
%               3.14; ...                                    % numeric edit field
%               struct('Spinner',true,'Value',5,'Limits',[1 100],'Step',1, ...
%                      'Round',true,'ValueDisplayFormat','%d units')};
%    options.PromptLines  = [1 1 1 1 2 3 1 1];
%    options.WindowStyle  = 'normal';
%    options.HeaderLines  = 2;
%    options.WindowWidth  = 672;
%    options.WindowHeight = 350;
%    options.Columns      = 2;
%    options.MainColumnWidths = {'1x', '2x'};
%    options.LabelPosition = 'left';
%    options.SectionsColumnWidths = {'1x', '2x', '1x', '3x'};
%    options.Focus        = 1;
%    options.HelpUrl      = 'http://mib.helsinki.fi';
%    options.LastItemColumns = 1;
%    options.Icon         = 'question_48px';
%    options.OkBtnText    = 'Proceed';
%    options.HelpBtnText  = 'Help';
%    options.DoNotShowAgain = true;
%    options.DefaultKey   = 'OK';
%    options.ParentFigure = obj.view.gui;
%    [answer, selIndex, dontShow] = utils.dlgs.inputUniversalDlg(obj.view.gui, ...
%        'My test Input dialog', prompts, defAns, 'Test Dialog', options);
%    if isempty(answer); return; end
%
% **Example 2** — Vertical layout (label on top, 1 column)
%
% .. code-block:: matlab
%
%    prompts = {'Enter a text:'; 'Select an option'; 'Are you sure?'; 'Numeric value'};
%    defAns  = {'my test string'; {'Option 1','Option 2','Option 3', 2}; true; 3.14};
%    options.WindowStyle  = 'normal';
%    options.Header       = 'Vertical Layout Example';
%    options.WindowWidth  = 400;
%    options.LabelPosition = 'top';
%    options.Icon         = 'question_48px';
%    [answer, selIndex, dontShow] = utils.dlgs.inputUniversalDlg(obj.view.gui, ...
%        '', prompts, defAns, 'Vertical layout dialog', options);
%    if isempty(answer); return; end
%
% **Example 3** — Warning message box (plain-text body, auto-wrapped to HTML)
%
% .. code-block:: matlab
%
%    dlgOpt.MsgBoxOnly  = true;
%    dlgOpt.Icon        = 'puffin_warning';
%    dlgOpt.HeaderLines = 1;
%    utils.dlgs.inputUniversalDlg(obj.mibModel.getProgressBarParent(), 'The models are switched off!', {''}, ...
%        {'Please enable "Enable selection" in Preferences and try again.'}, ...
%        'Models are disabled', dlgOpt);
%
% **Example 4** — Message box with rich HTML body
%
% .. code-block:: matlab
%
%    options.MsgBoxOnly         = true;
%    options.Icon               = 'puffin_info';
%    options.HeaderLines        = 1;
%    options.DoNotShowAgain     = true;
%    options.DoNotShowAgainText = 'Do not show this again';
%    htmlBody = ['<html><p style="font-size:10pt">This message has ' ...
%                '<b>rich text</b> and a list:<ul><li>Item 1</li>' ...
%                '<li>Item 2</li></ul></p></html>'];
%    [answer, selIndex, dontShow] = utils.dlgs.inputUniversalDlg(obj.mibModel.getProgressBarParent(), ...
%        'Please Read', {''}, {htmlBody}, 'Information', options);
%
% **Example 5** — Minimalist warning with everything in the header
%
% .. code-block:: matlab
%
%    dlgOpt.MsgBoxOnly  = true;
%    dlgOpt.Icon        = 'puffin_warning';
%    dlgOpt.HeaderLines = 3;
%    utils.dlgs.inputUniversalDlg(obj.mibModel.getProgressBarParent(), ...
%        sprintf('!!! Warning !!!\n\nThe output format was not selected!'), ...
%        {}, {}, 'Warning', dlgOpt);
%


arguments
    ParentFigure = []
    header char = ''
    prompts cell = {'Enter a text:'}
    defAns cell = {[]}
    dlgTitle char = 'MultiEdit dialog'
    options struct = struct
end

% Normalize options field names to their canonical casing.
% MATLAB struct field lookup is case-sensitive, so options.msgboxonly would be
% silently ignored. This loop finds any supplied field whose name matches a known
% field case-insensitively but differs in case (e.g. 'msgBoxOnly' -> 'MsgBoxOnly')
% and renames it to the canonical form before the defaults section runs.
knownOptionFields = {'Icon','IconWidth','WindowStyle','Columns','MainColumnWidths', ...
    'LabelPosition','SectionsColumnWidths','Focus','LastItemColumns', ...
    'OkBtnText','HelpBtnText','HelpUrl','MsgBoxOnly','PromptLines', ...
    'HeaderLines','Header','WindowWidth','WindowHeight','DoNotShowAgain', ...
    'DoNotShowAgainText','ParentFigure','DefaultKey','mibPath'};
for suppliedFieldCell = fieldnames(options)'
    suppliedField = suppliedFieldCell{1};
    canonicalIdx  = find(strcmpi(knownOptionFields, suppliedField), 1);
    if ~isempty(canonicalIdx) && ~strcmp(suppliedField, knownOptionFields{canonicalIdx})
        % Rename the misspelled/wrong-case field to the canonical name
        options.(knownOptionFields{canonicalIdx}) = options.(suppliedField);
        options = rmfield(options, suppliedField);
    end
end

% Defaults
if ~isfield(options, 'MsgBoxOnly'); options.MsgBoxOnly = false; end
% header parameter always takes priority over options.Header
if ~isempty(header)
    options.Header = header;
end
if ~isfield(options, 'Icon')
    if options.MsgBoxOnly
        options.Icon = 'puffin_error';
    else
        options.Icon = 'puffin_question';
    end
end
if ~isfield(options, 'IconWidth'); options.IconWidth = dlgIconDefaultWidth(options.Icon); end
if ~isfield(options, 'WindowStyle'); options.WindowStyle = 'normal'; end
if ~isfield(options, 'Columns'); options.Columns = 1; end
if ~isfield(options, 'MainColumnWidths'); options.MainColumnWidths = repmat({'1x'}, 1, options.Columns); end
if ~isfield(options, 'LabelPosition'); options.LabelPosition = 'top'; end  % 'top' or 'left'
if ~isfield(options, 'SectionsColumnWidths'); options.SectionsColumnWidths = repmat({'fit', '1x'}, 1, options.Columns); end
if ~isfield(options, 'Focus'); options.Focus = 0; end
if ~isfield(options, 'LastItemColumns'); options.LastItemColumns = 0; end
if ~isfield(options, 'OkBtnText'); options.OkBtnText = 'OK'; end
if ~isfield(options, 'HelpBtnText'); options.HelpBtnText = 'Help'; end
if ~isfield(options, 'HelpUrl'); options.HelpUrl = []; end
if ~isfield(options, 'PromptLines'); options.PromptLines = ones(numel(prompts),1); end
if ~isfield(options, 'HeaderLines')
    options.HeaderLines = 1;
    if options.MsgBoxOnly; options.HeaderLines = 3; end
end
if ~isfield(options, 'WindowWidth'); options.WindowWidth = 450; end
if ~isfield(options, 'WindowHeight'); options.WindowHeight = []; end   % [] = auto-calculate from content
if ~isfield(options, 'DoNotShowAgain'); options.DoNotShowAgain = false; end
if ~isfield(options, 'DoNotShowAgainText'); options.DoNotShowAgainText = 'Do not show again'; end
if ~isfield(options, 'mibPath'); options.mibPath = ''; end
if ~isfield(options, 'ParentFigure'); options.ParentFigure = []; end
% ParentFigure first-param takes priority over options.ParentFigure and the cached handle
options.ParentFigure = dlgResolveParent(ParentFigure, options.ParentFigure);
if ~isfield(options, 'DefaultKey'); options.DefaultKey = 'OK'; end

% In MsgBoxOnly mode auto-wrap plain-text defAns with the standard HTML
% font tag so callers do not need to embed HTML themselves.
if options.MsgBoxOnly && isscalar(defAns) && (ischar(defAns{1}) || isstring(defAns{1})) ...
        && ~strncmpi(strtrim(char(defAns{1})), '<html', 5)
    defAns{1} = sprintf('<html><p style="font-size:10pt">%s</p></html>', strrep(defAns{1}, newline, '<br>'));
end

% Normalize PromptLines
if isscalar(options.PromptLines)
    PromptLines = repmat(options.PromptLines, numel(prompts), 1);
else
    PromptLines = options.PromptLines(:);
end

% Normalize MainColumnWidths
if numel(options.MainColumnWidths) ~= options.Columns
    options.MainColumnWidths = repmat({'1x'}, 1, options.Columns);
end

% Normalize SectionsColumnWidths (should be 2 * Columns entries: label, widget for each column)
% Only used when LabelPosition='left'
if strcmpi(options.LabelPosition, 'left')
    if numel(options.SectionsColumnWidths) ~= 2 * options.Columns
        options.SectionsColumnWidths = repmat({'fit', '1x'}, 1, options.Columns);
    end
end

% MIB path resolution for icons — the helper caches it; options.mibPath refreshes the cache
mibDir = dlgResolveMibDir(options.mibPath);

% Build figure (before icon loading to get background color)
% Reuse a cached hidden figure when available to avoid ~200-400ms uifigure creation cost.
% When isCachedFigure is false the shell is a temporary second instance (the cached
% one is busy showing another dialog) and must be deleted on close, not hidden.
[fig, isCachedFigure] = dlgAcquireFigure('inputUniversalDlg', dlgTitle, mibDir);
if strcmpi(options.WindowStyle,'modal'); fig.WindowStyle='modal'; else; fig.WindowStyle='normal'; end

% Font-aware height of a single widget row (22 px at the factory 12 px font)
rowHeight = dlgRowHeight(fig);

% Determine if we have a header (the header parameter was folded into options.Header above)
hasHeader = isfield(options, 'Header') && ~isempty(options.Header);

% Calculate or set height
if isempty(options.WindowHeight)
    if options.MsgBoxOnly
        % Estimate from header lines plus body lines (text length at ~7 px/char
        % after stripping HTML tags, plus explicit breaks and list items)
        bodyLines = 0;
        if ~isempty(defAns) && ~isempty(defAns{1}) && (ischar(defAns{1}) || isstring(defAns{1}))
            bodyText = char(defAns{1});
            plainText = regexprep(bodyText, '<[^>]*>', '');
            charsPerLine = max(20, floor((options.WindowWidth - 140) / 7));
            bodyLines = ceil(numel(plainText) / charsPerLine) ...
                + numel(strfind(lower(bodyText), '<br')) ...
                + numel(strfind(lower(bodyText), '<li'));
            % block elements (<p>, <ul>, <ol>) render with extra vertical margins
            bodyLines = bodyLines + numel(strfind(lower(bodyText), '<p')) ...
                + numel(strfind(lower(bodyText), '<ul')) ...
                + numel(strfind(lower(bodyText), '<ol'));
        end
        estimatedHeight = (options.HeaderLines + bodyLines) * rowHeight + 110;
        windowHeight = max(150, min(800, estimatedHeight));
    else
        % Per-item heights, distributed into columns the same way the widget builder does
        numRegular = numel(prompts) - (options.LastItemColumns == 1);
        itemsPerCol = max(1, ceil(numRegular / options.Columns));
        columnHeights = zeros(options.Columns, 1);
        for itemIdx = 1:numel(prompts)
            colIdx = min(options.Columns, ceil(itemIdx / itemsPerCol));
            if options.LastItemColumns == 1 && itemIdx == numel(prompts); colIdx = 1; end
            if strcmpi(options.LabelPosition, 'top')
                % label row (its 'fit' height plus the 2px row spacings comes
                % out at roughly one rowHeight) + widget row
                itemHeight = rowHeight * (1 + PromptLines(itemIdx));
            else
                itemHeight = rowHeight * PromptLines(itemIdx) + 6;   % shared row + 6px spacing
            end
            columnHeights(colIdx) = columnHeights(colIdx) + itemHeight;
        end
        % outer padding (20) + content/button row spacing (10) + button row (24)
        estimatedHeight = 54 + max(columnHeights);
        if hasHeader; estimatedHeight = estimatedHeight + options.HeaderLines * rowHeight + 10; end
        windowHeight = max(110, min(800, estimatedHeight));
    end
else
    windowHeight = options.WindowHeight;
end

% Center on the parent and apply the geometry in a single Position write
xy = dlgCenterOnParent(options.ParentFigure, options.WindowWidth, windowHeight);
newPosition = fig.Position;
if ~isempty(xy); newPosition(1:2) = xy; end
newPosition(3:4) = [options.WindowWidth, windowHeight];
fig.Position = newPosition;

% Icon loading: composited against the figure background and cached by the helper
[iconImg, iconImgWidth] = dlgLoadIcon(options.Icon, options.IconWidth, fig.Color, mibDir);

% Main grid structure
totalCols = 1 + options.Columns;
mainColWidths = [{iconImgWidth} options.MainColumnWidths];  % Icon column with specified width

if hasHeader
    % 3 rows: header row, content row, button row
    headerRowHeight = options.HeaderLines * rowHeight;
    mainGrid = uigridlayout(fig, [3 totalCols], ...
        'RowHeight', {headerRowHeight, '1x', 24}, ...
        'ColumnWidth', mainColWidths, ...
        'Padding', [12 10 12 10], 'RowSpacing', 10, 'ColumnSpacing', 12);
    headerRow = 1;
    contentRow = 2;
    buttonRow = 3;
else
    % 2 rows: icon/content row, button row
    mainGrid = uigridlayout(fig, [2 totalCols], ...
        'RowHeight', {'1x', 24}, ...
        'ColumnWidth', mainColWidths, ...
        'Padding', [12 10 12 10], 'RowSpacing', 10, 'ColumnSpacing', 12);
    headerRow = 1;
    contentRow = 1;
    buttonRow = 2;
end

% Column 1: Icon — spans header+content rows when header present so it isn't clipped
if ~isempty(iconImg)
    iconUI = uiimage(mainGrid, 'ImageSource', iconImg);
    if hasHeader
        iconUI.Layout.Row = [headerRow contentRow];  % span header and content rows
    else
        iconUI.Layout.Row = contentRow;
    end
    iconUI.Layout.Column = 1;
    iconUI.VerticalAlignment = 'top';
    iconUI.HorizontalAlignment = 'left';
else
    emptyIconLbl = uilabel(mainGrid, 'Text', '');
    emptyIconLbl.Layout.Row = headerRow;
    emptyIconLbl.Layout.Column = 1;
end

% Row 1: Header spanning content columns (if header exists)
if hasHeader
    headerLbl = uilabel(mainGrid, 'Text', options.Header, 'WordWrap', 'on', 'FontWeight', 'bold');
    headerLbl.Layout.Row = headerRow;
    % Span columns 2 to N+1, or just column 2 if only one content column
    if totalCols > 2
        headerLbl.Layout.Column = [2 totalCols];
    else
        headerLbl.Layout.Column = 2;
    end
end

% Widget bookkeeping (the answer/selectedIndices outputs are initialized just before uiwait)
n = numel(prompts);
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
                    htmlContent = ['<!DOCTYPE html><html><head><style>body{font-family: sans-serif;font-size: 10pt}</style></head>' ...
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
    
    if strcmpi(options.LabelPosition, 'top')
        % Vertical layout: labels above widgets (1 column, dynamic rows)
        for c = 1:options.Columns
            % Create scrollable content grid for this column
            colGrids{c} = uigridlayout(mainGrid, [1 1], 'RowHeight', {'fit'}, ...
                'ColumnWidth', {'1x'}, 'RowSpacing', 2, 'ColumnSpacing', 8, 'Padding', [0 0 0 0]);
            colGrids{c}.Scrollable = 'on';
            colGrids{c}.Layout.Row = contentRow;
            colGrids{c}.Layout.Column = c + 1;
            colRowCounters(c) = 1;
        end
    else
        % Horizontal layout: labels left of widgets (2 columns per grid)
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
    end
    
    % Distribute items into columns
    numRegular = n - (options.LastItemColumns == 1);
    itemsPerCol = max(1, ceil(numRegular / options.Columns));
    
    % Build widgets — each widget is parented directly into the column grid using a
    % fixed-height row (no per-widget wrapper grids: saves one container per row)
    regIdx = 0;
    for i = 1:n
        isLastSpanning = (options.LastItemColumns == 1 && i == n);

        % Select parent grid
        regIdx = regIdx + 1;
        if isLastSpanning
            colIdx = 1;
        else
            colIdx = min(options.Columns, ceil(regIdx / itemsPerCol));
        end
        par = colGrids{colIdx};
        currentRow = colRowCounters(colIdx);

        % Detect placeholder (NaN)
        if isnumeric(defAns{i}) && isscalar(defAns{i}) && isnan(defAns{i})
            isPlaceholder(i) = true;
        end

        % Placeholder: a single label row spanning the grid
        if isPlaceholder(i)
            if currentRow > numel(par.RowHeight)
                par.RowHeight{end+1} = 'fit';
            end
            lab = uilabel(par, 'Text', prompts{i}, 'HorizontalAlignment', 'left', 'WordWrap', 'on');
            lab.Layout.Row = currentRow;
            if strcmpi(options.LabelPosition, 'top')
                lab.Layout.Column = 1;
            else
                lab.Layout.Column = [1 2];
            end
            colRowCounters(colIdx) = colRowCounters(colIdx) + 1;
            continue;
        end

        isCheckbox(i) = islogical(defAns{i}) && isscalar(defAns{i});

        % Height of the widget row: PromptLines(i) text lines for multi-line widgets
        if PromptLines(i) > 1 && ~isCheckbox(i)
            widgetHeight = rowHeight * PromptLines(i);
        else
            widgetHeight = rowHeight;
        end

        if strcmpi(options.LabelPosition, 'top')
            % === VERTICAL LAYOUT: label row ('fit') above a fixed-height widget row ===
            if currentRow > numel(par.RowHeight)
                par.RowHeight{end+1} = 'fit';  % Label row
            end
            lab = uilabel(par, 'Text', prompts{i}, 'HorizontalAlignment', 'left', ...
                'VerticalAlignment', 'bottom', 'WordWrap', 'on');
            lab.Layout.Row = currentRow;
            lab.Layout.Column = 1;

            % Widget goes into the next, fixed-height row
            currentRow = currentRow + 1;
            if currentRow > numel(par.RowHeight)
                par.RowHeight{end+1} = widgetHeight;
            else
                par.RowHeight{currentRow} = widgetHeight;
            end
            colRowCounters(colIdx) = currentRow + 1;
            widgetColumn = 1;
        else
            % === HORIZONTAL LAYOUT: label left of widget, sharing one row ===
            % Single-line rows stay 'fit' (they grow when the label wraps);
            % multi-line rows are fixed to PromptLines(i) text lines
            if PromptLines(i) > 1
                rowSpec = widgetHeight;
            else
                rowSpec = 'fit';
            end
            if currentRow > numel(par.RowHeight)
                par.RowHeight{end+1} = rowSpec;
            else
                par.RowHeight{currentRow} = rowSpec;
            end
            colRowCounters(colIdx) = colRowCounters(colIdx) + 1;

            lab = uilabel(par, 'Text', prompts{i}, 'HorizontalAlignment', 'right', ...
                'VerticalAlignment', 'top', 'WordWrap', 'on');
            lab.Layout.Row = currentRow;
            lab.Layout.Column = 1;
            widgetColumn = 2;
        end

        % Determine control type and create the widget (common for both layouts)
        val = defAns{i};
        if isCheckbox(i)
            ctrl = uicheckbox(par, 'Text', '', 'Value', defAns{i});

        elseif iscell(val)
            % Dropdown
            isDropdown(i) = true;
            entries = val;
            selIdx = 1;
            if ~isempty(val) && isnumeric(val{end}) && isscalar(val{end})
                selIdx = max(1, min(numel(val)-1, val{end}));
                entries = val(1:end-1);
            end
            ctrl = uidropdown(par, 'Items', entries, 'Value', entries{selIdx});

        elseif isstruct(val) && isfield(val,'Spinner') && val.Spinner
            % Spinner
            isSpinner(i) = true;
            v = 0; lo = -Inf; hi = Inf; step = 1;
            if isfield(val,'Value'); v = val.Value; end
            if isfield(val,'Limits'); lo = val.Limits(1); hi = val.Limits(2); end
            if isfield(val,'Step'); step = val.Step; end

            ctrl = uispinner(par, 'Limits', [lo hi], 'Value', v, 'Step', step);

            % Handle optional Round and ValueDisplayFormat
            if isfield(val,'Round') && val.Round
                ctrl.RoundFractionalValues = 'on';
            end
            if isfield(val,'ValueDisplayFormat')
                ctrl.ValueDisplayFormat = val.ValueDisplayFormat;
            end

        elseif isnumeric(val) && isscalar(val) && ~isempty(val)
            isNumericEdit(i) = true;
            ctrl = uieditfield(par, 'numeric', 'Value', double(val), 'ValueDisplayFormat','%.3g');

        else
            % Everything else is text input: textarea for multi-line, uieditfield for single-line
            if isempty(val); val = ''; end
            if PromptLines(i) > 1
                ctrl = uitextarea(par, 'Value', char(val));
            else
                ctrl = uieditfield(par, 'text', 'Value', char(val));
            end
        end

        ctrl.Layout.Row = currentRow;
        ctrl.Layout.Column = widgetColumn;
        widgets(i) = ctrl;
    end
end

% Button row spanning all columns
btnRow = uigridlayout(mainGrid, [1 4], 'ColumnWidth', {'fit','fit','1x','fit'}, ...
    'ColumnSpacing', 8, 'Padding', [0 0 0 0], 'RowHeight', {24});
btnRow.Layout.Row = buttonRow;
btnRow.Layout.Column = [1 totalCols];

% Button components
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

% Key handling — WindowKeyPressFcn only; binding KeyPressFcn as well would
% fire the handler twice when the figure itself has keyboard focus
fig.WindowKeyPressFcn = @(~, evt) onKey(evt);
fig.CloseRequestFcn = @(~,~) onCancel();

% show the dialog
fig.Visible = 'on';
drawnow;   % realize the figure before re-applying WindowStyle

% Re-apply WindowStyle on the realized (visible) figure. Setting it while a
% cached figure is hidden does not take effect (notably in the deployed web
% engine), so the dialog would otherwise come up non-modal on reuse.
if strcmpi(options.WindowStyle, 'modal'); fig.WindowStyle = 'modal'; else; fig.WindowStyle = 'normal'; end

% Set focus
if options.MsgBoxOnly || options.Focus == 0
    % Default: focus on OK button to enable Enter key
    try
        focus(okBtn);
    catch
    end
else
    % Explicit Focus index: focus on specified widget
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

% Block caller until dialog is closed (uiwait/uiresume enables figure reuse)
uiwait(fig);

% Callbacks
    function onHelp()
        H = options.HelpUrl;
        if ischar(H) || isstring(H)
            H = char(H);
            if strncmpi(H,'http',4) || contains(H,'.html')
                web(H,'-browser');
            else
                try
                    evalin('base', H)
                catch err
                    utils.dlgs.showErrorDialog(ParentFigure, err);
                end
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
                out{k} = w.Value;
                sel(k) = w.ValueIndex;
            elseif isCheckbox(k)
                out{k} = logical(w.Value);
            elseif isSpinner(k)
                out{k} = double(w.Value);
            elseif isNumericEdit(k)
                out{k} = double(w.Value);
            elseif isprop(w, 'Value')
                % Generic widget with Value property (includes text uieditfield)
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
        closeDialog();
    end

    function onCancel()
        answer = {};
        selectedIndices = [];
        if options.DoNotShowAgain && ~isempty(chkDontShow) && isvalid(chkDontShow)
            dontShowAgain = logical(chkDontShow.Value);
        end
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
            % Move focus away from the current widget so it can commit its
            % pending value (e.g. typed text in a uispinner or uieditfield).
            try; focus(okBtn); catch; end
            drawnow;     % dispatch the focus change to the renderer
            pause(0.1);  % allow the editfield value round-trip to commit before reading
                         % (drawnow alone is too fast: a text uieditfield commits its typed
                         %  value via an async browser round-trip that one drawnow misses)
            if strcmpi(options.DefaultKey, 'Cancel') && ~isempty(cancelBtn) && isvalid(cancelBtn)
                onCancel();
            else
                onOK();
            end
        end
    end

end
