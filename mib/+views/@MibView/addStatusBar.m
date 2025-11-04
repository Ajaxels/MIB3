function addStatusBar(obj)
% function addStatusBar(obj)
% Add status bar to MIB as matlab.ui.internal.statusbar.StatusBar()
% stored in obj.handles.status.*

arguments (Input)
    obj views.MibView
end

%% create status bar
obj.handles.status.bar = matlab.ui.internal.statusbar.StatusBar();

%% Create statusBarGroupWorkingDirectory to keep the working directory
statusBarGroupWorkingDirectory = matlab.ui.internal.statusbar.StatusGroup();
sLabel = matlab.ui.internal.statusbar.StatusLabel();
sLabel.Text = "Working directory:";
statusBarGroupWorkingDirectory.add(sLabel);

obj.handles.status.selectWorkingDirectory = matlab.ui.internal.statusbar.StatusButton();
obj.handles.status.selectWorkingDirectory.Description = "Use the system directory selection dialog to define the working directory";
obj.handles.status.selectWorkingDirectory.Icon = matlab.ui.internal.toolstrip.Icon.OPEN_16;
obj.handles.status.selectWorkingDirectory.ButtonPushedFcn = @(~, ~) disp("Status button pressed");
statusBarGroupWorkingDirectory.add(obj.handles.status.selectWorkingDirectory);

obj.handles.status.currentDirectory = matlab.ui.internal.statusbar.StatusEditField();
obj.handles.status.currentDirectory.Value = pwd;
obj.handles.status.currentDirectory.Description = "Enter the working directory";
obj.handles.status.currentDirectory.Width = 570;
%obj.handles.status.currentDirectory.ValueChangedFcn = @(s, e) disp(e);
statusBarGroupWorkingDirectory.add(obj.handles.status.currentDirectory);

obj.handles.status.copyPath = matlab.ui.internal.statusbar.StatusButton();
obj.handles.status.copyPath.Description = "Copy the current working directory to clipboard";
obj.handles.status.copyPath.Icon = matlab.ui.internal.toolstrip.Icon.COPY_16;
obj.handles.status.copyPath.ButtonPushedFcn = @(~, ~) disp("Copy button pressed");
statusBarGroupWorkingDirectory.add(obj.handles.status.copyPath);

obj.handles.status.openBrowser = matlab.ui.internal.statusbar.StatusButton();
obj.handles.status.openBrowser.Description = "Open the current working directory in a system file browser";
obj.handles.status.openBrowser.Icon = matlab.ui.internal.toolstrip.Icon.BROWSE_16;
obj.handles.status.openBrowser.ButtonPushedFcn = @(~, ~) disp("Open browser button pressed");
statusBarGroupWorkingDirectory.add(obj.handles.status.openBrowser);

% add group a to the statusbar
obj.handles.status.bar.add(statusBarGroupWorkingDirectory);




%% Create statusBarGroupPixels to keep information about the current pixel
statusBarGroupPixels = matlab.ui.internal.statusbar.StatusGroup();
obj.handles.status.pixelLabel = matlab.ui.internal.statusbar.StatusLabel();
obj.handles.status.pixelLabel.Text = "Pixel: XXXXX:XXXXX (RRRRR:GGGGG:BBBBB)";
statusBarGroupPixels.add(obj.handles.status.pixelLabel);
% add group a to the statusbar
obj.handles.status.bar.add(statusBarGroupPixels);

%% Add progress status bar widget
statusBarGroupProgress = matlab.ui.internal.statusbar.StatusGroup();

obj.handles.status.progressLabel = matlab.ui.internal.statusbar.StatusLabel();
obj.handles.status.progressLabel.Text = "Progress:";
statusBarGroupProgress.add(obj.handles.status.progressLabel);
obj.handles.status.progressBar = matlab.ui.internal.statusbar.StatusProgressBar();
obj.handles.status.progressBar.Description = 'obj.view.handles.status.progressBar';
obj.handles.status.progressBar.Value = 0;
obj.handles.status.progressBar.Indeterminate = false; % continious change
obj.handles.status.progressBar.Width = 60;
% add the progress bar to the group
statusBarGroupProgress.Region = 'right';
statusBarGroupProgress.add(obj.handles.status.progressBar)

% add the group to the status bar
obj.handles.status.bar.add(statusBarGroupProgress);

%% Create group for the info/log/zoom values
statusBarGroupInfo = matlab.ui.internal.statusbar.StatusGroup();

obj.handles.status.logButton = matlab.ui.internal.statusbar.StatusButton();
%obj.handles.status.logButton.Text = "Log";
obj.handles.status.logButton.Description = "Show the log of actions performed with the dataset";
obj.handles.status.logButton.Icon = matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/zoom100_16px.png'));
obj.handles.status.logButton.ButtonPushedFcn = @(~, ~) disp("Log button pressed");
statusBarGroupInfo.add(obj.handles.status.logButton);

obj.handles.status.infoButton = matlab.ui.internal.statusbar.StatusButton();
%obj.handles.status.infoButton.Text = "Info";
obj.handles.status.infoButton.Description = "Dataset properties";
obj.handles.status.infoButton.Icon = matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/zoomFit_16px.png'));
obj.handles.status.infoButton.ButtonPushedFcn = @(~, ~) disp("Info button pressed");
statusBarGroupInfo.add(obj.handles.status.infoButton);

sLabel = matlab.ui.internal.statusbar.StatusLabel();
sLabel.Text = "Zoom:";
statusBarGroupInfo.add(sLabel);

obj.handles.status.zoom = matlab.ui.internal.statusbar.StatusEditField();
obj.handles.status.zoom.Value = '100 %';
obj.handles.status.zoom.Width = 50;
%obj.handles.status.zoom.ValueChangedFcn = @(s, e) disp(e);
statusBarGroupInfo.add(obj.handles.status.zoom);

statusBarGroupInfo.Region = 'right';
obj.handles.status.bar.add(statusBarGroupInfo);

% add status bar to MIB
obj.gui.add(obj.handles.status.bar);

end