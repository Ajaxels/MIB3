function chosenFolder = chooseUserStatsLocation(ParentFigure, currentFolder, options)
% CHOOSEUSERSTATSLOCATION - Ask where MIB should keep the user statistics.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      chosenFolder = chooseUserStatsLocation(ParentFigure, currentFolder)
%      chosenFolder = chooseUserStatsLocation(ParentFigure, currentFolder, options)
%
% Presents the locations found by :func:`utils.getUserStatsCandidates` and
% lets the user pick one, or browse for any other folder.  The selected
% folder is created before the function returns, so the caller can write a
% shard into it straight away with :func:`utils.saveUserStats`.
%
% The dialog is used from two places: the one-time prompt shown on the first
% start of MIB on a workstation (``controllers.MibController.initialize``)
% and the **Set stats file...** button of
% :func:`utils.dlgs.showMilestoneDialog`.  The ``firstRun`` option only
% changes the wording.
%
% Selecting a folder does not move any existing statistics.  Because each
% workstation writes its own shard file, pointing several machines at the
% same shared folder is all that is needed for their statistics to add up;
% the dialog previews the total already stored in the highlighted folder so
% that the user can see this happening.
%
% Input Arguments:
%   - **ParentFigure** - handle to the parent window (AppContainer, uifigure
%     or ``[]``), used to center the dialog
%   - **currentFolder** - [char] folder currently in use, preselected in the
%     list.  Pass ``''`` when there is none
%   - **options** *(optional)* - struct with fields:
%
%     - ``.mibPath`` - [char] MIB installation directory, used to find the
%       window icon. Default: resolved from ``which('mib3')``
%     - ``.tierPointsCoef`` - [numeric] passed to :func:`utils.loadUserStats`
%       for the preview. Default: ``500``
%     - ``.firstRun`` - [logical] when ``true`` the dialog is worded as the
%       one-time question asked on a new workstation. Default: ``false``
%
% Output Arguments:
%   - **chosenFolder** - [char] full path of the selected folder, or ``''``
%     when the user cancelled
%
% Usage:
%
%   **Example 1** - ask once on a new workstation
%
%   .. code-block:: matlab
%
%      statsFolder = fileparts(obj.mibModel.preferences.System.UserStatsProfile);
%      chosenFolder = utils.dlgs.chooseUserStatsLocation(obj.view.gui, statsFolder, ...
%          struct('mibPath', obj.mibModel.mibPath, 'firstRun', true));
%
% See also: utils.getUserStatsCandidates, utils.loadUserStats,
% utils.saveUserStats, utils.dlgs.showMilestoneDialog

arguments
    ParentFigure = []
    currentFolder (1,:) char = ''
    options struct = struct()
end

if ~isfield(options, 'mibPath');        options.mibPath = ''; end
if ~isfield(options, 'tierPointsCoef'); options.tierPointsCoef = 500; end
if ~isfield(options, 'firstRun');       options.firstRun = false; end

chosenFolder = '';

%% Collect the locations to offer
candidates = utils.getUserStatsCandidates();

% Keep the folder already in use at the top of the list when it is not one
% of the detected candidates (for example a folder picked by hand earlier)
if ~isempty(currentFolder) && ...
        ~any(strcmpi({candidates.folder}, currentFolder))
    currentEntry = struct( ...
        'label',  'Current location', ...
        'folder', currentFolder, ...
        'note',   'The folder MIB is using at the moment', ...
        'syncs',  false);
    candidates = [currentEntry, candidates];
end

%% Wording
if options.firstRun
    headerText = 'Where should MIB keep your statistics?';
    introText = ['MIB counts the tools you use and the distance you travel with the mouse. ', ...
        'Pick a folder that is available from every computer you use and your statistics ', ...
        'will add up across all of them. Each computer writes its own file, so nothing is ', ...
        'ever overwritten. You can change this later from Home -> Help -> Your stats.'];
else
    headerText = 'Location of your MIB statistics';
    introText = ['Pick a folder that is available from every computer you use and your ', ...
        'statistics will add up across all of them. Each computer writes its own file ', ...
        'into this folder, so nothing is ever overwritten.'];
