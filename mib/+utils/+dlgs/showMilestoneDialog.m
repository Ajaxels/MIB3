function [newStatsPath, updatedTiers] = showMilestoneDialog(ParentFigure, userPrefs, mode, options)
% SHOWMILESTONEDIALOG - Show a gamification milestone / current-stats dialog with a celebration.
%
% Syntax:
%   .. code-block:: matlab
%
%      showMilestoneDialog(ParentFigure, userPrefs, mode)
%      showMilestoneDialog(ParentFigure, userPrefs, mode, options)
%
% video and user performance statistics.
%
% Input Arguments:
%   - **ParentFigure** - handle to the parent window (AppContainer, uifigure, or ``[]``);
%     used to center the dialog. Pass ``[]`` to use the cached handle from a prior call.
%     In MIB pass ``obj.mibModel.getProgressBarParent()`` so the dialog follows the
%     active dataset window when it is undocked.
%     To supply the MIB installation path use ``options.mibPath``.
%   - **userPrefs** - struct - ``mibModel.preferences.Users`` (provides tier data and stats)
%   - **mode** - [char] display mode:
%
%     - ``'milestoneReached'`` - congratulations dialog for reaching a new tier (default)
%     - ``'currentStats'`` - show current score and progress
%
%   - **options** *(optional)* - struct with fields:
%
%     - ``.mibPath`` - [char] path to MIB installation directory (default: ``''``)
%     - ``.WindowStyle`` - [char] ``'modal'`` (default for ``'milestoneReached'``) or ``'normal'``
%     - ``.ParentFigure`` - [handle] uifigure / AppContainer handle for centering
%
% Output Arguments:
%   - **newStatsPath** - [char] new ``mib_user.mat`` path chosen by the user,
%     or ``''`` if the path was not changed
%   - **updatedTiers** - struct with potentially updated ``Tiers`` data
%     (may differ from the input when a richer stats file was loaded)
%
% (none when called without output arguments - dialog blocks until dismissed)
%
% **Example 1** - Show a milestone congratulations dialog
%
% .. code-block:: matlab
%
%    utils.dlgs.showMilestoneDialog(obj.view.gui, ...
%        obj.mibModel.preferences.Users, 'milestoneReached');
%
% **Example 2** - Show current score and progress
%
% .. code-block:: matlab
%
%    utils.dlgs.showMilestoneDialog(obj.view.gui, ...
%        obj.mibModel.preferences.Users, 'currentStats');
%

arguments
    ParentFigure = []
    userPrefs struct = struct()
    mode      char   = 'milestoneReached'
    options   struct = struct()
end

%% Resolve mibDir and ParentFigure (mirrors pattern used in other +utils/+dlgs functions)
persistent mibDir
persistent parentFigureHandle   % cached handle to the main GUI window
persistent cachedFigure         % reusable hidden uifigure shell

if ~isfield(options, 'mibPath'); options.mibPath = ''; end
if ~isfield(options, 'userStatsPath'); options.userStatsPath = ''; end

% Output variables - shared with nested callbacks via closure
newStatsPath = '';
updatedTiers = struct();

% ParentFigure param takes priority; update cache
if ~isempty(ParentFigure) && isvalid(ParentFigure)
    parentFigureHandle = ParentFigure;
end

% Resolve mibDir - update cache when options.mibPath is supplied
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

%% Defaults
if ~isfield(options, 'ParentFigure'); options.ParentFigure = []; end
% use ParentFigure param first, then options.ParentFigure, then cached handle
if ~isempty(ParentFigure) && isvalid(ParentFigure)
    options.ParentFigure = ParentFigure;
elseif isempty(options.ParentFigure) && ~isempty(parentFigureHandle) && isvalid(parentFigureHandle)
    options.ParentFigure = parentFigureHandle;
elseif ~isempty(options.ParentFigure) && isvalid(options.ParentFigure)
    parentFigureHandle = options.ParentFigure;
end

