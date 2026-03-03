function answer = mibInputSingleDlg(mibPath, prompt, defAns, dlgTitle, options)
% function answer = mibInputSingleDlg(mibPath, prompt, defAns, dlgTitle, options)
% Efficient single-input dialog with uifigure and icon support offering
% access to uieditfield for texts or uispinner for values
%
% Parameters:
% mibPath: char with path to MIB installation (default: [])
% prompt: string with the prompt text for the input field
% defAns: default value - string for editfield or struct for spinner
%         For spinner: struct('Value', v, 'Limits', [min max], 'Step', s, 'Round', false/true, 'ValueDisplayFormat', '%.0f MS/s')
% dlgTitle: dialog window title string
% options: struct with fields:
%   .Type        - 'editfield' (default) or 'spinner'
%   .WindowWidth       - dialog width in pixels (default 400)
%   .WindowHeight      - dialog height in pixels (default 112)
%   .WindowStyle - 'normal' (default) or 'modal'
%   .Icon        - 'puffin_question' (default), 'puffin_warning', 'puffin_error', 'puffin_measure', 'question_48px', 'celebrate', 'call4help', 'warning_48px'
%   .IconWidth   - WindowWidth of icon column in pixels (default 48)
%   .ParentFigure - handle to the parent window to have the dialog centered
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
%   options.Icon = 'question_48px';
%   options.IconWidth = 48;
%   options.ParentFigure = obj.view.gui;
%   answer = utils.dlgs.mibInputSingleDlg(mibPath, prompt, defAns, dlgTitle, options);
%   if isempty(answer); return; end
%
% Example 2 (spinner):
%   mibPath = obj.mibPath;
%   prompt = 'Enter iteration count:';
%   defAns = struct('Value', 10, 'Limits', [1 100], 'Step', 1, 'Round', false, 'ValueDisplayFormat', '%.3f units'); % requires options.Type = 'spinner';
%   dlgTitle = 'Iterations';
%   options.Type = 'spinner';
%   options.WindowWidth = 400;
%   options.WindowHeight = 100;
%   options.WindowStyle = 'modal';
%   options.Icon = 'question_48px';
%   options.IconWidth = 48;
%   options.ParentFigure = obj.view.gui;
%   answer = utils.dlgs.mibInputSingleDlg(mibPath, prompt, defAns, dlgTitle, options);
%   if isempty(answer); return; end
%
% Example 3 (minimalistic spinner)
% options.Type = 'spinner';
% options.ParentFigure = obj.view.gui;
% defAns = struct('Value', 5, 'Limits', [1 Inf], 'Step', 1, 'Round', true, 'ValueDisplayFormat', '%d units');
% options.WindowWidth = 320;
% answer = utils.dlgs.mibInputSingleDlg(obj.mibModel.mibPath, ...
%    sprintf('Please enter number of colors\n(max. value is %d)', 255), ...
%    defAns, ...
%    'Define number of colors', options);
% if isempty(noColors); return; end


arguments
    mibPath char = ''
    prompt char = 'Enter value:'
    defAns = ''
    dlgTitle char = 'Input'
    options struct = struct()
end

persistent mibDir
% Initialize persistent variable on first call or update it with input
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

% Defaults
if ~isfield(options, 'Type'); options.Type = 'editfield'; end
if ~isfield(options, 'WindowWidth'); options.WindowWidth = 400; end
if ~isfield(options, 'WindowHeight'); options.WindowHeight = 112; end
if ~isfield(options, 'WindowStyle'); options.WindowStyle = 'normal'; end
if ~isfield(options, 'Icon'); options.Icon = 'puffin_question'; end
if ~isfield(options, 'IconWidth')
    if ismember(options.Icon, {'puffin_question', 'puffin_warning', 'puffin_error', 'puffin_measure'})
        options.IconWidth = 96; 
    else
        options.IconWidth = 48; 
    end
end
if ~isfield(options, 'ParentFigure'); options.ParentFigure = []; end

% Icon selection and loading
switch options.Icon
    case 'warning_48px',   iconFilename = 'warning_48px.png';        
    case 'question_48px',  iconFilename = 'question_48px.png';
    case 'celebrate', iconFilename =  sprintf('puffin_cheering_%d_220px.png', randi(2)); 
    case 'call4help', iconFilename = 'call4help.jpg';
    case 'puffin_error';     iconFilename = sprintf('puffin_error_%d_96px.png', randi(4));
    case 'puffin_warning';   iconFilename = sprintf('puffin_warning_%d_96px.png', randi(3));
    case 'puffin_question';  iconFilename = sprintf('puffin_quest_%d_96px.png', randi(7));
    case 'puffin_measure';   iconFilename = sprintf('puffin_measure_%d_96px.png', randi(4));
    otherwise
        % puffin_question
        iconFilename = sprintf('puffin_quest_%d_96px.png', randi(6));
end

iconPath = fullfile(mibDir, 'assets', 'images', iconFilename);

fig = uifigure('Name', dlgTitle, 'Visible', 'off', 'WindowStyle', lower(options.WindowStyle));
fig.Icon = fullfile(mibDir, 'assets', 'icons', 'mib_icon_16px.png');
% update figure width/height
fig.Position = [fig.Position(1), fig.Position(2), options.WindowWidth, options.WindowHeight];

% Configure figure
fig.Tag = 'mibInputSingleDlg';

mainGrid = uigridlayout(fig, [3 2], ...
    'RowHeight', {'1x', 22, 22}, ...
    'ColumnWidth', {options.IconWidth, '1x'}, ...
    'Padding', [10 10 10 10], 'RowSpacing', 10, 'ColumnSpacing', 12);

% Column 1: Icon (all rows)
if exist(iconPath, 'file')
    iconUI = uiimage(mainGrid, 'ImageSource', iconPath, 'ScaleMethod', 'fit');

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
% --- Local function (at end of file) ---
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
