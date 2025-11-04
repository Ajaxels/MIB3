function answer = mibInputSingleDlg(mibPath, prompt, defAns, dlgTitle, options)
% function answer = mibInputSingleDlg(mibPath, prompt, defAns, dlgTitle, options)
% Efficient single-input dialog with uifigure and icon support offering
% access to uieditfield for texts or uispinner for values
%
% Parameters:
% mibPath: char with path to MIB installation (default: [])
% prompt: string with the prompt text for the input field
% defAns: default value - string for editfield or struct for spinner
%         For spinner: struct('Value', v, 'Limits', [min max], 'Step', s, 'Round', false/true)
% dlgTitle: dialog window title string
% options: struct with fields:
%   .Type        - 'editfield' (default) or 'spinner'
%   .WindowWidth       - dialog width in pixels (default 400)
%   .WindowHeight      - dialog height in pixels (default 100)
%   .WindowStyle - 'normal' (default) or 'modal'
%   .Icon        - 'question' (default), 'celebrate', 'call4help', 'warning'
%   .IconWidth   - WindowWidth of icon column in pixels (default 64)
%
% Return values:
% answer: entered value (string for editfield, double for spinner), empty when canceled
%
% Example 1 (editfield):
%   mibPath = obj.mibPath;
%   prompt = 'Enter file name:';
%   defAns = 'myfile.txt';
%   dlgTitle = 'File Name';
%   options.Type = 'editfield';
%   options.WindowWidth = 400;
%   options.WindowHeight = 100;
%   options.WindowStyle = 'modal';
%   options.Icon = 'question';
%   options.IconWidth = 64;
%   answer = utils.mibInputSingleDlg(mibPath, prompt, defAns, dlgTitle, options);
%   if isempty(answer); return; end
%
% Example 2 (spinner):
%   mibPath = obj.mibPath;
%   prompt = 'Enter iteration count:';
%   defAns = struct('Value', 10, 'Limits', [1 100], 'Step', 1, 'Round', false);
%   dlgTitle = 'Iterations';
%   options.Type = 'spinner';
%   options.WindowWidth = 400;
%   options.WindowHeight = 100;
%   options.WindowStyle = 'modal';
%   options.Icon = 'question';
%   options.IconWidth = 64;
%   mibPath = obj.mibPath;
%   answer = utils.mibInputSingleDlg(mibPath, prompt, defAns, dlgTitle, options);
%   if isempty(answer); return; end

arguments
    mibPath char = ''
    prompt char = 'Enter value:'
    defAns = ''
    dlgTitle char = 'Input'
    options struct = struct()
end

% Defaults
if ~isfield(options, 'Type'); options.Type = 'editfield'; end
if ~isfield(options, 'WindowWidth'); options.WindowWidth = 400; end
if ~isfield(options, 'WindowHeight'); options.WindowHeight = 100; end
if ~isfield(options, 'WindowStyle'); options.WindowStyle = 'normal'; end
if ~isfield(options, 'Icon'); options.Icon = 'question'; end
if ~isfield(options, 'IconWidth'); options.IconWidth = []; end
if ~isfield(options, 'ParentFigure'); options.ParentFigure = []; end

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

% Icon selection and loading
switch options.Icon
    case 'warning',   iconFilename = 'mib_warning.png';
    case 'question',  iconFilename = 'mib_question.png';
    case 'celebrate', iconFilename = 'mib_celebrate.jpg';
    case 'call4help', iconFilename = 'mib_call4help.jpg';
    otherwise,        iconFilename = 'mib_question.png';
end
iconPath = fullfile(mibDir, 'assets', 'images', iconFilename);

if exist(iconPath, 'file')
    try
        % Read image with alpha channel
        [img, ~, alpha] = imread(iconPath);
        
        % Build figure first to get background color
        fig = uifigure('Name', dlgTitle, 'Visible', 'off', 'WindowStyle', lower(options.WindowStyle));
        figBgColor = fig.Color;
        
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
        
        % Resize icon to fit WindowWidth
        if ~isempty(options.IconWidth)
            iconImg = imresize(iconImg, [options.IconWidth, NaN], 'lanczos3');
        else
            options.IconWidth = size(iconImg, 2);
        end
    catch
        % Create figure without icon if loading fails
        fig = uifigure('Name', dlgTitle, 'Visible', 'off', 'WindowStyle', lower(options.WindowStyle));
        iconImg = [];
    end
else
    % Create figure without icon if file not found
    fig = uifigure('Name', dlgTitle, 'Visible', 'off', 'WindowStyle', lower(options.WindowStyle));
    iconImg = [];
end
% update figure width/height
fig.Position = [fig.Position(1), fig.Position(2), options.WindowWidth, options.WindowHeight];

% Configure figure
fig.Tag = 'mibInputSingleDlg';

% Main grid: 3 rows, 2 columns (icon, content)
mainGrid = uigridlayout(fig, [3 2], ...
    'RowHeight', {'1x', 22, 22}, ...
    'ColumnWidth', {options.IconWidth, '1x'}, ...
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
        v = 0; lo = 1; hi = 100; step = 1; roundVals = false;
        if isfield(defAns, 'Value'); v = defAns.Value; end
        if isfield(defAns, 'Limits'); lo = defAns.Limits(1); hi = defAns.Limits(2); end
        if isfield(defAns, 'Step'); step = defAns.Step; end
        if isfield(defAns,'Round'); roundVals = defAns.Round; end
        inputCtrl = uispinner(mainGrid, 'Limits', [lo hi], 'Value', v, 'Step', step, 'RoundFractionalValues', roundVals);
    else
        inputCtrl = uispinner(mainGrid, 'Limits', [1 100], 'Value', 1, 'Step', 1);
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
            % AppContainer window
            parentPos = options.ParentFigure.WindowBounds;
        elseif isa(options.ParentFigure, 'matlab.ui.Figure') % standard window
            parentPos = options.ParentFigure.Position;
        end

        screenSize = get(0, 'ScreenSize');
        screenHeight = screenSize(4);

        % Center of main GUI (top-left origin)
        centerX = parentPos(1) + parentPos(3) / 2;
        centerY = parentPos(2) + parentPos(4) / 2;

        % Convert to MATLAB Position coords (bottom-left origin)
        x1 = centerX - options.WindowWidth / 2;
        y1 = screenHeight - centerY - options.WindowHeight / 2;

        % Clamp to screen bounds
        x1 = max(0, min(x1, screenSize(3) - options.WindowWidth));
        y1 = max(0, min(y1, screenHeight - options.WindowHeight));

        % Set dialog position
        fig.Position(1) = x1;
        fig.Position(2) = y1;
    catch
        % If centering fails, MATLAB will use default position
    end
end

% Show figure
drawnow;  % Render layout before making visible
fig.Visible = 'on';

% Set focus on input widget
try
    focus(inputCtrl);
catch
end

% Initialize output
answer = [];

% Wait for user
uiwait(fig);

% Callbacks
    function onOK()
        if strcmpi(options.Type, 'spinner')
            answer = double(inputCtrl.Value);
        else
            answer = char(inputCtrl.Value);
        end
        uiresume(fig);
        delete(fig);
    end

    function onCancel()
        answer = [];
        uiresume(fig);
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