%% Build stats text block (shared by both modes)
if ~isempty(fieldnames(userPrefs)) && isfield(userPrefs, 'Tiers')
    T    = userPrefs.Tiers;
    U    = userPrefs;
    updatedTiers = T;   % initialise output; may be overwritten by onSetStatsFile
    elapsedTime = datetime('now') - T.logStartDate;

    statsBlock = sprintf(['Stats:\n' ...
        '     Loaded datasets: %d\n' ...
        '     Image filterings: %d\n' ...
        '     Batch processings: %d\n' ...
        '     Snaps and movies: %d\n' ...
        '     Shortcuts pressed: %d\n\n' ...
        'Tools:\n' ...
        '     3D balls: %d\n' ...
        '     3D lines: %d\n' ...
        '     Annotations: %d\n' ...
        '     BW thresholdings: %d\n' ...
        '     Drag-and-drop materials: %d\n' ...
        '     Lassos: %d\n' ...
        '     Magic wands: %d\n' ...
        '     Object pickers: %d\n' ...
        '     Membrane trackers: %d\n' ...
        '     Segment anything: %d\n' ...
        '     Spots: %d\n' ...
        '     Graphcuts: %d\n' ...
        '     Trained CNN networks: %d\n' ...
        '     Inferenced CNN datasets: %d\n' ...
        '     Measurements placed: %d\n' ...
        '     Statistics calculated: %d\n', ...
        '     Alignments: %d\n' ...
        '     Stitchings: %d\n'], ...
        T.numberOfLoadedDatasets, ...
        T.numberOfImageFilterings, ...
        T.numberOfBatchProcessings, ...
        T.numberOfSnapAndMovies, ...
        T.numberOfKeyShortcuts, ...
        T.numberOfBall3D, ...
        T.numberOfLine3D, ...
        T.numberOfAnnotations, ...
        T.numberOfBWThresholdings, ...
        T.numberOfDragDropMaterials, ...
        T.numberOfLassos, ...
        T.numberOfMagicWands, ...
        T.numberOfObjectPickers, ...
        T.numberOfMembraneClickTrackers, ...
        T.numberOfSAMclicks, ...
        T.numberOfSpots, ...
        T.numberOfGraphcuts, ...
        T.numberOfTrainedDeepNetworks, ...
        T.numberOfInferencedDeepNetworks, ...
        T.numberOfMeasurements, ...
        T.numberOfGetStats, ...
        T.numberOfAlignments, ...
        T.numberOfStitchings);

    tierName = U.tierLevelRanks{min(T.tierLevel, numel(U.tierLevelRanks))};
else
    statsBlock   = '';
    tierName     = '';
    elapsedTime  = duration(0, 0, 0);
    T.brushTravelDistance = 0;
    T.mouseTravelDistance = 0;
    T.collectedPoints     = 0;
    T.tierLevel           = 1;
    U.tierPointsCoef      = 1;
end

%% Build mode-specific greeting text and window properties
switch mode
    case 'milestoneReached'
        dlgTitle     = 'Milestone!';
        windowStyle  = 'modal';
        greetingText = sprintf( ...
            'Congratulations!!! You have reached a milestone!!!\n\nYou just unlocked a new tier:\n\t\t\t\t\t\t\tLevel %s\n\n', ...
            tierName);
        bodyText = sprintf( ...
            ['You have been\n' ...
             '   - brushing with MIB for %.3f km\n' ...
             '   - moving mouse in MIB for %.3f km\n' ...
             'and it took you approximately %s\n\n' ...
             '%s'], ...
            T.brushTravelDistance / 1000, ...
            T.mouseTravelDistance / 1000, ...
            duration(elapsedTime, 'Format', 'd'), ...
            statsBlock);
        okLabel = 'OMG!';

    case 'currentStats'
        rng('shuffle');
        titles   = {'Work hard, succeed big!'; 'No pain, no gain!'; ...
                    'Push yourself, achieve more!'; 'Sweat, conquer, repeat!'; ...
                    'Dream big, work harder!'; 'Label pixels, conquer volumes!'; 'One mask at a time!'; ...
                    'Watershed your fears, flood your goals!'; 'Train, predict, repeat!'; 'Every pixel counts - so do you!'; ...
                    'Annotate today, automate tomorrow!'; 'Make brush great again!'};
        dlgTitle    = titles{randi(numel(titles))};
        windowStyle = 'normal';

        if T.tierLevel == 1
            currentTierPoints = 0;
        else
            currentTierPoints = U.tierPointsCoef * 2^(T.tierLevel - 1);
        end
        nextTierPoints  = U.tierPointsCoef * 2^T.tierLevel;
        toNextTierPoints = nextTierPoints - currentTierPoints;
        collectedCurrent = T.collectedPoints - currentTierPoints;

        greetingText = sprintf( ...
            ['Your current tier: %s\n' ...
             'Score: %.3f  (%.2f%% to next tier [%d])\n\n'], ...
            tierName, T.collectedPoints, ...
            collectedCurrent / toNextTierPoints * 100, nextTierPoints);
        bodyText = sprintf( ...
            ['You have been\n' ...
             '   - brushing with MIB for %.3f km\n' ...
             '   - moving mouse in MIB for %.3f km\n' ...
             'and it took you approximately %s\n\n' ...
             '%s'], ...
            T.brushTravelDistance / 1000, ...
            T.mouseTravelDistance / 1000, ...
            duration(elapsedTime, 'Format', 'd'), ...
            statsBlock);
        okLabel = 'OK';

    otherwise
        dlgTitle    = 'Stats';
        windowStyle = 'normal';
        greetingText = '';
        bodyText     = statsBlock;
        okLabel      = 'OK';
