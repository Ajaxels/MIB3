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
% .WindowStyle - 'normal' (default) or 'modal'.
% .PromptLines - scalar or array (numel(prompts)) of integers specifying wrapped title line heights for prompts.
% .Header - string, text displayed above widgets.
% .HeaderLines - integer number of lines reserved for Header.
% .WindowWidth - dialog width in pixels (default 560).
% .WindowHeight - dialog height in pixels (default: auto-calculated based on content, min 200, max 800).
% .Columns - integer number of columns (default 1).
% .IconWidth - width of icon column in pixels (default [], i.e. use the size of the image).
% .MainColumnWidths - cell array of main grid column widths, e.g., {'1x', '2x'} for 2 columns (default: equal '1x' for all).
% .LabelPosition - 'left' (default, horizontal layout) or 'top' (vertical layout, labels above widgets).
% .SectionsColumnWidths - cell array specifying label/widget column proportions for each main column,
%                         used only when LabelPosition='left'. E.g., for 2 main columns: {'1x', '2x', '1x', '2x'} means
%                         col1 has label:widget = 1x:2x, col2 has label:widget = 1x:2x (default: all 'fit' and '1x').
% .LastItemColumns - 1 to force last entry to span all columns, 0 otherwise (default 0).
% .Focus - 1-based index of widget to focus on open (default 1).
% .OkBtnText - text for OK button (default 'OK').
% .HelpBtnText - text for Help button (default 'Help').
% .HelpUrl - string URL or command; if provided, shows Help button.
% .MsgBoxOnly - logical, show dialog as a message box with only OK button and single html content (default false).
% .Icon - 'question' (default), 'celebrate', 'call4help', 'warning'.
% .DoNotShowAgain - logical, show "Do not show again" checkbox (default false).
% .DoNotShowAgainText - text for the "Do not show again" checkbox (default 'Do not show again').
% .ParentFigure - handle to parent figure; if provided, dialog is centered on parent window (default: []).
% .DefaultKey - which button to trigger on Enter/Return key: 'OK' (default) or 'Cancel'.
%
% Return values:
% answer: a cell array with entered values (or empty when canceled). For dropdowns, value is the selected string; numeric edit returns double; spinner returns double; checkbox returns logical.
% selectedIndices: a vector of selected indices for dropdowns; 1 for non-dropdown items; empty when canceled.
% dontShowAgain: logical state of the "Do not show again" checkbox (false when canceled).
%
% Example 1 (input dialog with horizontal layout - label on the left):
% prompts = {
%     'Enter a text:'
%     'Select an option'
%     'Are you sure?'
%     'placeholder, remove text to make empty'
%     'Long prompt that wraps and occupies multiple lines'
%     'Multi-line text input (3 lines):'  % <-- This will get a text area
%     'Numeric value'
%     'Iterations (spinner)'
% };
% defAns = {
%     'my test string'                                        % text edit
%     {'Option 1','Option 2','Option 3', 2}                   % dropdown, default index 2
%     true                                                     % checkbox
%     NaN                                                      % placeholder row
%     ''                                                       % text edit with long label
%     sprintf('Line 1\nLine 2\nLine 3')                       % multi-line text (3 lines)
%     3.14                                                     % numeric edit field
%     struct('Spinner', true, 'Value', 5, 'Limits', [1 100], 'Step', 1, 'Round', true, 'ValueDisplayFormat', '%d units') % spinner
% };
% options.PromptLines  = [1 1 1 1 2 3 1 1];  %
% dlgTitle = 'multi line input dialog';
% options.WindowStyle  = 'normal';
% options.Header       = 'My test Input dialog';
% options.HeaderLines  = 2;
% options.WindowWidth  = 672;
% options.WindowHeight = 350;
% options.IconWidth    = [];
% options.Columns      = 2;
% options.MainColumnWidths = {'1x', '2x'};
% options.LabelPosition = 'left'; % or top
% options.SectionsColumnWidths = {'1x', '2x', '1x', '3x'};
% options.Focus        = 1;
% options.HelpUrl      = 'http://mib.helsinki.fi';
% options.LastItemColumns = 1;
% options.MsgBoxOnly   = false;
% options.Icon         = 'question_48px';
% options.OkBtnText    = 'Proceed';
% options.HelpBtnText  = 'Help';
% options.DoNotShowAgain = true;
% options.DoNotShowAgainText    = 'Do not show again';
% options.DefaultKey   = 'OK';
% options.ParentFigure = obj.view.gui;
% [answer, selIndex, dontShow] = utils.dlgs.mibInputUniversalDlg(obj.mibPath, prompts, defAns, dlgTitle, options);
% if isempty(answer); return; end
%
% Example 2 (input dialog with vertical layout - label on top):
% prompts = {
%     'Enter a text:'
%     'Select an option'
%     'Are you sure?'
%     'Numeric value'
% };
% defAns = {
%     'my test string'                                        % text edit
%     {'Option 1','Option 2','Option 3', 2}                   % dropdown, default index 2
%     true                                                     % checkbox
%     3.14                                                     % numeric edit field
% };
% dlgTitle = 'Vertical layout dialog';
% options.WindowStyle  = 'normal';
% options.Header       = 'Vertical Layout Example';
% options.WindowWidth  = 400;
% options.LabelPosition = 'top';
% options.Columns      = 1;
% options.Icon         = 'question_48px';
% [answer, selIndex, dontShow] = utils.dlgs.mibInputUniversalDlg(obj.mibPath, prompts, defAns, dlgTitle, options);
% if isempty(answer); return; end
%
% Example 3 (message box with HTML content):
% htmlContent = '<html><body><h3>Important Message</h3><p>This is a message box with <b>rich text</b> formatting.</p><ul><li>Item 1</li><li>Item 2</li></ul></body></html>';
% dlgTitle = 'Information';
% options.MsgBoxOnly = true;
% options.Header = 'Please Read';
% options.OkBtnText = 'OK';
% options.Icon = 'question_48px';
% options.DoNotShowAgain = true;
% options.DoNotShowAgainText = 'Do not show this again';
% [answer, selIndex, dontShow] = utils.dlgs.mibInputUniversalDlg(obj.mibPath, {htmlContent}, {htmlContent}, dlgTitle, options);

