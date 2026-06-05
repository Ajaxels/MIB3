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
%     - ``.WindowWidth`` — [numeric] dialog width in pixels (default: 560)
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

persistent mibDirPersistent;       % cached MIB installation path
persistent parentFigurePersistent; % cached handle to the main GUI window
persistent cachedFigure;           % reusable hidden uifigure shell
persistent iconCompositeCache;     % dictionary: cacheKey -> composited uint8 image
persistent iconCacheBgColor;       % RGB triplet used for compositing

% Normalize options field names to their canonical casing.
% MATLAB struct field lookup is case-sensitive, so options.msgboxonly would be
% silently ignored. This loop finds any supplied field whose name matches a known
% field case-insensitively but differs in case (e.g. 'msgBoxOnly' -> 'MsgBoxOnly')
% and renames it to the canonical form before the defaults section runs.
knownOptionFields = {'Icon','IconWidth','WindowStyle','Columns','MainColumnWidths', ...
    'LabelPosition','SectionsColumnWidths','Focus','LastItemColumns', ...
    'OkBtnText','HelpBtnText','HelpUrl','MsgBoxOnly','PromptLines', ...
    'HeaderLines','Header','WindowWidth','WindowHeight','DoNotShowAgain', ...
    'DoNotShowAgainText','ParentFigure','DefaultKey'};
for suppliedField = fieldnames(options)'
    suppliedField = suppliedField{1};
    canonicalIdx  = find(strcmpi(knownOptionFields, suppliedField), 1);
    if ~isempty(canonicalIdx) && ~strcmp(suppliedField, knownOptionFields{canonicalIdx})
        % Rename the misspelled/wrong-case field to the canonical name
        options.(knownOptionFields{canonicalIdx}) = options.(suppliedField);
        options = rmfield(options, suppliedField);
    end
end
clear suppliedField canonicalIdx knownOptionFields

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
if ~isfield(options, 'IconWidth')
    if ismember(options.Icon, {'puffin_question', 'puffin_warning', 'puffin_error', 'puffin_info', 'puffin_waiting'})
        options.IconWidth = 96; 
    else
        options.IconWidth = 48; 
    end
end
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
if ~isfield(options, 'WindowHeight'); options.WindowHeight = 150; end
if ~isfield(options, 'DoNotShowAgain'); options.DoNotShowAgain = false; end
if ~isfield(options, 'DoNotShowAgainText'); options.DoNotShowAgainText = 'Do not show again'; end
if ~isfield(options, 'mibPath'); options.mibPath = ''; end
if ~isfield(options, 'ParentFigure'); options.ParentFigure = []; end
% ParentFigure first-param takes priority; update cache and options.ParentFigure
if ~isempty(ParentFigure) && isvalid(ParentFigure)
    parentFigurePersistent = ParentFigure;
    options.ParentFigure = ParentFigure;
elseif isempty(options.ParentFigure) && ~isempty(parentFigurePersistent) && isvalid(parentFigurePersistent)
    options.ParentFigure = parentFigurePersistent;
elseif ~isempty(options.ParentFigure) && isvalid(options.ParentFigure)
    parentFigurePersistent = options.ParentFigure;   % cache for future calls
end
if ~isfield(options, 'DefaultKey'); options.DefaultKey = 'OK'; end

% In MsgBoxOnly mode auto-wrap plain-text defAns with the standard HTML
% font tag so callers do not need to embed HTML themselves.
if options.MsgBoxOnly && numel(defAns) == 1 && (ischar(defAns{1}) || isstring(defAns{1})) ...
        && ~strncmpi(char(defAns{1}), '<html>', 6)
    defAns{1} = sprintf('<html><p style="font-size:10pt">%s</p></html>', strrep(defAns{1}, newline, '<br>'));
end

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

% MIB path resolution for icons — update cache when options.mibPath is supplied
if ~isempty(options.mibPath)
    mibDirPersistent = options.mibPath;   % caller provided a fresh path; cache it
end

if isempty(mibDirPersistent)
    if isdeployed
        [~, result] = system('path');
        toks = regexp(result, 'Path=(.*?);', 'tokens', 'once');
        if ~isempty(toks); mibDirPersistent = char(toks{1}); else; mibDirPersistent = pwd; end
    else
        mibDirPersistent = fileparts(which('mib3'));
        if isempty(mibDirPersistent); mibDirPersistent = pwd; end
    end
end
mibDir = mibDirPersistent;

% Build figure (before icon loading to get background color)
% Reuse a cached hidden figure when available to avoid ~200-400ms uifigure creation cost
if ~isempty(cachedFigure) && isvalid(cachedFigure) && strcmp(cachedFigure.Visible, 'off')
    fig = cachedFigure;
    delete(fig.Children);
    fig.Name = dlgTitle;
    fig.KeyPressFcn = '';
    fig.WindowKeyPressFcn = '';
    fig.CloseRequestFcn = 'closereq';
