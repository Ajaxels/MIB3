function statusHandles = addStatusBar(obj)
% ADDSTATUSBAR - Add status bar to MIB as matlab.ui.internal.statusbar.StatusBar().
%
% Syntax:
%   function statusHandles = addStatusBar(obj)
%
% stored in statusHandles.*

arguments (Input)
    obj views.MibView
end

%% create status bar
statusHandles.bar = matlab.ui.internal.statusbar.StatusBar();

%% Create statusBarGroupWorkingDirectory to keep the working directory
statusBarGroupWorkingDirectory = matlab.ui.internal.statusbar.StatusGroup();
sLabel = matlab.ui.internal.statusbar.StatusLabel();
sLabel.Text = "Working directory:";
statusBarGroupWorkingDirectory.add(sLabel);

statusHandles.selectWorkingDirectory = matlab.ui.internal.statusbar.StatusButton();
statusHandles.selectWorkingDirectory.Description = "Use the system directory selection dialog to define the working directory";
statusHandles.selectWorkingDirectory.Icon = matlab.ui.internal.toolstrip.Icon.OPEN_16;
statusBarGroupWorkingDirectory.add(statusHandles.selectWorkingDirectory);

statusHandles.currentDirectory = matlab.ui.internal.statusbar.StatusEditField();
statusHandles.currentDirectory.Value = pwd;
statusHandles.currentDirectory.Description = "Enter the working directory";
statusHandles.currentDirectory.Width = 570;
statusBarGroupWorkingDirectory.add(statusHandles.currentDirectory);

statusHandles.copyPath = matlab.ui.internal.statusbar.StatusButton();
statusHandles.copyPath.Description = "Copy the current working directory to clipboard";
statusHandles.copyPath.Icon = matlab.ui.internal.toolstrip.Icon.COPY_16;
statusBarGroupWorkingDirectory.add(statusHandles.copyPath);

statusHandles.openBrowser = matlab.ui.internal.statusbar.StatusButton();
statusHandles.openBrowser.Description = "Open the current working directory in a system file browser";
statusHandles.openBrowser.Icon = matlab.ui.internal.toolstrip.Icon.BROWSE_16;
statusBarGroupWorkingDirectory.add(statusHandles.openBrowser);

% add group a to the status bar
statusHandles.bar.add(statusBarGroupWorkingDirectory);

%% Create statusBarGroupPixels to keep information about the current pixel
statusBarGroupPixels = matlab.ui.internal.statusbar.StatusGroup();
statusHandles.pixelLabel = matlab.ui.internal.statusbar.StatusLabel();
statusHandles.pixelLabel.Text = "Pixel: XXXXX:XXXXX (RRRRR:GGGGG:BBBBB)";
statusBarGroupPixels.add(statusHandles.pixelLabel);
% add group a to the statusbar
statusHandles.bar.add(statusBarGroupPixels);

%% Add progress status bar widget
statusBarGroupProgress = matlab.ui.internal.statusbar.StatusGroup();

statusHandles.progressLabel = matlab.ui.internal.statusbar.StatusLabel();
statusHandles.progressLabel.Text = "Progress:";
statusBarGroupProgress.add(statusHandles.progressLabel);
statusHandles.progressBar = matlab.ui.internal.statusbar.StatusProgressBar();
statusHandles.progressBar.Description = 'obj.view.handles.status.progressBar';
statusHandles.progressBar.Value = 0;
statusHandles.progressBar.Indeterminate = false; % continious change
statusHandles.progressBar.Width = 60;
% add the progress bar to the group
statusBarGroupProgress.Region = 'right';
statusBarGroupProgress.add(statusHandles.progressBar)

% add the group to the status bar
statusHandles.bar.add(statusBarGroupProgress);

%% Create group for the info/log/zoom values
statusBarGroupInfo = matlab.ui.internal.statusbar.StatusGroup();

sLabel = matlab.ui.internal.statusbar.StatusLabel();
sLabel.Text = "Zoom:";
statusBarGroupInfo.add(sLabel);

statusHandles.zoom = matlab.ui.internal.statusbar.StatusEditField();
statusHandles.zoom.Value = '100 %';
statusHandles.zoom.Width = 50;
statusHandles.zoom.Description = 'Define the zoom level';
statusBarGroupInfo.add(statusHandles.zoom);

statusBarGroupInfo.Region = 'right';
statusHandles.bar.add(statusBarGroupInfo);

obj.handles.status = statusHandles;

% add status bar to MIB
obj.gui.add(statusHandles.bar);

% add handle tags to the status bar
if obj.mibModel.preferences.System.DeveloperMode
    utils.overrideDescriptions(statusHandles, true, 'obj.cStatus.view.handles');
end

end