arguments
    mibPath char = ''
    prompts cell = {'Enter a text:'}
    defAns cell = {[]}
    dlgTitle char = 'MultiEdit dialog'
    options struct = struct
end

% Defaults
if ~isfield(options, 'Icon'); options.Icon = 'question_48px'; end
if ~isfield(options, 'WindowStyle'); options.WindowStyle = 'normal'; end
if ~isfield(options, 'Columns'); options.Columns = 1; end
if ~isfield(options, 'IconWidth'); options.IconWidth = []; end
if ~isfield(options, 'MainColumnWidths'); options.MainColumnWidths = repmat({'1x'}, 1, options.Columns); end
if ~isfield(options, 'LabelPosition'); options.LabelPosition = 'left'; end
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
if numel(options.PromptLines) == 1
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

% MIB path resolution for icons
if isempty(mibPath)
    if isdeployed
        [~, result] = system('path');
        toks = regexp(result, 'Path=(.*?);', 'tokens', 'once');
        if ~isempty(toks); mibDir = char(toks{1}); else; mibDir = pwd; end
    else
        mibDir = fileparts(which('mib'));
        if isempty(mibDir); mibDir = pwd; end
    end
else
    mibDir = mibPath;
end

% Build figure (before icon loading to get background color)
fig = uifigure('Name', dlgTitle, 'Visible', 'off');
fig.Tag = 'mibInputUniversalDlg';
fig.AutoResizeChildren = 'off';  % Disable auto-resize
if strcmpi(options.WindowStyle,'modal'); fig.WindowStyle='modal'; else; fig.WindowStyle='normal'; end
fig.Position(3) = options.WindowWidth;

% Calculate or set height
if isempty(options.WindowHeight)
    numRegular = numel(prompts) - (options.LastItemColumns == 1 && ~options.MsgBoxOnly);
    if options.MsgBoxOnly
        itemsPerCol = 1;  % Only one row for message box
        estimatedHeight = 300;
    else
        itemsPerCol = max(1, ceil(numRegular / options.Columns));
        if strcmpi(options.LabelPosition, 'top')
            % Vertical layout: each item takes ~50 pixels (label + widget)
            estimatedHeight = 100 + (itemsPerCol * 50) + 50;
        else
            % Horizontal layout: each item takes ~35 pixels
            estimatedHeight = 100 + (itemsPerCol * 35) + 50;
        end
    end
    fig.Position(4) = max(200, min(800, estimatedHeight));
else
    fig.Position(4) = options.WindowHeight;
end

% Center dialog on parent figure if provided
if ~isempty(options.ParentFigure) && isvalid(options.ParentFigure)
    try
        parentPos = options.ParentFigure.Position;
        dialogWidth = fig.Position(3);
        dialogHeight = fig.Position(4);
        
        % Calculate center position relative to parent
        centerX = parentPos(1) + (parentPos(3) - dialogWidth) / 2;
        centerY = parentPos(2) + (parentPos(4) - dialogHeight) / 2;
        
        % Set dialog position
        fig.Position(1) = centerX;
        fig.Position(2) = centerY;
    catch
        % If centering fails, MATLAB will use default position
    end
end