else
    fig = uifigure('Name', dlgTitle, 'Visible', 'off');
    fig.Tag = 'inputUniversalDlg';
    fig.AutoResizeChildren = 'off';
    cachedFigure = fig;
end
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

% Get figure background color for alpha blending
figBgColor = fig.Color;

% Icon selection and loading
switch options.Icon
    case 'warning_48px';     iconFilename = 'warning_48px.png';
    case 'question_48px';    iconFilename = 'question_48px.png';
    case 'celebrate';        iconFilename =  sprintf('puffin_cheering_%d_220px.png', randi(2)); options.IconWidth = 220;
    case 'call4help';        iconFilename =  sprintf('puffin_call4help_%d_220px.png', randi(3)); options.IconWidth = 220;
    case 'puffin_error';     iconFilename = sprintf('puffin_error_%d_96px.png', randi(4));
    case 'puffin_warning';   iconFilename = sprintf('puffin_warning_%d_96px.png', randi(3));
    case 'puffin_question';  iconFilename = sprintf('puffin_quest_%d_96px.png', randi(7));
    case 'puffin_measure';   iconFilename = sprintf('puffin_measure_%d_96px.png', randi(5));
    case 'puffin_info';      iconFilename = sprintf('puffin_info_%d_96px.png', randi(5));
    case 'puffin_waiting';      iconFilename = sprintf('puffin_waiting_%d_96px.png', randi(3));
    otherwise
        % get random icon
        iconFilename = sprintf('puffin_quest_%d_96px.png', randi(6));
        options.IconWidth = 96;
end
iconPath = fullfile(mibDir, 'assets', 'images', iconFilename);
iconImg = [];
iconImgWidth = 48;  % Default icon width
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

        iconWidth = options.IconWidth;
        if isempty(iconWidth); iconWidth = 0; end
        cacheKey = string(sprintf('%s_%d', iconFilename, iconWidth));

        if isKey(iconCompositeCache, cacheKey)
            iconImg = iconCompositeCache{cacheKey};
            iconImgWidth = size(iconImg, 2);
        else
            % Read image with alpha channel
            [img, ~, alpha] = imread(iconPath);

            % Handle alpha channel by compositing with figure background
            if ~isempty(alpha)
                img = im2double(img);
                alpha = im2double(alpha);
                bgColor = figBgColor;

                if size(img, 3) == 3
                    for k = 1:3
                        img(:,:,k) = img(:,:,k) .* alpha + bgColor(k) * (1 - alpha);
                    end
                else
                    bgGray = mean(bgColor);
                    img = img .* alpha + bgGray * (1 - alpha);
                end
                iconImg = im2uint8(img);
            else
                iconImg = img;
            end

            % Resize icon
            iconImgWidth = size(iconImg, 2);
            if ~isempty(options.IconWidth)
                iconImg = imresize(iconImg, [NaN options.IconWidth]);
                iconImgWidth = options.IconWidth;
            end

            % Store in cache
            if ~isempty(iconImg)
                iconCompositeCache(cacheKey) = {iconImg};
            end
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
    headerRowHeight = options.HeaderLines * 22;  % ~22px per line
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
    okBtn = uibutton(btnBox, 'Text', options.OkBtnText, 'ButtonPushedFcn', @(~,~) onOK());
    cancelBtn = uibutton(btnBox, 'Text', 'Cancel', 'ButtonPushedFcn', @(~,~) onCancel());
end

% Key handling
fig.KeyPressFcn = @(~, evt) onKey(evt);
fig.WindowKeyPressFcn = @(~, evt) onKey(evt);
fig.CloseRequestFcn = @(~,~) onCancel();

% show the dialog
fig.Visible = 'on';
drawnow;

% Re-apply WindowStyle on the realized (visible) figure. Setting it while a
% cached figure is hidden does not take effect (notably in the deployed web
% engine), so the dialog would otherwise come up non-modal on reuse.
if strcmpi(options.WindowStyle, 'modal'); fig.WindowStyle = 'modal'; else; fig.WindowStyle = 'normal'; end
drawnow;

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
                    try eval(H); catch, end
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
        % Hide and unblock instead of deleting so the figure can be reused.
        % Reset WindowStyle first: a hidden but still-modal figure keeps its
        % input grab on the parent and would freeze the main GUI.
        fig.WindowStyle = 'normal';
        fig.Visible = 'off';
        uiresume(fig);
    end

    function onCancel()
        answer = {};
        selectedIndices = [];
        if options.DoNotShowAgain && ~isempty(chkDontShow) && isvalid(chkDontShow)
            dontShowAgain = logical(chkDontShow.Value);
        end
        fig.WindowStyle = 'normal';   % release modal grab before hiding
        fig.Visible = 'off';
        uiresume(fig);
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
            pause(0.1);  % allow widget to commit its value
            if strcmpi(options.DefaultKey, 'Cancel') && ~isempty(cancelBtn) && isvalid(cancelBtn)
                onCancel();
            else
                onOK();
            end
        end
    end

end