end

%% Build the window
mibDir = options.mibPath;
if isempty(mibDir)
    mibDir = fileparts(which('mib3'));
    if isempty(mibDir); mibDir = pwd; end
end

WIN_W = 620;
WIN_H = 470;

fig = uifigure('Name', 'MIB statistics location', 'Visible', 'off', 'Resize', 'on');
fig.Tag = 'chooseUserStatsLocation';
iconFile = fullfile(mibDir, 'assets', 'icons', 'mib_icon_16px.png');
if exist(iconFile, 'file'); fig.Icon = iconFile; end
fig.Position = [fig.Position(1), fig.Position(2), WIN_W, WIN_H];

% The icon takes a fixed column on the left of the header and the intro text,
% the same layout the ResampleDataset dialog uses. The rows below span both
% columns so the list keeps the full width of the window
rootGrid = uigridlayout(fig, [5, 2], ...
    'RowHeight',   {28, 96, '1x', 66, 26}, ...
    'ColumnWidth', {96, '1x'}, ...
    'Padding', [12 10 12 10], 'RowSpacing', 8, 'ColumnSpacing', 10);

iconImage = uiimage(rootGrid, ...
    'VerticalAlignment', 'top', 'HorizontalAlignment', 'left');
iconImage.Layout.Row = [1 2];
iconImage.Layout.Column = 1;
iconImagePath = fullfile(mibDir, 'assets', 'images', 'image_arithmetics_96px.png');
if exist(iconImagePath, 'file'); iconImage.ImageSource = iconImagePath; end

headerLabel = uilabel(rootGrid, ...
    'Text', headerText, 'FontWeight', 'bold', 'FontSize', 13, ...
    'VerticalAlignment', 'center');
headerLabel.Layout.Row = 1;
headerLabel.Layout.Column = 2;

introLabel = uilabel(rootGrid, ...
    'Text', introText, 'WordWrap', 'on', 'VerticalAlignment', 'top');
introLabel.Layout.Row = 2;
introLabel.Layout.Column = 2;

locationList = uilistbox(rootGrid, ...
    'Items', i_listItems(candidates), ...
    'ItemsData', 1:numel(candidates), ...
    'ValueChangedFcn', @(~,~) updateDetails());
locationList.Layout.Row = 3;
locationList.Layout.Column = [1 2];

detailsLabel = uilabel(rootGrid, ...
    'Text', '', 'WordWrap', 'on', 'VerticalAlignment', 'top', ...
    'FontName', 'Monospaced');
detailsLabel.Layout.Row = 4;
detailsLabel.Layout.Column = [1 2];

buttonGrid = uigridlayout(rootGrid, [1, 4], ...
    'ColumnWidth', {150, '1x', 90, 90}, ...
    'ColumnSpacing', 8, 'Padding', [0 0 0 0]);
buttonGrid.Layout.Row = 5;
buttonGrid.Layout.Column = [1 2];

browseButton = uibutton(buttonGrid, 'Text', 'Other folder...', ...
    'Tooltip', 'Browse for any other folder, for example a shared network drive', ...
    'ButtonPushedFcn', @(~,~) onBrowse());
browseButton.Layout.Column = 1;

cancelButton = uibutton(buttonGrid, 'Text', 'Cancel', ...
    'ButtonPushedFcn', @(~,~) onCancel());
cancelButton.Layout.Column = 3;

okButton = uibutton(buttonGrid, 'Text', 'Use this', ...
    'ButtonPushedFcn', @(~,~) onOK());
okButton.Layout.Column = 4;

% Preselect the folder in use, otherwise the first (best) candidate
selectedIndex = 1;
if ~isempty(currentFolder)
    matchIndex = find(strcmpi({candidates.folder}, currentFolder), 1);
    if ~isempty(matchIndex); selectedIndex = matchIndex; end
end
locationList.Value = selectedIndex;
updateDetails();