% Get figure background color for alpha blending
figBgColor = fig.Color;

% Icon selection and loading
iconFilename = '';
switch options.Icon
    case 'warning_48px',   iconFilename = 'warning_48px.png';
    case 'question_48px',  iconFilename = 'question_48px.png';
    case 'celebrate',      iconFilename = 'celebrate.jpg';
    case 'call4help',      iconFilename = 'call4help.jpg';
    otherwise,             iconFilename = 'question_48px.png';
end
iconPath = fullfile(mibDir, 'assets', 'images', iconFilename);
iconImg = [];
iconImgWidth = 48;  % Default icon width
if exist(iconPath, 'file')
    try
        % Read image with alpha channel
        [img, ~, alpha] = imread(iconPath);
        
        % Handle alpha channel by compositing with figure background
        if ~isempty(alpha)
            % Convert to double for blending
            img = im2double(img);
            alpha = im2double(alpha);
            
            % Get background color from figure
            bgColor = figBgColor; % RGB triplet from figure
            
            % Blend image with background using alpha
            if size(img, 3) == 3
                % RGB image
                for k = 1:3
                    img(:,:,k) = img(:,:,k) .* alpha + bgColor(k) * (1 - alpha);
                end
            else
                % Grayscale image - use average of RGB for gray value
                bgGray = mean(bgColor);
                img = img .* alpha + bgGray * (1 - alpha);
            end
            
            % Convert back to uint8
            iconImg = im2uint8(img);
        else
            iconImg = img;
        end
        
        % Get icon width for layout
        iconImgWidth = size(iconImg, 2);
        if ~isempty(options.IconWidth)
            iconImg = imresize(iconImg, [NaN options.IconWidth]);
            iconImgWidth = options.IconWidth;
        end
    catch
        iconImg = [];
    end
end

% Determine if we have a header
hasHeader = isfield(options,'Header') && ~isempty(options.Header);

% Main grid structure
totalCols = 1 + options.Columns;
mainColWidths = [{iconImgWidth} options.MainColumnWidths];  % Icon column with specified width

if hasHeader
    % 3 rows: header row, content row, button row
    mainGrid = uigridlayout(fig, [3 totalCols], ...
        'RowHeight', {'fit', '1x', 24}, ...
        'ColumnWidth', mainColWidths, ...
        'Padding', [10 10 10 10], 'RowSpacing', 10, 'ColumnSpacing', 12);
    headerRow = 1;
    contentRow = 2;
    buttonRow = 3;
else
    % 2 rows: icon/content row, button row
    mainGrid = uigridlayout(fig, [2 totalCols], ...
        'RowHeight', {'1x', 24}, ...
        'ColumnWidth', mainColWidths, ...
        'Padding', [10 10 10 10], 'RowSpacing', 10, 'ColumnSpacing', 12);
    headerRow = 1;
    contentRow = 1;
    buttonRow = 2;
end

