function initialize(obj)
% INITIALIZE - Initialize the main MibController class.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.initialize()
%
% Output Arguments:
%   (none)
%

arguments (Input)
    obj controllers.MibController
end

% tweaks
showSplashScreen = false;

% ---- show splash screen
if showSplashScreen
    [hSplashScreen, hSplashAxes, hLabel] = obj.showSplashScreen(sprintf('MIB %s', obj.mibVersion), sprintf('Staring MIB\n%s\nPlease wait...', obj.mibVersion));
    %hLabel.String = 'adding something else';
end

% generate the resource file for icons and images
assetsDir = fullfile(obj.mibPath, 'assets');
resourceFile  = fullfile(obj.mibPath, 'assets', 'mib_icons.res');
if ~isfile(resourceFile)
    core.MibIconCache.buildResourceFile(assetsDir, resourceFile);
    % usage example:
    % imgBrush = core.MibIconCache.get('about_16px');         % loads from the resource class on first call
    % h.brushButton.Icon = imgBrush;
end

% Initialize all external libraries and Java paths
obj.initializeLibraries();   

% get the current version of Matlab
obj.matlabVersion = obj.mibModel.matlabVersion;

%% ----------------- INIT THE MAIN VIEW -----------------
obj.view = views.MibView(obj);
obj.mibModel.mibGUI = obj.view.gui;
obj.mibModel.mibController = obj;   % back-reference, used by MibModel.getProgressBarParent to reach the active document
% --- create controller for panels and add view into them
obj.addGuiControllers();

% ---- add callbacks ----
% add callback for selection of the
obj.view.handles.ribbon.global.SelectedTabChangedFcn = @(~, ~)obj.globalTabGroup_SelectionCallback;


if obj.mibModel.preferences.System.EnableSelection
    obj.view.brushCursorShow =  true;
else
    obj.view.brushCursorShow =  false;
end

% --------- update listeners
% callback for change of properties in obj.view.handles.imageViewDocGroup, used to track selection of panels in the image view panel
obj.listeners{1} = addlistener(obj.view.handles.imageViewDocGroup, 'PropertyChanged', @obj.listener_appStateChanged);
obj.listeners{end+1} = addlistener(obj.mibModel, 'NewDataset', @(src, evnt) obj.listener_newDataset(src, evnt)); % update toolbar buttons
obj.listeners{end+1} = addlistener(obj.mibModel, 'ShowErrorDialog', @(src, evnt) obj.listener_showErrorDialog(src, evnt));
obj.listeners{end+1} = addlistener(obj.mibModel, 'ShowImage', @(src, evnt) obj.listener_showImage(src, evnt));
obj.listeners{end+1} = addlistener(obj.mibModel, 'UpdateDatasetAxes', @(src, evnt) obj.listener_updateDatasetAxes(src, evnt));
obj.listeners{end+1} = addlistener(obj.mibModel, 'UpdateToolbar', @(src, evnt) obj.listener_updateToolbar(src, evnt)); % update toolbar buttons
obj.listeners{end+1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src, evnt) obj.listener_updateGuiWidgets(src, evnt)); % update GUI widgets
obj.listeners{end+1} = addlistener(obj.mibModel, 'UpdateUserScore', @(src, evnt) obj.listner_ModelEvent(src, evnt)); % update GUI widgets
obj.listeners{end+1} = addlistener(obj.mibModel, 'KeyPressEvent', @(src,evnt) obj.listner_ModelEvent(src, evnt));

%obj.listeners{end+1} = addlistener(obj.model, 'modelNotify', @(src, evnt) obj.listner_ModelEvent_Callback(src, evnt));
%obj.listeners{end+1} = addlistener(obj.model, 'modelNotify', @obj.listner_ModelEvent_Callback);
%obj.listeners{end+1} = addlistener(obj.model, 'keyPressEvent', @obj.listner2_Callback);
%obj.listeners{end+1} = addlistener(obj.model, 'newFileCreated', @obj.listner2_Callback);

% Make the GUI visible
drawnow;
obj.view.gui.Visible = true;


if showSplashScreen; hSplashScreen.focus; end  % focus on the splash screen
%pause(2);

% do GUI post-initialization tasks that require GUI to be visible
obj.view.doPostInitializationTasks();

% show image
obj.showImage();

if showSplashScreen
    %hLabel.String = 'finishing'; drawnow nocallbacks;
    % close the splash screen
    delete(hSplashScreen);
end

if obj.mibModel.preferences.Tips.ShowTips == 1
    try     % on MacOs this gives an error
        obj.startController('controllers.WelcomeTips');
    catch err
        obj.mibModel.preferences.Tips.ShowTips = false;
    end
end

% check for update
currentDate = floor(now);  %#ok<TNOW1>
if currentDate - obj.mibModel.preferences.System.Update.SinceLastCheck > ...
        obj.mibModel.preferences.System.Update.RecheckPeriod
    obj.mibModel.preferences.System.Update.SinceLastCheck = currentDate;
    if isdeployed
        if ismac
            link = 'http://mib.helsinki.fi/web-update/mib3_mac.txt';
        elseif isunix
            link = 'http://mib.helsinki.fi/web-update/mib3_linux.txt';
        else
            link = 'http://mib.helsinki.fi/web-update/mib3_win.txt';
        end
    else
        link = 'http://mib.helsinki.fi/web-update/mib3_matlab.txt';
    end
    try
        urlText = urlread(link, 'Timeout', 4);  %#ok<URLRD>
    catch
        urlText = '0';
    end
    linefeedPositions = strfind(urlText, sprintf('\n'));
    if ~isempty(linefeedPositions)
        availableVersion = str2double(urlText(1:linefeedPositions(1)));
    else
        availableVersion = str2double(urlText);
    end
    mibVersionNumeric = utils.getMibVersionNumberic(obj.mibModel.mibVersion);
    if availableVersion - mibVersionNumeric > 0
        answer = utils.dlgs.inputQuestDlg(obj.mibModel.getProgressBarParent(), ...
            sprintf('A new version %g of MIB is available!\nWould you like to download/install it?\n\nYou can always do that later via Help \x2192 Check for Update.', availableVersion), ...
            'New version available', 'Update now', 'Later', 'Update now');
        if strcmp(answer, 'Update now')
            obj.startController('controllers.UpdateCheck', obj);
        end
    end
end

end