%% Center on the parent window
if ~isempty(ParentFigure) && isvalid(ParentFigure)
    try
        if isa(ParentFigure, 'matlab.ui.container.internal.AppContainer')
            parentPos  = ParentFigure.WindowBounds;
            screenSize = get(0, 'ScreenSize');
            fig.Position(1) = parentPos(1) + (parentPos(3) - WIN_W) / 2;
            fig.Position(2) = screenSize(4) - parentPos(2) - parentPos(4) + (parentPos(4) - WIN_H) / 2;
        else
            parentPos = ParentFigure.Position;
            fig.Position(1) = parentPos(1) + (parentPos(3) - WIN_W) / 2;
            fig.Position(2) = parentPos(2) + (parentPos(4) - WIN_H) / 2;
        end
    catch
    end
end

fig.CloseRequestFcn = @(~,~) onCancel();
fig.Visible = 'on';
drawnow;
% Re-apply WindowStyle once the figure is realized - setting it while hidden
% does not take effect in the deployed web engine
fig.WindowStyle = 'modal';
drawnow;
focus(okButton);
uiwait(fig);

%% ---- Nested callbacks ----

    function updateDetails()
        entry = candidates(locationList.Value);
        [totalTiers, ~, shardNames] = utils.loadUserStats(entry.folder, ...
            'tierPointsCoef', options.tierPointsCoef);
        if isempty(totalTiers) || ~isfield(totalTiers, 'collectedPoints')
            foundText = 'no statistics stored here yet';
        else
            foundText = sprintf('%.0f points from %d computer(s) stored here', ...
                totalTiers.collectedPoints, numel(shardNames));
        end
        detailsLabel.Text = sprintf('%s\n%s\n%s', entry.folder, entry.note, foundText);
    end

    function onBrowse()
        % Start the browser at the highlighted candidate. Most candidates are
        % folders MIB would only create on the first save, so walk up to the
        % nearest existing parent instead of dropping the user somewhere
        % unrelated - landing in the OneDrive root beats landing in prefdir.
        startDir = candidates(locationList.Value).folder;
        while ~isempty(startDir) && ~isfolder(startDir)
            parentDir = fileparts(startDir);
            if strcmp(parentDir, startDir); break; end   % reached the drive root
            startDir = parentDir;
        end
        if ~isfolder(startDir); startDir = utils.getPrefDir(); end

        pathName = uigetdir(startDir, 'Select a folder for the MIB statistics');
        figure(fig);   % uigetdir drops the modal focus
        if isequal(pathName, 0); return; end

        existingIndex = find(strcmpi({candidates.folder}, pathName), 1);
        if isempty(existingIndex)
            candidates(end+1) = struct( ...
                'label',  'Selected folder', ...
                'folder', pathName, ...
                'note',   'Folder you picked', ...
                'syncs',  false);
            locationList.Items = i_listItems(candidates);
            locationList.ItemsData = 1:numel(candidates);
            existingIndex = numel(candidates);
        end
        locationList.Value = existingIndex;
        updateDetails();
    end

    function onOK()
        entry = candidates(locationList.Value);
        try
            if ~isfolder(entry.folder); mkdir(entry.folder); end
        catch createErr
            uialert(fig, sprintf('The folder could not be created:\n%s\n\n%s', ...
                entry.folder, createErr.message), 'Statistics location');
            return;
        end
        % Keep the folder hydrated when it lives in OneDrive, otherwise
        % Files-On-Demand may evict it and the load would need the network
        if ispc && strcmp(entry.label, 'OneDrive')
            try
                system(sprintf('attrib +P "%s" /S /D', entry.folder));
            catch
            end
        end
        chosenFolder = entry.folder;
        fig.WindowStyle = 'normal';   % release the modal grab before closing
        uiresume(fig);
        delete(fig);
    end

    function onCancel()
        chosenFolder = '';
        fig.WindowStyle = 'normal';
        uiresume(fig);
        delete(fig);
    end

end

% =====================================================================

function items = i_listItems(candidates)
% Build the display strings of the list box

items = cell(1, numel(candidates));
for entryId = 1:numel(candidates)
    items{entryId} = sprintf('%s   (%s)', ...
        candidates(entryId).label, candidates(entryId).folder);
end

end