% Row 1, Column 1: Icon (always in top row)
if ~isempty(iconImg)
    iconUI = uiimage(mainGrid, 'ImageSource', iconImg);
    iconUI.Layout.Row = headerRow;
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
        else
            regIdx = regIdx + 1;
            colIdx = min(options.Columns, ceil(regIdx / itemsPerCol));
            par = colGrids{colIdx};
            currentRow = colRowCounters(colIdx);
        end
        
        % Detect placeholder (NaN)
        if isnumeric(defAns{i}) && isscalar(defAns{i}) && isnan(defAns{i})
            isPlaceholder(i) = true;
        end
        
        % Placeholder: single row
        if isPlaceholder(i)
            if strcmpi(options.LabelPosition, 'top')
                % Vertical layout
                if currentRow > numel(par.RowHeight)
                    par.RowHeight{end+1} = 'fit';
                end
                lab = uilabel(par, 'Text', prompts{i}, 'HorizontalAlignment', 'left', 'WordWrap', 'on');
                lab.Layout.Row = currentRow;
                lab.Layout.Column = 1;
                colRowCounters(colIdx) = colRowCounters(colIdx) + 1;
            else
                % Horizontal layout
                if currentRow > numel(par.RowHeight)
                    par.RowHeight{end+1} = 'fit';
                end
                lab = uilabel(par, 'Text', prompts{i}, 'HorizontalAlignment', 'left', 'WordWrap', 'on');
                lab.Layout.Row = currentRow;
                lab.Layout.Column = [1 2];
                colRowCounters(colIdx) = colRowCounters(colIdx) + 1;
            end
            continue;
        end
        
        % Build label and widget based on layout mode
        if strcmpi(options.LabelPosition, 'top')
            % === VERTICAL LAYOUT: Label above widget ===
            
            % Extend rows if needed for label
            if currentRow > numel(par.RowHeight)
                par.RowHeight{end+1} = 'fit';  % Label row
            end
            
            % Label above widget
            lab = uilabel(par, 'Text', prompts{i}, 'HorizontalAlignment', 'left', ...
                'VerticalAlignment', 'bottom', 'WordWrap', 'on');
            lab.Layout.Row = currentRow;
            lab.Layout.Column = 1;
            
            % Move to next row for widget
            currentRow = currentRow + 1;
            colRowCounters(colIdx) = currentRow + 1;  % Reserve current row for widget
            
            % Checkbox: Label above, checkbox below
            if islogical(defAns{i}) && isscalar(defAns{i})
                isCheckbox(i) = true;
                
                % Extend rows for widget
                if currentRow > numel(par.RowHeight)
                    par.RowHeight{end+1} = 22;  % Fixed height for checkbox
                end
                
                % Wrapper grid for checkbox
                wrapperGrid = uigridlayout(par, [1 1], 'RowHeight', {22}, 'ColumnWidth', {'1x'}, 'Padding', [0 0 0 0]);
                wrapperGrid.Layout.Row = currentRow;
                wrapperGrid.Layout.Column = 1;
                
                cb = uicheckbox(wrapperGrid, 'Text', '', 'Value', defAns{i});
                widgets(i) = cb;
                continue;
            end
            
            % Create wrapper grid for widget with fixed or variable height based on PromptLines
            if PromptLines(i) > 1
                % Multi-line text input: use textarea with height based on PromptLines
                widgetHeight = 22 * PromptLines(i);  % 22 pixels per line
                if currentRow > numel(par.RowHeight)
                    par.RowHeight{end+1} = widgetHeight;
                end
                wrapperGrid = uigridlayout(par, [1 1], 'RowHeight', {widgetHeight}, 'ColumnWidth', {'1x'}, 'Padding', [0 0 0 0]);
            else
                % Single-line input: fixed 22 pixel height
                if currentRow > numel(par.RowHeight)
                    par.RowHeight{end+1} = 22;
                end
                wrapperGrid = uigridlayout(par, [1 1], 'RowHeight', {22}, 'ColumnWidth', {'1x'}, 'Padding', [0 0 0 0]);
            end
            wrapperGrid.Layout.Row = currentRow;
            wrapperGrid.Layout.Column = 1;
            
        else
            % === HORIZONTAL LAYOUT: Label left of widget ===
            
            % Extend rows if needed
            if currentRow > numel(par.RowHeight)
                par.RowHeight{end+1} = 'fit';
            end
            colRowCounters(colIdx) = colRowCounters(colIdx) + 1;
            
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
        end
        
        % Determine control type and create widget (common for both layouts)
        ctrl = [];
        val = defAns{i};
        
        if iscell(val)
            % Dropdown
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
            % Spinner
            isSpinner(i) = true;
            v = 0; lo = -Inf; hi = Inf; step = 1;
            if isfield(val,'Value'); v = val.Value; end
            if isfield(val,'Limits'); lo = val.Limits(1); hi = val.Limits(2); end
            if isfield(val,'Step'); step = val.Step; end
            
            ctrl = uispinner(wrapperGrid, 'Limits', [lo hi], 'Value', v, 'Step', step);
            
            % Handle optional Round and ValueDisplayFormat
            if isfield(val,'Round') && val.Round
                ctrl.RoundFractionalValues = 'on';
            end
            if isfield(val,'ValueDisplayFormat')
                ctrl.ValueDisplayFormat = val.ValueDisplayFormat;
            end
            
        else
            % Check if it's numeric ONLY if non-empty or explicitly a number
            if isnumeric(val) && isscalar(val) && ~isempty(val)
                isNumericEdit(i) = true;
                ctrl = uieditfield(wrapperGrid, 'numeric', 'Value', double(val), 'ValueDisplayFormat','%.3g');
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
    okBtn = uibutton(btnBox, 'Text', options.OkBtnText, 'BackgroundColor', [0.15, 0.90, 0.18], 'ButtonPushedFcn', @(~,~) onOK());
    cancelBtn = uibutton(btnBox, 'Text', 'Cancel', 'BackgroundColor', [1.00,0.53,0.10], 'ButtonPushedFcn', @(~,~) onCancel());
end

% Key handling
fig.KeyPressFcn = @(~, evt) onKey(evt);
fig.WindowKeyPressFcn = @(~, evt) onKey(evt);

% Render layout before showing
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
                out{k} = w.Value;
                sel(k) = w.ValueIndex;
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
        if options.DoNotShowAgain && ~isempty(chkDontShow) && isvalid(chkDontShow)
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
                onOK();  % Default to OK
            end
        end
    end

end