end

if isfield(options, 'WindowStyle'); windowStyle = options.WindowStyle; end

%% Layout constants
WIN_W        = 760;
WIN_H        = 500;
VIDEO_COL_W  = 220;   % width of the video column
BTN_H        = 25;
GREETING_H   = 80;    % fixed height for the bold greeting label

%% Pre-read left-panel dimensions for top-aligned layout
videoFile    = fullfile(mibDir, 'assets', 'videos', 'celebration.mp4');

cheersFile   = fullfile(mibDir, 'assets', 'images', sprintf('puffin_cheering_%d_220px.png', randi(2)));
videoRowH = VIDEO_COL_W;  % default: assume square, updated after probe

if strcmp(mode, 'milestoneReached') && exist(videoFile, 'file')
    try
        vrInfo    = VideoReader(videoFile);
        videoRowH = round(VIDEO_COL_W * vrInfo.Height / vrInfo.Width);
        clear vrInfo;
    catch
    end
elseif strcmp(mode, 'currentStats') && exist(cheersFile, 'file')
    try
        info      = imfinfo(cheersFile);
        videoRowH = round(VIDEO_COL_W * info.Height / info.Width);
    catch
    end
end

%% Build figure
% Reuse a cached hidden figure when available
if ~isempty(cachedFigure) && isvalid(cachedFigure) && strcmp(cachedFigure.Visible, 'off')
    fig = cachedFigure;
    delete(fig.Children);
    fig.Name = dlgTitle;
    fig.CloseRequestFcn = 'closereq';
else
    fig = uifigure('Name', dlgTitle, 'Visible', 'off', 'Resize', 'on');
    fig.Tag = 'showMilestoneDialog';
    iconFile = fullfile(mibDir, 'assets', 'icons', 'mib_icon_16px.png');
    if exist(iconFile, 'file'); fig.Icon = iconFile; end
    cachedFigure = fig;
end
fig.WindowStyle = lower(windowStyle);
fig.Position = [fig.Position(1), fig.Position(2), WIN_W, WIN_H];

%% Root grid: [1 row × 2 cols]  -  video | content
rootGrid = uigridlayout(fig, [1, 2], ...
    'ColumnWidth', {VIDEO_COL_W, '1x'}, ...
    'RowHeight',   {'1x'}, ...
    'Padding',     [0 0 0 0], 'ColumnSpacing', 0);

%% ---- Left column: 2-row grid so video pins to top ----
leftGrid = uigridlayout(rootGrid, [2, 1], ...
    'RowHeight',   {videoRowH, '1x'}, ...
    'ColumnWidth', {'1x'}, ...
    'Padding',     [0 0 0 0], 'RowSpacing', 0);
leftGrid.Layout.Row    = 1;
leftGrid.Layout.Column = 1;

videoAx = uiaxes(leftGrid);
videoAx.Layout.Row    = 1;
videoAx.Layout.Column = 1;
videoAx.XTick = []; videoAx.YTick = [];
videoAx.Box   = 'off';
videoAx.Color = [0 0 0];
disableDefaultInteractivity(videoAx);

%% ---- Right column: content grid [3 rows] ----
contentGrid = uigridlayout(rootGrid, [3, 1], ...
    'RowHeight',    {GREETING_H, '1x', BTN_H}, ...
    'ColumnWidth',  {'1x'}, ...
    'Padding',      [12 10 12 10], 'RowSpacing', 6);
contentGrid.Layout.Row    = 1;
contentGrid.Layout.Column = 2;

% Row 1: greeting / header label (bold)
greetLbl = uilabel(contentGrid, ...
    'Text',       greetingText, ...
    'FontWeight', 'bold', ...
    'FontSize',   13, ...
    'WordWrap',   'on', ...
    'VerticalAlignment', 'top');
greetLbl.Layout.Row    = 1;
greetLbl.Layout.Column = 1;

% Row 2: scrollable stats text area (read-only)
statsArea = uitextarea(contentGrid, ...
    'Value',    bodyText, ...
    'Editable', 'off', ...
    'FontSize', 12, ...
    'FontName', 'Monospaced');
statsArea.Layout.Row    = 2;
statsArea.Layout.Column = 1;

% Row 3: button row  [Set stats file... | spacer | OK]
btnGrid = uigridlayout(contentGrid, [1, 3], ...
    'ColumnWidth', {160, '1x', 80}, ...
    'ColumnSpacing', 8, 'Padding', [0 0 0 0]);
btnGrid.Layout.Row    = 3;
btnGrid.Layout.Column = 1;

% "Set stats file..." button - only shown in currentStats mode
if strcmp(mode, 'currentStats')
    statsFileBtn = uibutton(btnGrid, ...
        'Text',    'Set stats file...', ...
        'Tooltip', sprintf('Choose a custom location for mib_user.mat\n(e.g. a synced network folder)\nThe current:\n%s', options.userStatsPath), ...
        'ButtonPushedFcn', @(~,~) onSetStatsFile());
    statsFileBtn.Layout.Column = 1;
end

% OK button
okBtn = uibutton(btnGrid, 'Text', okLabel, 'ButtonPushedFcn', @(~,~) onOK());
okBtn.Layout.Column = 3;

%% ---- Load left-panel media (video for milestone, image for currentStats) ----
videoTimer = [];
im_h = [];

if strcmp(mode, 'milestoneReached') && exist(videoFile, 'file')
    try
        vr = VideoReader(videoFile);
        firstFrame = readFrame(vr);
        im_h = image(videoAx, firstFrame);
        videoAx.XLim = [0.5, vr.Width  + 0.5];
        videoAx.YLim = [0.5, vr.Height + 0.5];
        videoAx.DataAspectRatio = [1 1 1];

        framePeriod = max(0.001, round(1000 / vr.FrameRate) / 1000);  % round to ms precision
        videoTimer  = timer('Period', framePeriod, ...
            'ExecutionMode', 'fixedRate', ...
            'TimerFcn',      @updateFrame, ...
            'ErrorFcn',      @(~,~) stopTimer());
        start(videoTimer);
    catch ME
        warning('showMilestoneDialog: could not load video: %s', ME.message);
    end
else
    if strcmp(mode, 'currentStats') && exist(cheersFile, 'file')
        mediaFile = cheersFile;
    else
        mediaFile = '';
    end
    if ~isempty(mediaFile)
        try
            img = imread(mediaFile);
            image(videoAx, img);
            videoAx.XLim = [0.5, size(img,2)+0.5];
            videoAx.YLim = [0.5, size(img,1)+0.5];
            videoAx.DataAspectRatio = [1 1 1];
        catch
        end
    end
end

%% Center on parent figure
if ~isempty(options.ParentFigure) && isvalid(options.ParentFigure)
    try
        if isa(options.ParentFigure, 'matlab.ui.container.internal.AppContainer')
            parentPos  = options.ParentFigure.WindowBounds;
            screenSize = get(0, 'ScreenSize');
            x1 = parentPos(1) + (parentPos(3) - WIN_W) / 2;
            y1 = screenSize(4) - parentPos(2) - parentPos(4) + (parentPos(4) - WIN_H) / 2;
        else
            parentPos = options.ParentFigure.Position;
            x1 = parentPos(1) + (parentPos(3) - WIN_W) / 2;
            y1 = parentPos(2) + (parentPos(4) - WIN_H) / 2;
        end
        fig.Position(1) = x1;
        fig.Position(2) = y1;
    catch
    end
end

%% Show and wait
fig.CloseRequestFcn = @(~,~) onClose();
fig.Visible = 'on';
drawnow;
% Re-apply WindowStyle on the realized (visible) figure - setting it while a
% cached figure is hidden does not take effect (notably in the deployed web
% engine), so the dialog would otherwise come up non-modal on reuse.
fig.WindowStyle = lower(windowStyle);
drawnow;
focus(okBtn);
uiwait(fig);

%% ---- Nested callbacks ----

    function updateFrame(~, ~)
        if ~isvalid(fig)
            stopTimer(); return;
        end
        if ~hasFrame(vr)
            try; vr.CurrentTime = 0; catch; end  % loop back to start
        end
        try
            im_h.CData = readFrame(vr);
        catch
            stopTimer();
        end
    end

    function stopTimer()
        if ~isempty(videoTimer) && isvalid(videoTimer)
            try; stop(videoTimer); catch; end
            try; delete(videoTimer); catch; end
            videoTimer = [];
        end
    end

    function onOK()
        stopTimer();
        fig.WindowStyle = 'normal';   % release modal grab before hiding (else parent stays blocked)
        fig.Visible = 'off';
        uiresume(fig);
    end

    function onClose()
        stopTimer();
        fig.WindowStyle = 'normal';   % release modal grab before hiding
        fig.Visible = 'off';
        uiresume(fig);
    end

    function onSetStatsFile()
        % Determine starting directory for the browser
        startPath = options.userStatsPath;
        if isempty(startPath)
            startDir = utils.getUserStatsDir();
            if isempty(startDir); startDir = utils.getPrefDir(); end
            startPath = fullfile(startDir, 'mib_user.mat');
        end

        pathname = uigetdir(fileparts(startPath), 'Specify location for mib_user.mat');
        if isequal(pathname, 0); return; end   % cancelled

        selectedPath = fullfile(pathname, 'mib_user.mat');

        % Compare collected points when an existing stats file was selected
        if isfile(selectedPath)
            try
                loadedVars = load(selectedPath, 'Tiers');
                if isfield(loadedVars, 'Tiers') && isfield(loadedVars.Tiers, 'collectedPoints')
                    currentPoints = 0;
                    if isfield(updatedTiers, 'collectedPoints')
                        currentPoints = updatedTiers.collectedPoints;
                    end
                    if loadedVars.Tiers.collectedPoints > currentPoints
                        updatedTiers = loadedVars.Tiers;
                        greetLbl.Text = sprintf( ...
                            'Richer stats loaded from:\n%s', selectedPath);
                    else
                        greetLbl.Text = sprintf( ...
                            'Stats file location set (current stats kept):\n%s', selectedPath);
                    end
                else
                    greetLbl.Text = sprintf('Stats file location set:\n%s', selectedPath);
                end
            catch
                greetLbl.Text = sprintf('Stats file location set:\n%s', selectedPath);
            end
        else
            % New location - save current stats there immediately so it exists on next load
            Tiers = updatedTiers;
            try
                destDir = fileparts(selectedPath);
                if ~exist(destDir, 'dir'); mkdir(destDir); end
                save(selectedPath, 'Tiers');
                greetLbl.Text = sprintf('Stats saved to new location:\n%s', selectedPath);
            catch saveErr
                greetLbl.Text = sprintf('Could not save to:\n%s\n%s', selectedPath, saveErr.message);
                return;
            end
        end

        newStatsPath = selectedPath;
        options.userStatsPath = selectedPath;   % prevent double-trigger
    end

end
